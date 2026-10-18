extends SceneTree

const Pipeline=preload("res://scripts/simulation/unified_edit/pipeline.gd")
const Config=preload("res://scripts/simulation/unified_edit/configuration.gd")
const Domain=preload("res://scripts/simulation/sand_water_domain.gd")
const L=preload("res://scripts/simulation/unified_edit/layout.gd")
var pipeline:=Pipeline.new()
var checks: Array=[]
var failed:=false
var output:=""
var registry
var fields: Dictionary={}
var remaining:=0
var started:=0
var domain
var source_hashes: Dictionary={}
var probe_case:="normal"
var armed:=false
var water_decision:=PackedByteArray()
var reference_state
var reference_ready:=false

func check(name: String, value: bool) -> void:
	checks.append({"name":name,"pass":value});failed=failed or not value
	print("UNIFIED_GPU ",name," ",value)

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
		if arg.begins_with("--case="):probe_case=arg.trim_prefix("--case=")
	call_deferred("_run")

func _process(_delta: float) -> bool:
	pipeline.pump()
	return false

func request(id: int, profile_id: StringName, point: Vector2, amount: float=0.05) -> Dictionary:
	var profile: Dictionary=registry.profile(profile_id)
	var value:={"domain_id":"main_beach","generation":9007199254740993,"command_id":id,"sim_tick":pipeline.completed_tick,"profile_id":profile_id,"profile_version":1,"profile_hash":profile.profile_hash,"start_xz_m":point,"parameters":{"amount_m3":amount},"features":{"water_policy":0}}
	if profile.shape==L.Profile.Shape.SWEPT_CAPSULE:value.end_xz_m=point+Vector2(1,0.4)
	return value

func await_idle() -> void:
	var begin:=Time.get_ticks_msec()
	while pipeline.fault_reason().is_empty() and (pipeline.pending_count()>0 or pipeline.active_count()>0) and Time.get_ticks_msec()-begin<15000:await process_frame
	check("idle_before_deadline_"+str(checks.size()),pipeline.pending_count()==0 and pipeline.active_count()==0 and pipeline.fault_reason().is_empty())
	if not pipeline.fault_reason().is_empty():print("PIPELINE_FAULT ",pipeline.fault_reason())

func _read_render() -> void:
	var device: RenderingDevice=pipeline.state.rd
	for pair in [["sand",pipeline.state.textures.sand[0]],["sand_spare",pipeline.state.textures.sand[1]],["water",pipeline.state.textures.water[0]],["qx",pipeline.state.textures.momentum_x[0]],["published",pipeline.state.published_sand]]:
		if device.texture_get_data_async(pair[1],0,_field_render.bind(pair[0]))!=OK:call_deferred("_read_failed",pair[0])
	if device.buffer_get_data_async(pipeline.transport.control,_field_render.bind("control"),0,L.CONTROL_BYTES)!=OK:call_deferred("_read_failed","control")

func _field_render(bytes: PackedByteArray, field: String) -> void:call_deferred("_field",bytes,field)
func _field(bytes: PackedByteArray, field: String) -> void:fields[field]=bytes;remaining-=1
func _read_failed(field: String) -> void:check("readback_"+field,false);remaining-=1

func finish() -> void:
	var data:={"pass":not failed,"case":probe_case,"checks":checks,"fault":String(pipeline.fault_reason()),"source_hashes":source_hashes,"traces":pipeline.executor.traces,"engine":Engine.get_version_info(),"elapsed_ms":Time.get_ticks_msec()-started,"scope":"isolated real main RenderingDevice volume edits and retained water tick; no final visual/cost or complete tool migration claim"}
	if not output.is_empty():
		var raw:={}
		for field in fields:
			var path:=output.get_base_dir()+"/"+String(field)+".bin"
			var file:=FileAccess.open(path,FileAccess.WRITE)
			if file==null:check("raw_write_"+String(field),false);continue
			file.store_buffer(fields[field]);file.close()
			raw[field]={"path":path,"bytes":fields[field].size(),"sha256":FileAccess.get_sha256(path)}
		var initial: Dictionary={} if domain==null else {"domain_id":domain.domain_id,"generation":domain.generation,"sand":domain.sand,"water":domain.water,"momentum_x":domain.get_meta("edit_validation_initial_qx",PackedFloat32Array())}
		var typed:={"initial_domain":initial,"consumed_configuration":pipeline._configuration.duplicate(true),"final_terminal_results":pipeline._results.duplicate(true),"arrival_order":pipeline.arrival_order.duplicate(),"raw_capture_control":fields.get("control",PackedByteArray()),"capture_note":"normal fields/control captured after first five edits and one water tick; subsequent scheduling and 64-command results are separate later observations; fault control is raw GPU truth, not a manufactured CPU completion"}
		var typed_path:=output.get_base_dir()+"/typed_evidence.variant"
		FileAccess.open(typed_path,FileAccess.WRITE).store_buffer(var_to_bytes(typed))
		data.raw_fields=raw;data.typed_evidence={"path":typed_path,"sha256":FileAccess.get_sha256(typed_path)}
		data.output_size=DisplayServer.window_get_size();data.vsync=DisplayServer.window_get_vsync_mode()
		data.pass=not failed
	if not output.is_empty():FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(data,"\t"))
	quit(1 if failed else 0)

func _run() -> void:
	started=Time.get_ticks_msec()
	DisplayServer.window_set_size(Vector2i(1280,720));DisplayServer.window_set_title("Unified edit pipeline GPU contract")
	var created: Dictionary=load("res://assets/unified_edit/default_catalog.tres").instantiate_registry()
	check("registry",created.error.is_empty());registry=created.registry
	var simulation:={"enable_erosion":false,"enable_brush_water":true,"unrestricted_sand_tools":true,"enable_structures":false,"local_front_history":false,"rise_front_history":false,"contact_history":false}
	var extras:=PackedStringArray(Pipeline.SOURCE_PATHS+Pipeline.ADAPTER_SOURCES)
	var configuration:=Config.freeze(registry,"main_beach",simulation,{"foam_enabled":false,"gravel_enabled":false},{},{"engine":Engine.get_version_info().string,"test":"real_gpu_contract"},extras)
	check("configuration",configuration.error.is_empty())
	if not configuration.error.is_empty():finish();return
	source_hashes=configuration.value.sources.duplicate(true)
	check("configure",pipeline.configure(registry,configuration.value,9007199254740993).is_empty())
	domain=Domain.new(256,0.125);domain.domain_id=&"main_beach";domain.generation=9007199254740993
	domain.sand.fill(0.4);domain.water.fill(0.15)
	if probe_case.begins_with("water_"):
		domain.water.fill(0.1)
		var desired:=int(probe_case.trim_prefix("water_"));var speed: float=(float(desired)-0.25)*0.35*0.125/0.001
		var momentum:=PackedFloat32Array();momentum.resize(65536);momentum.fill(maxf(0.0,speed-sqrt(9.81*0.1))*0.1)
		domain.set_meta("edit_validation_initial_qx",momentum)
	RenderingServer.call_on_render_thread(pipeline.initialize_render.bind(domain))
	while not pipeline.initialized and Time.get_ticks_msec()-started<20000:await process_frame
	check("real_gpu_initialize",pipeline.initialized and pipeline.fault_reason().is_empty())
	if not pipeline.fault_reason().is_empty():print(pipeline.fault_reason());finish();return
	if probe_case.begins_with("water_"):
		await run_water_reference(int(probe_case.trim_prefix("water_")));finish();return
	if probe_case!="normal":
		await run_fault_case();finish();return
	RenderingServer.call_on_render_thread(_reorder_render)
	while not armed:await process_frame
	for pair in [[1,&"fill_v1",Vector2.ZERO],[2,&"dig_v1",Vector2(2,1)],[3,&"fill_sweep_v1",Vector2(-2,0)],[4,&"dig_sweep_v1",Vector2(0,2)]]:
		check("admit_"+str(pair[0]),pipeline.submit_intent(request(pair[0],pair[1],pair[2])).accepted)
	check("admit_real_water",pipeline.request_tick(1.0/30.0).is_empty())
	check("admit_post_tick",pipeline.submit_intent(request(5,&"fill_v1",Vector2(1,-2))).accepted)
	# All three work units are accepted before any CPU result consumption.
	pipeline.hold_completions=true;pipeline.pump()
	check("three_work_units_record_ahead",pipeline.active_count()==3 and pipeline.pending_count()==0)
	pipeline.hold_completions=false
	await await_idle()
	if not pipeline.fault_reason().is_empty():finish();return
	var net:=0.0
	for id in range(1,6):
		var result:=pipeline.result(id)
		check("actual_result_"+str(id),not result.is_empty() and result.outcome==L.Outcome.APPLIED)
		if not result.is_empty():net+=result.added_m3-result.removed_m3
	check("ordered_state_and_revision",pipeline.completed_state_seq==3 and pipeline.completed_tick==1 and pipeline.completed_revision>=5 and pipeline.advanced_time_s>0.0)
	check("edit_after_water_has_actual_tick",pipeline.result(5).applied_tick==1)
	check("real_callbacks_reordered_and_duplicated",pipeline.arrival_order.size()>=4 and pipeline.arrival_order[0]==2 and pipeline.arrival_order[1]==2 and pipeline.arrival_order[2]==1)
	remaining=6;RenderingServer.call_on_render_thread(_read_render)
	var begin:=Time.get_ticks_msec()
	while remaining>0 and Time.get_ticks_msec()-begin<10000:await process_frame
	check("physical_readbacks",remaining==0 and fields.size()==6)
	if fields.size()==6:
		var actual_net:=0.0
		for value in fields.sand.to_float32_array():actual_net+=(float(value)-float(domain.sand[0]))*0.015625
		check("real_sand_matches_per_command_results",absf(actual_net-net)<0.00001 and actual_net>0.0)
		check("sand_spares_and_publication_match",fields.sand==fields.sand_spare and fields.sand==fields.published)
		check("real_water_and_momentum_changed",fields.water!=domain.water.to_byte_array() and fields.qx!=PackedFloat32Array(domain.rock).to_byte_array())
		for field in ["sand","water","qx"]:
			var good:=true
			for value in fields[field].to_float32_array():good=good and is_finite(value) and (field=="qx" or value>=0.0)
			check("finite_"+field,good)
	var cancelled:=pipeline.submit_intent(request(6,&"fill_v1",Vector2.ZERO))
	check("cancel_accepted_pending",cancelled.accepted and pipeline.cancel_pending(6) and pipeline.result(6).cancelled)
	check("cancelled_id_not_reused",not pipeline.submit_intent(request(6,&"fill_v1",Vector2.ZERO)).accepted)
	var future:=request(7,&"fill_v1",Vector2.ZERO);future.sim_tick=4
	check("admit_future_tick",pipeline.submit_intent(future).accepted)
	var earlier:=request(8,&"dig_v1",Vector2(1,0));earlier.sim_tick=1
	check("admit_earlier_due_later_id",pipeline.submit_intent(earlier).accepted)
	await await_idle()
	check("due_order_and_implicit_water",pipeline.result(8).applied_tick==1 and pipeline.result(7).applied_tick==4 and pipeline.completed_tick==4)
	var legacy:={"domain_id":&"main_beach","generation":9007199254740993,"sim_tick":4,"command_id":9,"kind":&"place_sand","shape":&"circle","transform":{"position_m":Vector3(1,77,0)},"radius_m":0.75,"strength":1.0,"amount_m3":0.05,"seed":101}
	check("real_legacy_api_admission",pipeline.submit_legacy(legacy,0,0.0).accepted)
	await await_idle()
	check("real_legacy_api_shared_result",pipeline.result(9).outcome==L.Outcome.APPLIED and pipeline.result(9).applied_tick==4)
	var zero:=request(10,&"fill_v1",Vector2.ZERO);zero.authorization={"available_m3":0.0}
	check("admit_restrictive_zero",pipeline.submit_intent(zero).accepted)
	check("admit_after_rejection",pipeline.submit_intent(request(11,&"fill_v1",Vector2.ZERO)).accepted)
	await await_idle()
	check("business_reject_then_apply_chain",pipeline.result(10).outcome==L.Outcome.REJECTED and pipeline.result(11).outcome==L.Outcome.APPLIED and pipeline.result(10).output_revision==pipeline.result(11).input_revision)
	var first_id:=9007199254740995
	var admitted_all:=true
	for offset in 64:admitted_all=admitted_all and pipeline.submit_intent(request(first_id+offset,&"fill_v1",Vector2.ZERO,0.01)).accepted
	check("full_64_admitted",admitted_all)
	check("sixty_fifth_backpressure",pipeline.submit_intent(request(first_id+64,&"fill_v1",Vector2.ZERO,0.01)).error==&"queue_full")
	await await_idle()
	var all_results:=true
	for offset in 64:
		var item:=pipeline.result(first_id+offset)
		all_results=all_results and not item.is_empty() and item.command_id==first_id+offset and item.outcome==L.Outcome.APPLIED
	check("full_64_real_per_command_i64_results",all_results)
	pipeline.close_admission()
	check("closing_rejects",not pipeline.submit_intent(request(first_id+64,&"fill_v1",Vector2.ZERO)).accepted)
	RenderingServer.call_on_render_thread(pipeline.release_render)
	while not pipeline.released and Time.get_ticks_msec()-begin<10000:await process_frame
	check("release_after_last_consumer",pipeline.released)
	for path in source_hashes:check("source_unchanged_"+path,FileAccess.get_sha256(path)==source_hashes[path])
	finish()

func _arm_render() -> void:
	if probe_case=="upload":pipeline.transport.inject_upload_failure_once=true
	elif probe_case=="readback":pipeline.transport.inject_readback_failure_once=true;pipeline.transport.inject_terminal_unavailable=true
	elif probe_case in ["truncate","identity","unknown_state"]:pipeline.transport.inject_completion_fault_once=probe_case
	elif probe_case=="fatal":pipeline.transport.rd.buffer_update(pipeline.transport.control,4,4,PackedInt32Array([8]).to_byte_array())
	elif probe_case=="counter":pipeline.transport.rd.buffer_update(pipeline.transport.control,16,8,PackedInt64Array([9223372036854775807]).to_byte_array())
	elif probe_case=="tick_counter":pipeline.transport.rd.buffer_update(pipeline.transport.control,24,8,PackedInt64Array([9223372036854775807]).to_byte_array())
	elif probe_case=="revision_counter":pipeline.transport.rd.buffer_update(pipeline.transport.control,40,8,PackedInt64Array([9223372036854775807]).to_byte_array())
	elif probe_case=="bad_cfl":
		var invalid:=PackedByteArray();invalid.resize(65536*4);invalid.encode_float(0,NAN)
		var source: RID=pipeline.state._create_texture(RenderingDevice.DATA_FORMAT_R32_SFLOAT,invalid)
		pipeline.transport.rd.texture_copy(source,pipeline.state.textures.momentum_x[0],Vector3.ZERO,Vector3.ZERO,Vector3(256,256,1),0,0,0,0)
	call_deferred("_armed")

func _reorder_render() -> void:
	pipeline.transport.inject_duplicate_completion_once=true;pipeline.transport.inject_reorder_first_completion=true;call_deferred("_armed")

func _armed() -> void:armed=true

func _allow_terminal_render() -> void:
	pipeline.transport.inject_terminal_unavailable=false
	call_deferred("_armed")

func run_fault_case() -> void:
	check("known_fault_case",probe_case in ["upload","readback","truncate","identity","unknown_state","fatal","counter","tick_counter","revision_counter","bad_cfl"])
	RenderingServer.call_on_render_thread(_arm_render)
	while not armed:await process_frame
	if probe_case in ["tick_counter","bad_cfl"]:check("admit_fault_tick",pipeline.request_tick(1.0/30.0).is_empty())
	else:check("admit_fault_command",pipeline.submit_intent(request(1,&"fill_v1",Vector2.ZERO)).accepted)
	pipeline.pump()
	var begin:=Time.get_ticks_msec()
	while pipeline.fault_reason().is_empty() and Time.get_ticks_msec()-begin<10000:await process_frame
	check("fault_detected",not pipeline.fault_reason().is_empty())
	if probe_case=="upload":
		var aborted:=pipeline.result(1)
		check("known_unrecorded_has_no_gpu_outcome",aborted.get("cancelled",false) and aborted.get("submitted",true)==false and not aborted.has("outcome") and pipeline.completed_state_seq==0)
		var reserved:=pipeline.result_reservations()
		check("known_abort_result_consumable",pipeline.take_result(1)==aborted and pipeline.result_reservations()==reserved-1 and pipeline.result(1).is_empty() and pipeline.accounting.ledger.sand_source_m3==0.0)
	else:check("no_business_result",pipeline.result(1).is_empty() and pipeline.completed_state_seq==0)
	check("stop_after_fault",not pipeline.submit_intent(request(2,&"fill_v1",Vector2.ZERO)).accepted)
	if probe_case=="readback":
		pipeline.cleanup_fault()
		for index in 10:await process_frame
		check("unconfirmed_owner_retained",pipeline.active_count()==1 and pipeline.transport.has_owned())
		armed=false;RenderingServer.call_on_render_thread(_allow_terminal_render)
		while not armed:await process_frame
	pipeline.cleanup_fault()
	begin=Time.get_ticks_msec()
	while pipeline.active_count()>0 and Time.get_ticks_msec()-begin<10000:await process_frame
	check("terminal_proof_reclaims",pipeline.active_count()==0 and not pipeline.transport.has_owned())
	check("no_replay",pipeline.executor.recorded_commands==(0 if probe_case in ["upload","tick_counter","bad_cfl"] else 1))
	remaining=6;RenderingServer.call_on_render_thread(_read_render)
	while remaining>0 and Time.get_ticks_msec()-begin<10000:await process_frame
	if fields.has("sand"):
		check("recording_outcome_not_replayed",(fields.sand!=domain.sand.to_byte_array()) if probe_case in ["readback","truncate","identity","unknown_state"] else fields.sand==domain.sand.to_byte_array())
	RenderingServer.call_on_render_thread(pipeline.release_render)
	while not pipeline.released and Time.get_ticks_msec()-begin<10000:await process_frame
	check("fault_release_after_proof",pipeline.released)

func _read_decision_render() -> void:
	pipeline.transport.rd.buffer_get_data_async(pipeline.water.decision,_decision_render)

func _decision_render(bytes: PackedByteArray) -> void:call_deferred("_decision",bytes)
func _decision(bytes: PackedByteArray) -> void:water_decision=bytes

func _reference_render(dt: float, steps: int) -> void:
	reference_state=preload("res://scripts/simulation/unified_edit/state.gd").new()
	if not reference_state.initialize(pipeline.transport.rd,domain,pipeline.transport):call_deferred("_reference_failed");return
	for step in steps:
		var index:=step%2
		for pass_index in 3:
			var name: String=["edge_flux","drain_scale","update_state"][pass_index]
			var push:=PackedByteArray()
			if pass_index==1:push=PackedFloat32Array([dt/float(steps)/0.125,0,0,0]).to_byte_array()
			if pass_index==2:push=PackedFloat32Array([dt/float(steps)/0.125,0.125,0,0]).to_byte_array()
			reference_state.dispatch(name,reference_state.uniform_sets[index][pass_index],Vector3i(32,32,1),push)
	for pair in [["ref_water","water"],["ref_qx","momentum_x"],["ref_qz","momentum_z"]]:
		pipeline.transport.rd.texture_get_data_async(reference_state.textures[pair[1]][steps%2],0,_field_render.bind(pair[0]))
	call_deferred("_reference_started")

func _reference_started() -> void:reference_ready=true
func _reference_failed() -> void:check("reference_initialize",false);reference_ready=true

func _release_reference_render() -> void:
	reference_state.release();call_deferred("_reference_released")
func _reference_released() -> void:reference_ready=false

func run_water_reference(desired: int) -> void:
	check("water_tick_admitted",pipeline.request_tick(0.001).is_empty())
	await await_idle()
	RenderingServer.call_on_render_thread(_read_decision_render)
	var begin:=Time.get_ticks_msec()
	while water_decision.is_empty() and Time.get_ticks_msec()-begin<10000:await process_frame
	if water_decision.size()!=64:check("water_decision_readback",false);return
	var steps: int=water_decision.decode_u32(4);var dt: float=water_decision.decode_float(12)
	check("actual_gpu_cfl_count",steps==mini(64,desired))
	check("actual_gpu_cfl_overload",water_decision.decode_u32(16)==(1 if desired>64 else 0))
	check("clock_uses_actual_advance",pipeline.advanced_time_s==dt and dt>0.0 and (dt<0.001 if desired>64 else absf(dt-0.001)<1e-9))
	remaining=6;RenderingServer.call_on_render_thread(_read_render)
	while remaining>0 and Time.get_ticks_msec()-begin<10000:await process_frame
	remaining=3;RenderingServer.call_on_render_thread(_reference_render.bind(dt,steps))
	while (remaining>0 or not reference_ready) and Time.get_ticks_msec()-begin<10000:await process_frame
	for pair in [["water","ref_water"],["qx","ref_qx"]]:
		var valid: bool=fields.has(pair[0]) and fields.has(pair[1]);var max_error:=0.0
		if valid:
			var actual: PackedFloat32Array=fields[pair[0]].to_float32_array();var expected: PackedFloat32Array=fields[pair[1]].to_float32_array()
			for index in actual.size():
				var difference:=absf(actual[index]-expected[index]);max_error=maxf(max_error,difference)
				valid=valid and difference<=preload("res://scripts/simulation/edit_validation/edit_protocol.gd").cell_budget(expected[index],actual[index])
		check("original_direct_substeps_"+pair[0],valid);print("REFERENCE_MAX_ERROR ",pair[0]," ",max_error)
	RenderingServer.call_on_render_thread(_release_reference_render)
	while reference_ready:await process_frame
	pipeline.close_admission();RenderingServer.call_on_render_thread(pipeline.release_render)
	while not pipeline.released and Time.get_ticks_msec()-begin<10000:await process_frame
	check("reference_and_pipeline_released",pipeline.released)

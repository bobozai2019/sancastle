extends "res://tests/integration/unified_edit_target_probe.gd"

const Codec=preload("res://scripts/simulation/unified_edit/checkpoint_codec.gd")
const AREA:=0.015625
var records: Array=[]
var configuration: Dictionary={}
var metrics: Dictionary={}
var fixture_ready:=false
var restored
var pumping_restored:=false

func _process(_delta: float) -> bool:
	pipeline.pump()
	if pumping_restored:restored.pump()
	return false

func _run() -> void:
	started=Time.get_ticks_msec();DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var profiles: Array=Array(load("res://assets/unified_edit/default_catalog.tres").profiles)
	if probe_case=="legacy_blocked":
		for index in profiles.size():
			if profiles[index].profile_id==&"shovel_v1":
				profiles[index]=profiles[index].duplicate(true);profiles[index].version=1;profiles[index].transfer_policy=1
	registry=preload("res://scripts/simulation/unified_edit/profile_registry.gd").new()
	check("registry",registry.initialize(profiles).is_empty())
	var simulation:={"enable_erosion":false,"enable_brush_water":true,"unrestricted_sand_tools":true,"enable_structures":false,"local_front_history":false,"rise_front_history":false,"contact_history":false}
	var frozen:=Config.freeze(registry,"main_beach",simulation,{"foam_enabled":false,"gravel_enabled":false},{},{"engine":Engine.get_version_info().string,"probe":probe_case},PackedStringArray(Pipeline.SOURCE_PATHS+Pipeline.ADAPTER_SOURCES))
	check("configuration",frozen.error.is_empty())
	if not frozen.error.is_empty():finish();return
	configuration=frozen.value;source_hashes=configuration.sources.duplicate(true)
	check("configure",pipeline.configure(registry,configuration,9007199254740993).is_empty())
	domain=Domain.new(256,0.125);domain.domain_id=&"main_beach";domain.generation=9007199254740993
	domain.sand.fill(1.0);domain.rock.fill(0.0);domain.water.fill(0.15 if probe_case=="wet" else 0.0);domain.compaction.fill(0.3)
	# The physical seed contains a mound already at the stroke's shoulder cap.
	# A fixed baseline fixture below it reproduces prior deposition in that stroke.
	var capped:=probe_case in ["one_full","both_full","partial","wet","legacy_blocked"]
	if capped:
		for index in 65536:
			var pos:=Vector2((index%256+0.5-128.0)*0.125,(index/256+0.5-128.0)*0.125)
			var distance:=pos.distance_to(Vector2(clampf(pos.x,-1.0,1.0),0.0))
			if distance>=0.25 and distance<0.75 and (probe_case!="one_full" or pos.y>0.0):domain.sand[index]=1.49 if probe_case=="partial" else 1.5
	RenderingServer.call_on_render_thread(pipeline.initialize_render.bind(domain))
	while not pipeline.initialized and pipeline.fault_reason().is_empty() and Time.get_ticks_msec()-started<20000:await process_frame
	check("initialized",pipeline.initialized and pipeline.fault_reason().is_empty())
	if not pipeline.initialized or not pipeline.fault_reason().is_empty():finish();return
	await submit("begin",control_identity(),"begin")
	if capped:
		RenderingServer.call_on_render_thread(_baseline_fixture)
		while not fixture_ready:await process_frame
	var before:=await capture(pipeline,"before")
	var result:=await cut("cut",1)
	if result.is_empty():finish();return
	var after:=await capture(pipeline,"after")
	var removed:=0.0;var added:=0.0;var min_center:=INF;var max_shoulder:=0.0;var valid:=true
	var a: PackedFloat32Array=before.sand.to_float32_array();var b: PackedFloat32Array=after.sand.to_float32_array()
	for index in 65536:
		removed+=maxf(0.0,float(a[index])-float(b[index]))*AREA;added+=maxf(0.0,float(b[index])-float(a[index]))*AREA
		valid=valid and is_finite(b[index]) and b[index]>=0.0
		var x: float=(index%256+0.5-128.0)*0.125;var z: float=(index/256+0.5-128.0)*0.125
		if absf(x)<0.9 and absf(z)<0.125:min_center=minf(min_center,b[index])
		if b[index]>a[index]:max_shoulder=maxf(max_shoulder,b[index])
	check("finite_nonnegative",valid);check("sand_slots_equal",after.sand==after.sand1)
	check("receipt_matches_raw_cut",absf(result.removed_m3-removed)<=maxf(result.eps_transfer_m3,1e-7))
	check("receipt_matches_raw_deposit",absf(result.added_m3-added)<=maxf(result.eps_transfer_m3,1e-7))
	check("height_cap",max_shoulder<=1.500001)
	check("exact_sink_balance",absf(removed-added-result.sink_m3)<=maxf(result.eps_transfer_m3,1e-7))
	check("settled_exact_sink",pipeline.accounting.ledger.sand_sink_m3==result.sink_m3 and pipeline.accounting.ledger.sand_source_m3==0.0)
	if probe_case=="legacy_blocked":
		check("legacy_balanced_policy_retained",result.outcome==L.Outcome.NO_CHANGE and removed==0.0 and added==0.0)
	else:
		# The existing per-command volume authorization scales the discrete
		# parabola slightly; capacity must not reduce this normal ~13.6 cm cut.
		check("full_center_depth_even_at_capacity",1.0-min_center>0.13 and removed>0.1)
		check("applied",result.outcome==L.Outcome.APPLIED)
		if probe_case in ["both_full","wet"]:check("full_shoulders_do_not_receive",added==0.0 and result.transferred_m3==0.0 and result.sink_m3>0.1)
		if probe_case=="one_full":check("available_side_still_receives",minf(result.left_received_m3,result.right_received_m3)==0.0 and maxf(result.left_received_m3,result.right_received_m3)>0.05 and result.sink_m3>0.05)
		if probe_case=="partial":check("partial_capacity_uses_space_then_discards",added>0.0 and added<removed and result.sink_m3>0.0)
		var repeat_result:=await cut("repeat",2)
		check("repeated_geometry_no_extra_cut",repeat_result.get("outcome")==L.Outcome.NO_CHANGE)
		var before_zero:=await capture(pipeline,"before_zero")
		var zero:=await cut("zero",3,3.0,{"transfer_budget_m3":0.0})
		var after_zero:=await capture(pipeline,"after_zero")
		check("zero_budget_no_false_coverage",zero.get("outcome")==L.Outcome.NO_CHANGE and before_zero.coverage==after_zero.coverage and before_zero.sand==after_zero.sand)
		if probe_case=="history":
			var overlap:=await cut("overlap",4,0.375)
			var overlapped:=await capture(pipeline,"overlap")
			var cv: PackedFloat32Array=after.coverage.to_float32_array();var changed: PackedFloat32Array=overlapped.sand.to_float32_array();var refilled:=0
			for index in 65536:
				if cv[index*2+1]>0.0 and changed[index]>b[index]:refilled+=1
			check("earlier_donors_can_receive",overlap.get("outcome")==L.Outcome.APPLIED and refilled>0)
			var recut:=await cut("recut",5)
			check("refilled_old_trench_can_be_cut",recut.get("outcome")==L.Outcome.APPLIED and recut.removed_m3>0.01)
			metrics.refilled_cells=refilled
		if probe_case=="both_full":await checkpoint_roundtrip()
	metrics.merge({"removed_m3":removed,"added_m3":added,"sink_m3":result.sink_m3,"left_received_m3":result.left_received_m3,"right_received_m3":result.right_received_m3,"center_cut_m":1.0-min_center,"max_deposit_height_m":max_shoulder})
	check("healthy",pipeline.fault_reason().is_empty())
	await close_pipeline(pipeline)
	finish()

func cut(label: String, sample: int, z: float=0.0, authorization: Dictionary={}) -> Dictionary:
	var command:=shape_request(&"shovel_v1",Vector2(-1,z),Vector2(1,z),sample,{},1,11,2,authorization)
	if probe_case=="wet":command.features.water_policy=2;command.parameters.speed_m_s=0.25
	return await submit(label,command)

func submit(label: String, command: Dictionary, mode: String="") -> Dictionary:
	var admitted: Dictionary=pipeline.submit_intent(command) if mode.is_empty() else pipeline.submit_control(mode,command)
	check(label+"_admitted",admitted.accepted);await await_idle()
	var result:=pipeline.result(command.command_id)
	check(label+"_completed",not result.is_empty() and result.get("error_code",-1)==0)
	records.append({"label":label,"command":command,"result":result})
	return result

func _baseline_fixture() -> void:
	var base:=PackedFloat32Array();base.resize(65536);base.fill(1.0)
	var texture: RID=pipeline.state._create_texture(RenderingDevice.DATA_FORMAT_R32_SFLOAT,base.to_byte_array())
	pipeline.transport.rd.texture_copy(texture,pipeline.executor.images.baseline,Vector3.ZERO,Vector3.ZERO,Vector3(256,256,1),0,0,0,0)
	call_deferred("_fixture_done")
func _fixture_done() -> void:fixture_ready=true

func capture(subject, label: String) -> Dictionary:
	fields={};remaining=3;RenderingServer.call_on_render_thread(_capture_render.bind(subject))
	var begin:=Time.get_ticks_msec()
	while remaining>0 and Time.get_ticks_msec()-begin<10000:await process_frame
	check(label+"_readback",remaining==0 and fields.size()==3)
	for key in fields:FileAccess.open(output.get_base_dir().path_join(label+"_"+key+".bin"),FileAccess.WRITE).store_buffer(fields[key])
	return fields.duplicate(true)
func _capture_render(subject) -> void:
	for pair in [["sand",subject.state.textures.sand[0]],["sand1",subject.state.textures.sand[1]],["coverage",subject.executor.images.coverage]]:
		if subject.transport.rd.texture_get_data_async(pair[1],0,_field_render.bind(pair[0]))!=OK:call_deferred("_read_failed",pair[0])

func checkpoint_roundtrip() -> void:
	var completed: Dictionary={}
	var selection:={"policy":0,"speed":0.0,"brush":{"tool":&"shovel_v1","parameters":{"depth_m":0.15,"trench_width_m":0.5,"shoulder_width_m":0.5},"dig_amount_m3":0.05,"fill_amount_m3":0.05}}
	var path:=output.get_base_dir()+"/capped.sandue"
	var saved: Dictionary=pipeline.save_checkpoint(path,selection,func(value: Dictionary):completed.merge(value,true))
	check("save_admitted",saved.accepted)
	var begin:=Time.get_ticks_msec()
	while completed.is_empty() and Time.get_ticks_msec()-begin<20000:await process_frame
	check("save_completed",completed.get("error",&"missing").is_empty())
	if not completed.get("error",&"missing").is_empty():metrics.save_error=completed;return
	var loaded:=Codec.load(path,configuration)
	check("checkpoint_loaded",loaded.error.is_empty())
	if not loaded.error.is_empty():metrics.load_error=loaded.error;return
	check("sink_saved_exactly",loaded.checkpoint.ledger==pipeline.accounting.ledger and loaded.checkpoint.ledger.sand_sink_m3>0.0)
	restored=Pipeline.new()
	check("restore_configure",restored.configure_restore(registry,configuration,9007199254741093,loaded.checkpoint).is_empty())
	RenderingServer.call_on_render_thread(restored.initialize_render.bind(restored.restore_domain()))
	begin=Time.get_ticks_msec()
	while not restored.initialized and restored.fault_reason().is_empty() and Time.get_ticks_msec()-begin<20000:await process_frame
	check("restore_verified",restored.initialized and restored._ready and restored.restore_verifier.passed and restored.fault_reason().is_empty())
	if not restored._ready:return
	var source:=await capture(pipeline,"saved_source");var target:=await capture(restored,"restored")
	check("restored_sand_identical",source.sand==target.sand and source.sand1==target.sand1)
	check("restored_sink_identical",restored.accounting.ledger==pipeline.accounting.ledger)
	# Continue both states with the same new stroke after save's automatic END.
	pumping_restored=true
	for subject in [pipeline,restored]:
		var id: int=subject.command_highwater()+1
		var control:={"domain_id":"main_beach","generation":subject._generation,"command_id":id,"sim_tick":subject.completed_tick,"stroke_id":42,"baseline_token":43}
		check("resume_begin",subject.submit_control("begin",control).accepted)
		var command:=shape_request(&"shovel_v1",Vector2(-1,0),Vector2(1,0),1,{},1,11,2)
		command.command_id=id+1;command.generation=subject._generation;command.sim_tick=subject.completed_tick;command.stroke_id=42;command.baseline_token=43
		check("resume_cut",subject.submit_intent(command).accepted)
	await await_idle();begin=Time.get_ticks_msec()
	while (restored.active_count()>0 or restored.pending_count()>0) and restored.fault_reason().is_empty() and Time.get_ticks_msec()-begin<15000:await process_frame
	check("restored_continue_healthy",restored.fault_reason().is_empty() and restored.active_count()==0 and restored.pending_count()==0)
	source=await capture(pipeline,"continued_source");target=await capture(restored,"continued_restored")
	check("continued_sand_identical",source.sand==target.sand)
	check("continued_ledger_identical",restored.accounting.ledger==pipeline.accounting.ledger)
	metrics.checkpoint_ledger=loaded.checkpoint.ledger
	pumping_restored=false;await close_pipeline(restored)

func close_pipeline(subject) -> void:
	subject.close_admission();RenderingServer.call_on_render_thread(subject.release_render)
	var begin:=Time.get_ticks_msec()
	while not subject.released and Time.get_ticks_msec()-begin<10000:await process_frame
	check("released",subject.released)

func finish() -> void:
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"pass":not failed,"case":probe_case,"checks":checks,"records":records,"metrics":metrics,"fault":String(pipeline.fault_reason()),"source_hashes":source_hashes,"scope":"Production D3D12 shader, capped shoulders, raw volume/coverage, exact sink settlement and native checkpoint continuation. Capacity fixtures fix the stroke baseline below an initially seeded mound."},"\t"))
	quit(1 if failed else 0)

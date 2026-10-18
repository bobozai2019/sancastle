extends "res://tests/integration/unified_edit_restore_probe.gd"

const Observed=preload("res://tests/integration/unified_edit_observed_boundary.gd")
const MathTrace=preload("res://tests/integration/unified_edit_boundary_math_trace.gd")
var capture_result: Dictionary={}
var wave_requests: Array=[]
var restored_epoch:=0
var trace_done:=false
var trace_valid:=false
var math_trace:=MathTrace.new()

func wave(id: int, start: int=1) -> Dictionary:
	return {"domain_id":configuration.domain_id,"generation":pipeline._generation,"request_id":id,"start_tick":start,"profile_id":&"test_packet","amplitude_m":0.08,"duration_s":0.5,"seed":id*7}

func _run() -> void:
	started=Time.get_ticks_msec();DisplayServer.window_set_size(Vector2i(1280,720));DisplayServer.window_set_title("Unified prescribed boundary and waves")
	var key:="main_beach"
	if probe_case=="boundary_capture":key="test1_capture"
	elif probe_case=="boundary_backwash":key="test1_backwash"
	elif probe_case.begins_with("boundary_geometry"):key="test1_geometry"
	var created: Dictionary=load("res://assets/unified_edit/default_catalog.tres").instantiate_registry();registry=created.registry;check("registry",created.error.is_empty())
	var extras:=PackedStringArray(Pipeline.SOURCE_PATHS+Pipeline.ADAPTER_SOURCES+MathTrace.SOURCES+[get_script().resource_path,"res://tests/integration/unified_edit_restore_probe.gd","res://tests/integration/unified_edit_observed_boundary.gd"])
	var frozen:=Config.freeze(registry,key,{"enable_erosion":true,"enable_brush_water":true,"unrestricted_sand_tools":true,"enable_structures":false,"local_front_history":true,"rise_front_history":false,"contact_history":false},{"foam_enabled":true,"gravel_enabled":true},{},{"engine":Engine.get_version_info().string,"probe":probe_case,"boundary":Pipeline.Boundary.for_scene(key)},extras)
	check("configuration",frozen.error.is_empty());configuration=frozen.value;source_hashes=configuration.sources.duplicate(true)
	pipeline.water=Observed.new();check("configure",pipeline.configure(registry,configuration,9007199254740993).is_empty())
	domain=Domain.new(256,0.125);domain.domain_id=StringName(key);domain.generation=9007199254740993
	if key=="test1_geometry":check("actual_geometry_initial_state",Pipeline.Boundary.Geometry.initialize(domain))
	elif key in ["test1_capture","test1_backwash"]:check("actual_capture_initial_state",Pipeline.Boundary.Capture.initialize(domain,key))
	else:domain.rock.fill(0.05);domain.sand.fill(0.02);domain.water.fill(0.01);domain.wetness.fill(0.1);domain.compaction.fill(0.3)
	domain.water_source_m3=0.123456789012345;domain.water_sink_m3=0.023456789012345
	RenderingServer.call_on_render_thread(pipeline.initialize_render.bind(domain))
	var begin:=Time.get_ticks_msec()
	while not pipeline.initialized and Time.get_ticks_msec()-begin<25000:await process_frame
	check("initialized_full_combination",pipeline._ready and pipeline.fault_reason().is_empty() and pipeline.water.boundary_enabled and pipeline.visuals.enabled)
	if not pipeline._ready:observations.error=String(pipeline.fault_reason());await shutdown();finish();return
	if probe_case in ["boundary_geometry_rise","boundary_geometry_fall"]:await initialize_clock_fixture(3.0 if probe_case=="boundary_geometry_rise" else 7.0)
	observations.initial=await snapshot(pipeline,"initial")
	var wrong:=wave(999);wrong.domain_id="other"
	check("wrong_domain_wave_rejected",pipeline.request_wave(wrong).error==&"stale_generation_or_domain")
	if probe_case=="boundary_queued":check("older_tick_queued",pipeline.request_tick(1.0/30.0).is_empty())
	var count:=128 if probe_case=="boundary_capacity" else 2
	for id in range(1,count+1):
		var request:=wave(id,2 if probe_case=="boundary_queued" else 1);wave_requests.append(request.duplicate(true));check("wave_admit_"+str(id),pipeline.request_wave(request).accepted)
	check("wave_duplicate_rejected",not pipeline.request_wave(wave(count)).accepted)
	if probe_case=="boundary_capacity":check("wave_capacity_bounded",pipeline.request_wave(wave(129)).error==&"wave_capacity")
	if probe_case=="boundary_upload":pipeline.water.inject_boundary_upload_failure_once=true
	check("boundary_tick_admitted",pipeline.request_tick(1.0/30.0).is_empty())
	if probe_case=="boundary_upload":
		begin=Time.get_ticks_msec()
		while pipeline.fault_reason().is_empty() and Time.get_ticks_msec()-begin<10000:await process_frame
		check("upload_fault_known_unrecorded",pipeline.fault_reason()==&"boundary_wave_upload" and pipeline.completed_tick==0 and pipeline.completed_state_seq==0)
		pipeline.cleanup_fault();await process_frame;observations.after_upload_failure=await snapshot(pipeline,"after_upload_failure")
		await shutdown();finish();return
	await await_idle();await stages_idle(pipeline)
	observations.first=await snapshot(pipeline,"first");observations.stages=save_stages(pipeline.water,"first")
	check("full_combination_tick_advanced",pipeline.completed_tick==(2 if probe_case=="boundary_queued" else 1) and pipeline.advanced_time_s>0.0)
	var selection:={"policy":0,"speed":0.0,"brush":{"tool":&"place_sand","parameters":{},"dig_amount_m3":0.05,"fill_amount_m3":0.05}}
	var path:=output.get_base_dir()+"/boundary.sandue"
	check("boundary_capture_admitted",pipeline.save_checkpoint(path,selection,func(value: Dictionary):capture_result=value).accepted)
	begin=Time.get_ticks_msec()
	while capture_result.is_empty() and Time.get_ticks_msec()-begin<15000:await process_frame
	check("boundary_capture_valid",capture_result.get("error",&"missing")==&"")
	if capture_result.get("error",&"missing")!=&"":observations.capture_error=capture_result;await shutdown();finish();return
	var loaded:=Codec.load(path,configuration);check("boundary_container_loaded",loaded.error.is_empty())
	var checkpoint: Dictionary=loaded.checkpoint
	observations.container={"path":path,"sha256":FileAccess.get_sha256(path)};observations.capture_info=pipeline.last_checkpoint_info.duplicate(true)
	var after_save:=await snapshot(pipeline,"after_save");observations.after_save=after_save
	check("actual_wave_buffer_capture",pipeline.last_checkpoint_info.records.has("boundary_waves") and FileAccess.get_file_as_bytes(after_save.boundary_waves.path)==Pipeline.Boundary.encode_packets(pipeline.boundary.packets()))
	candidate=Pipeline.new();candidate.water=Observed.new();candidate.restore_verifier.capture_bytes=true
	restored_epoch=pipeline._generation+1
	check("restore_configured",candidate.configure_restore(registry,configuration,restored_epoch,checkpoint).is_empty())
	RenderingServer.call_on_render_thread(candidate.initialize_render.bind(candidate.restore_domain()))
	begin=Time.get_ticks_msec()
	while not candidate.initialized and Time.get_ticks_msec()-begin<25000:await process_frame
	check("boundary_candidate_verified",candidate._ready and candidate.restore_verifier.passed and candidate.restore_verifier.records.size()==47 and candidate.restore_verifier.records.has("display_active_count"))
	observations.verifier=candidate.restore_verifier.records.duplicate(true);observations.restored=await snapshot(candidate,"restored")
	check("wave_generation_rebased_only_metadata",candidate.boundary.requests.size()==count and candidate.boundary.requests[0].generation==restored_epoch and candidate.boundary.start_times==pipeline.boundary.start_times)
	var repeated:=wave(count,100);repeated.generation=restored_epoch
	check("restored_wave_highwater_rejects_replay",not candidate.request_wave(repeated).accepted)
	await verify_physics(checkpoint);candidate_pump=true
	for subject in [pipeline,candidate]:
		var request:=wave(count+1,subject.completed_tick+1);request.generation=subject._generation
		if count<128:check("new_wave_after_restore_"+str(subject._generation),subject.request_wave(request).accepted)
		check("continued_tick_"+str(subject._generation),subject.request_tick(1.0/30.0).is_empty())
	await await_idle();begin=Time.get_ticks_msec()
	while (candidate.active_count()>0 or candidate.pending_count()>0) and Time.get_ticks_msec()-begin<15000:await process_frame
	check("candidate_continuation_complete",candidate.active_count()==0 and candidate.pending_count()==0 and candidate.fault_reason().is_empty())
	await stages_idle(pipeline);await stages_idle(candidate)
	observations.source_second=await snapshot(pipeline,"source_second");observations.candidate_second=await snapshot(candidate,"candidate_second")
	observations.source_stages=save_stages(pipeline.water,"source_stages");observations.candidate_stages=save_stages(candidate.water,"candidate_stages")
	for field in observations.source_second:
		if field in ["control","stamp"]:continue
		check("continued_exact_"+field,observations.source_second[field].sha256==observations.candidate_second[field].sha256)
	var second_headers: Array=[]
	for subject in [pipeline,candidate]:
		var received: Dictionary={}
		check("second_checkpoint_accepted_"+str(subject._generation),subject.request_checkpoint(selection,func(value: Dictionary):received.merge(value,true)).accepted)
		begin=Time.get_ticks_msec()
		while received.is_empty() and Time.get_ticks_msec()-begin<15000:await process_frame
		check("second_checkpoint_valid_"+str(subject._generation),received.get("error",&"missing")==&"")
		if received.get("error",&"missing")==&"":second_headers.append({"ledger":received.checkpoint.ledger,"waves":received.checkpoint.wave_requests,"times":received.checkpoint.wave_start_times,"tick":received.checkpoint.sim_tick,"time_s":received.checkpoint.advanced_time_s})
	observations.second_headers=save_fields({"headers":var_to_bytes(second_headers)},"second_headers")
	check("continued_f64_ledger_exact",pipeline.ledger_snapshot()==candidate.ledger_snapshot())
	await capture_math_traces()
	await shutdown();observations.source_ownership=pipeline.ownership_counts();finish()

func initialize_clock_fixture(time_s: float) -> void:
	var data: Dictionary={};var selection:={"policy":0,"speed":0.0,"brush":{"tool":&"place_sand","parameters":{},"dig_amount_m3":0.05,"fill_amount_m3":0.05}}
	check("clock_fixture_capture_admitted",pipeline.request_checkpoint(selection,func(value: Dictionary):data.merge(value,true)).accepted)
	var begin:=Time.get_ticks_msec()
	while data.is_empty() and Time.get_ticks_msec()-begin<15000:await process_frame
	check("clock_fixture_capture_valid",data.get("error",&"missing")==&"")
	var fixture: Dictionary=data.checkpoint.duplicate(true);fixture.advanced_time_s=time_s;fixture.native.control.encode_float(32,time_s)
	fixture.source_provenance.trusted_fixture={"role":"synthetic_clock_only","actual_fields_origin":"initial real geometry GPU snapshot","time_s":time_s}
	var path:=output.get_base_dir()+"/clock_fixture.sandue";check("clock_fixture_saved",Codec.save(path,fixture,configuration).is_empty())
	var previous=pipeline;previous.close_admission();RenderingServer.call_on_render_thread(previous.release_render)
	begin=Time.get_ticks_msec()
	while not previous.released and Time.get_ticks_msec()-begin<10000:await process_frame
	check("clock_fixture_previous_released",previous.released)
	pipeline=Pipeline.new();pipeline.water=Observed.new();check("clock_fixture_restore_configured",pipeline.configure_restore(registry,configuration,previous._generation+1,fixture).is_empty())
	RenderingServer.call_on_render_thread(pipeline.initialize_render.bind(pipeline.restore_domain()));begin=Time.get_ticks_msec()
	while not pipeline.initialized and Time.get_ticks_msec()-begin<25000:await process_frame
	check("clock_fixture_native_verified",pipeline._ready and pipeline.restore_verifier.passed and pipeline.advanced_time_s==time_s)
	observations.clock_fixture={"path":path,"sha256":FileAccess.get_sha256(path),"time_s":time_s,"original_owners_after_release":previous.ownership_counts()}

func capture_math_traces() -> void:
	trace_done=false;RenderingServer.call_on_render_thread(_trace_initialize)
	while not trace_done:await process_frame
	check("private_math_trace_initialized",trace_valid)
	var mappings: Array=[];var count:=0
	for pair in [[pipeline.water,observations.stages,"first"],[pipeline.water,observations.source_stages,"source"],[candidate.water,observations.candidate_stages,"candidate"]]:
		var recorder=pair[0];var rows: Array=pair[1];var index:=0
		for id in recorder.stages:
			var stage: Dictionary=recorder.stages[id];count+=1;mappings.append({"id":count,"row":rows[index],"label":pair[2]});index+=1
			RenderingServer.call_on_render_thread(math_trace.capture.bind(Pipeline.Boundary.encode_packets(stage.packets),stage.fields["before/control"],stage.packets.size()))
			if index==rows.size():break
	var begin:=Time.get_ticks_msec()
	while math_trace.results.size()!=count and Time.get_ticks_msec()-begin<15000:await process_frame
	check("private_math_trace_readers_complete",math_trace.results.size()==count and math_trace.pending==0)
	for mapping in mappings:
		var bytes: PackedByteArray=math_trace.results.get(mapping.id,PackedByteArray());check("math_trace_bytes_"+str(mapping.id),bytes.size()==2064)
		mapping.row.math_trace=save_fields({"trace":bytes},"math_"+mapping.label+"_"+str(mapping.id)).trace
	trace_done=false;RenderingServer.call_on_render_thread(_trace_release)
	while not trace_done:await process_frame
	check("private_math_trace_all_rids_released",math_trace.owned.is_empty())

func _trace_initialize() -> void:call_deferred("_trace_result",math_trace.initialize(pipeline.transport.rd))
func _trace_result(valid: bool) -> void:trace_valid=valid;trace_done=true
func _trace_release() -> void:math_trace.release();call_deferred("_trace_result",true)

func stages_idle(subject) -> void:
	var begin:=Time.get_ticks_msec()
	while subject.water.pending>0 and Time.get_ticks_msec()-begin<10000:await process_frame
	check("ordered_stage_readers_complete_"+str(checks.size()),subject.water.pending==0 and subject.water.registration_errors==0)

func save_stages(recorder, label: String) -> Array:
	var result: Array=[]
	for id in recorder.stages:
		var stage: Dictionary=recorder.stages[id];var index: Dictionary=save_fields(stage.fields,label+"_"+str(id))
		index.push=save_fields({"push":stage.push},label+"_"+str(id)).push
		index.packet_bytes=save_fields({"packets":Pipeline.Boundary.encode_packets(stage.packets)},label+"_"+str(id)).packets
		index.packet_count=stage.packets.size();result.append(index)
	return result

func snapshot(subject, label: String) -> Dictionary:
	snapshot_fields={};snapshot_pending=27+subject.visuals.capture_images().size()+subject.visuals.published.size();RenderingServer.call_on_render_thread(_snapshot_render.bind(subject))
	var begin:=Time.get_ticks_msec()
	while snapshot_pending>0 and Time.get_ticks_msec()-begin<10000:await process_frame
	check("snapshot_"+label,snapshot_pending==0);return save_fields(snapshot_fields,label)

func _snapshot_render(subject) -> void:
	super._snapshot_render(subject)
	var images: Dictionary=subject.visuals.capture_images()
	for key in subject.visuals.published:images["visual_view/"+key]=subject.visuals.published[key]
	for key in images:
		if subject.transport.rd.texture_get_data_async(images[key],0,_snapshot_arrived.bind(key))!=OK:call_deferred("_snapshot_failed",key)
	for pair in [["boundary_waves",subject.water.waves,2048],["decision",subject.water.decision,64]]:
		if subject.transport.rd.buffer_get_data_async(pair[1],_snapshot_arrived.bind(pair[0]),0,pair[2])!=OK:call_deferred("_snapshot_failed",pair[0])

func finish() -> void:
	observations.source_ownership=pipeline.ownership_counts()
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"pass":not failed,"case":probe_case,"checks":checks,"observations":observations,"source_hashes":source_hashes,"engine":Engine.get_version_info(),"scope":"Real ordered boundary pre/post snapshots; erosion+foam/front/gravel; wave admission/frozen pending order; native capture/restore/rebase/continuation and 64 physics maps. No formal scene or cost claim."},"\t"));quit(1 if failed else 0)

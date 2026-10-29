extends "res://tests/integration/unified_edit_visuals_probe.gd"

const Display=preload("res://scripts/simulation/unified_edit/display_intent.gd")
const FIRST:=9007199254740995
var old_gravel:=PackedByteArray()
var capture_frames:=false

func emit_request(id: int, point: Vector2, count: int, epoch: int=9007199254740993) -> Dictionary:
	return {"domain_id":"main_beach","generation":epoch,"command_id":id,"sim_tick":pipeline.completed_tick,"point_xz_m":point,"count":count}

func _run() -> void:
	started=Time.get_ticks_msec();DisplayServer.window_set_size(Vector2i(1280,720))
	var catalog: Dictionary=load("res://assets/unified_edit/default_catalog.tres").instantiate_registry();registry=catalog.registry;check("registry",catalog.error.is_empty())
	var profile:=Pipeline.Visuals.Gravel.default_profile("main",0)
	var sources:=PackedStringArray(Pipeline.SOURCE_PATHS+Pipeline.ADAPTER_SOURCES+Reference.SOURCES+[get_script().resource_path,"res://tests/integration/unified_edit_visuals_probe.gd","res://tests/integration/unified_edit_restore_probe.gd","res://tests/integration/unified_edit_gpu_probe.gd"])
	var frozen:=Config.freeze(registry,"main_beach",{"enable_erosion":false,"enable_brush_water":true,"unrestricted_sand_tools":true,"enable_structures":false,"local_front_history":false,"rise_front_history":false,"contact_history":false},{"foam_enabled":false,"gravel_enabled":probe_case!="display_disabled"},{},{"engine":Engine.get_version_info().string,"gravel_profile":profile},sources)
	check("configuration",frozen.error.is_empty());configuration=frozen.value;source_hashes=configuration.sources.duplicate(true)
	check("configure",pipeline.configure(registry,configuration,9007199254740993).is_empty())
	domain=Domain.new(256,0.125);domain.domain_id=&"main_beach";domain.generation=9007199254740993
	domain.rock.fill(0.05);domain.sand.fill(0.25);domain.water.fill(0.1);domain.wetness.fill(0.1);domain.compaction.fill(0.3)
	var qx:=PackedFloat32Array();qx.resize(65536);qx.fill(0.045);domain.set_meta("edit_validation_initial_qx",qx)
	RenderingServer.call_on_render_thread(pipeline.initialize_render.bind(domain))
	var start:=Time.get_ticks_msec()
	while not pipeline.initialized and Time.get_ticks_msec()-start<25000:await process_frame
	check("initialized",pipeline._ready and pipeline.fault_reason().is_empty())
	if not pipeline._ready:await shutdown_visuals();finish();return
	if probe_case!="display_core":await _case();return
	observations.initial=await snapshot(pipeline,"initial")
	reference_done=false;RenderingServer.call_on_render_thread(_reference_initialize)
	while not reference_done and Time.get_ticks_msec()-start<30000:await process_frame
	check("original_gravel_reference",reference_ok)
	var first:=emit_request(FIRST,Vector2(-2,0),17);var second:=emit_request(FIRST+1,Vector2(4,1),29)
	pipeline.hold_completions=true
	check("first_emit_admitted",pipeline.submit_display_intent(first).accepted)
	check("second_emit_admitted",pipeline.submit_display_intent(second).accepted)
	start=Time.get_ticks_msec()
	while pipeline.pending_count()!=0 and Time.get_ticks_msec()-start<10000:await process_frame
	check("two_shared_slots_before_cpu_results",pipeline.active_count()==2 and pipeline.completed_state_seq==0 and pipeline.visuals.active_count==0)
	capture_frames=true;observations.emitted_held=await snapshot(pipeline,"emitted_held");capture_frames=false
	var identity: Dictionary=pipeline.slots.slot_snapshot(0).identity
	var raw:=FileAccess.get_file_as_bytes(observations.emitted_held.frame_0.path)
	var typed: Dictionary=Display.freeze(first,configuration,domain.generation).value
	check("actual_raw_display_receipt_decodes",Pipeline.W.decode_completion(raw,identity,[typed],Display.WORK_KIND).error.is_empty())
	for mutation in ["magic","authority","revision","amount","count","capacity","reserved"]:
		var bad:=raw.duplicate()
		match mutation:
			"magic":bad.encode_u32(96,L.RESULT_MAGIC)
			"authority":bad.encode_u32(196,1)
			"revision":bad.encode_s64(152,1)
			"amount":bad.encode_float(224,0.1)
			"count":bad.encode_u32(216,18)
			"capacity":bad.encode_u32(220,1025)
			"reserved":bad[479]=1
		check("receipt_reject_"+mutation,not Pipeline.W.decode_completion(bad,identity,[typed],Display.WORK_KIND).error.is_empty())
	old_gravel=PackedByteArray();RenderingServer.call_on_render_thread(_old_emit.bind([first,second],false))
	start=Time.get_ticks_msec()
	while old_gravel.is_empty() and Time.get_ticks_msec()-start<10000:await process_frame
	observations.reference_emitted=save_fields({"gravel":old_gravel},"reference_emitted")
	check("original_mode3_exact_bytes",observations.emitted_held["visual/gravel_0"].sha256==observations.reference_emitted.gravel.sha256)
	for key in observations.initial:
		if key in ["control","stamp","display_active_count"] or key.begins_with("visual"):continue
		check("display_keeps_authority_"+key,observations.initial[key].sha256==observations.emitted_held[key].sha256)
	pipeline.hold_completions=false;await await_idle()
	var first_result:=pipeline.take_result(FIRST);var second_result:=pipeline.take_result(FIRST+1)
	observations.results=[first_result,second_result]
	check("actual_display_receipts",first_result.get("display_count")==17 and second_result.get("display_count")==29 and second_result.get("active_count")==46 and pipeline.visuals.active_count==46)
	check("display_revision_tick_clock_unchanged",pipeline.completed_state_seq==2 and pipeline.completed_revision==0 and pipeline.completed_tick==0 and pipeline.advanced_time_s==0.0)
	check("display_ledger_unchanged",pipeline.accounting.ledger.sand_source_m3==0.0 and pipeline.accounting.ledger.sand_sink_m3==0.0)
	check("tick_after_emission",pipeline.request_tick(0.001).is_empty());await await_idle()
	observations.after_tick=await snapshot(pipeline,"after_tick")
	old_gravel=PackedByteArray();RenderingServer.call_on_render_thread(_old_emit.bind([],true))
	start=Time.get_ticks_msec()
	while old_gravel.is_empty() and Time.get_ticks_msec()-start<10000:await process_frame
	observations.reference_tick=save_fields({"gravel":old_gravel},"reference_tick")
	check("new_population_advances_original_exactly",observations.after_tick["visual/gravel_0"].sha256==observations.reference_tick.gravel.sha256)
	capture_result={}
	var selection:={"policy":0,"speed":0.0,"brush":{"tool":&"gravel_drop","parameters":{"count":16},"dig_amount_m3":0.1,"fill_amount_m3":0.1}}
	var path:=output.get_base_dir()+"/display.sandue"
	check("native_capture_admitted",pipeline.save_checkpoint(path,selection,func(value: Dictionary):capture_result=value).accepted)
	start=Time.get_ticks_msec()
	while capture_result.is_empty() and Time.get_ticks_msec()-start<25000:await process_frame
	check("native_capture_complete",capture_result.get("error",&"missing")==&"")
	observations.capture=capture_result.duplicate(true)
	observations.capture.erase("checkpoint")
	var loaded:=Codec.load(path,configuration);check("native_loaded",loaded.error.is_empty())
	if not loaded.error.is_empty():await shutdown_visuals();finish();return
	var checkpoint: Dictionary=loaded.checkpoint
	check("native_active_count_proven",checkpoint.visual_extensions.gravel_v1.active_count==46)
	candidate=Pipeline.new();candidate.restore_verifier.capture_bytes=true
	check("restore_configure",candidate.configure_restore(registry,configuration,9007199254740994,checkpoint).is_empty())
	RenderingServer.call_on_render_thread(candidate.initialize_render.bind(candidate.restore_domain()))
	start=Time.get_ticks_msec()
	while not candidate.initialized and Time.get_ticks_msec()-start<25000:await process_frame
	check("restore_gpu_count_verified",candidate._ready and candidate.restore_verifier.passed and candidate.restore_verifier.records.get("display_active_count",{}).get("matched",false))
	observations.restore_verification=candidate.restore_verifier.records.duplicate(true)
	observations.restored=await snapshot(candidate,"restored")
	check("restored_gravel_exact",observations.restored["visual/gravel_0"].sha256==observations.after_tick["visual/gravel_0"].sha256)
	candidate_pump=true
	check("source_continued_emit",pipeline.submit_display_intent(emit_request(FIRST+2,Vector2(1,-2),3)).accepted)
	check("restored_continued_emit",candidate.submit_display_intent(emit_request(FIRST+2,Vector2(1,-2),3,9007199254740994)).accepted)
	check("source_continued_tick",pipeline.request_tick(0.001).is_empty());check("restored_continued_tick",candidate.request_tick(0.001).is_empty())
	await await_idle();start=Time.get_ticks_msec()
	while (candidate.active_count()!=0 or candidate.pending_count()!=0) and Time.get_ticks_msec()-start<15000:await process_frame
	check("both_continue_population",pipeline.visuals.active_count==49 and candidate.visuals.active_count==49 and candidate.fault_reason().is_empty())
	observations.source_continued=await snapshot(pipeline,"source_continued");observations.candidate_continued=await snapshot(candidate,"candidate_continued")
	for key in observations.source_continued:
		if key in ["control","stamp"]:continue
		check("continued_exact_"+key,observations.source_continued[key].sha256==observations.candidate_continued[key].sha256)
	await shutdown_visuals();finish()

func snapshot(subject, label: String) -> Dictionary:
	snapshot_fields={};snapshot_pending=26+subject.visuals.capture_images().size()+subject.visuals.published.size()+(2 if capture_frames else 0);RenderingServer.call_on_render_thread(_snapshot_render.bind(subject))
	var start:=Time.get_ticks_msec()
	while snapshot_pending>0 and Time.get_ticks_msec()-start<10000:await process_frame
	check("snapshot_"+label,snapshot_pending==0);return save_fields(snapshot_fields,label)

func _snapshot_render(subject) -> void:
	super._snapshot_render(subject)
	if subject.transport.rd.buffer_get_data_async(subject.visuals.gravel_meta,_snapshot_arrived.bind("display_active_count"),0,4)!=OK:call_deferred("_snapshot_failed","display_active_count")
	if capture_frames:
		for index in 2:
			var key:="frame_"+str(index)
			if subject.transport.rd.buffer_get_data_async(subject.transport.resources[index].output,_snapshot_arrived.bind(key),0,480)!=OK:call_deferred("_snapshot_failed",key)

func _old_emit(requests: Array, step: bool) -> void:
	for request in requests:
		var error: StringName=reference.gravel.add_at(reference.solver,request.point_xz_m,request.count,domain.generation,reference.gravel.completed_tick,reference.gravel.revision)
		if not error.is_empty():call_deferred("check","original_emit",false)
	if step:
		var ok: bool=reference.gravel.advance(reference.solver,reference.gravel.completed_tick+1,reference.gravel.revision,domain.generation,0.001)
		if not ok:call_deferred("check","original_step",false)
	reference.rd.texture_get_data_async(reference.gravel.current_texture(),0,_old_arrived)
func _old_arrived(bytes: PackedByteArray) -> void:call_deferred("_old_received",bytes)
func _old_received(bytes: PackedByteArray) -> void:old_gravel=bytes

func _case() -> void:
	if probe_case=="display_disabled":
		check("disabled_display_explicitly_rejected",pipeline.submit_display_intent(emit_request(FIRST,Vector2.ZERO,16)).error==&"display_disabled")
		check("disabled_has_no_display_allocation",not pipeline.visuals.gravel_meta.is_valid())
		await shutdown_visuals();finish();return
	observations.before=await snapshot(pipeline,"before")
	if probe_case=="display_mixed":await _mixed();return
	for bad in [0,129,-1,1.5,true]:
		var request:=emit_request(FIRST,Vector2.ZERO,1);request.count=bad
		check("invalid_count_"+str(bad),not pipeline.submit_display_intent(request).accepted)
	check("point_out_of_domain",not pipeline.submit_display_intent(emit_request(FIRST,Vector2(15.6,0),1)).accepted)
	check("wrong_generation",not pipeline.submit_display_intent(emit_request(FIRST,Vector2.ZERO,1,7)).accepted)
	if probe_case in ["display_capacity","display_cancel"]:
		var requests: Array=[]
		for index in 8:
			var request:=emit_request(FIRST+index,Vector2(float(index)-4,0),128);requests.append(request)
			check("capacity_admit_"+str(index),pipeline.submit_display_intent(request).accepted)
		check("reserved_capacity_before_gpu",pipeline.submit_display_intent(emit_request(FIRST+8,Vector2.ZERO,1)).error==&"gravel_capacity_full")
		if probe_case=="display_cancel":
			check("cancel_unrecorded_display",pipeline.cancel_pending(FIRST+1))
			observations.cancelled=pipeline.take_result(FIRST+1)
			check("cancel_has_no_fake_gpu_result",observations.cancelled.get("cancelled",false) and not observations.cancelled.has("outcome"))
			requests.remove_at(1);var replacement:=emit_request(FIRST+8,Vector2(5,1),128);requests.append(replacement)
			check("cancel_releases_capacity",pipeline.submit_display_intent(replacement).accepted)
		await await_idle()
		check("gpu_population_capacity",pipeline.visuals.active_count==1024 and pipeline.completed_revision==0 and pipeline.completed_tick==0)
		check("completed_capacity_rejection",pipeline.submit_display_intent(emit_request(FIRST+9,Vector2.ZERO,1)).error==&"gravel_capacity_full")
		observations.results=[]
		for request in requests:observations.results.append(pipeline.take_result(request.command_id))
		observations.after=await snapshot(pipeline,"after")
		reference_done=false;RenderingServer.call_on_render_thread(_reference_initialize)
		var start:=Time.get_ticks_msec()
		while not reference_done and Time.get_ticks_msec()-start<10000:await process_frame
		old_gravel=PackedByteArray();RenderingServer.call_on_render_thread(_old_emit.bind(requests,false))
		while old_gravel.is_empty() and Time.get_ticks_msec()-start<15000:await process_frame
		observations.reference=save_fields({"gravel":old_gravel},"reference")
		check("dense_fifo_assignment_original_bytes",observations.after["visual/gravel_0"].sha256==observations.reference.gravel.sha256)
		await shutdown_visuals();finish();return
	if probe_case=="display_capture_mismatch":
		check("count_proof_emit",pipeline.submit_display_intent(emit_request(FIRST,Vector2.ZERO,17)).accepted);await await_idle();pipeline.take_result(FIRST)
		pipeline.visuals.active_count=16 # Deliberate non-authoritative metadata fault.
		capture_result={};var path:=output.get_base_dir()+"/must_not_exist.sandue"
		var selection:={"policy":0,"speed":0.0,"brush":{"tool":&"gravel_drop","parameters":{"count":16},"dig_amount_m3":0.1,"fill_amount_m3":0.1}}
		check("count_proof_capture_admitted",pipeline.save_checkpoint(path,selection,func(value: Dictionary):capture_result=value).accepted)
		var start:=Time.get_ticks_msec()
		while capture_result.is_empty() and Time.get_ticks_msec()-start<20000:await process_frame
		check("actual_gpu_count_prevents_false_save",capture_result.get("error")==&"checkpoint_display_count_mismatch" and not FileAccess.file_exists(path))
		pipeline.visuals.active_count=17;observations.capture_error=capture_result.duplicate(true)
		await shutdown_visuals();finish();return
	if probe_case=="display_fatal":
		check("pre_fatal_emit",pipeline.submit_display_intent(emit_request(FIRST,Vector2.ZERO,17)).accepted);await await_idle();pipeline.take_result(FIRST)
		observations.before=await snapshot(pipeline,"before_fatal")
		RenderingServer.call_on_render_thread(_poison_display_control);await process_frame;await process_frame
	elif probe_case=="display_upload":pipeline.transport.inject_upload_failure_once=true
	elif probe_case=="display_unknown":pipeline.transport.inject_readback_failure_once=true;pipeline.transport.inject_terminal_unavailable=true
	else:check("known_display_case",false);await shutdown_visuals();finish();return
	var id:=FIRST+1 if probe_case=="display_fatal" else FIRST
	check("failure_request_admitted",pipeline.submit_display_intent(emit_request(id,Vector2(2,1),17)).accepted)
	var start:=Time.get_ticks_msec()
	while pipeline.fault_reason().is_empty() and Time.get_ticks_msec()-start<10000:await process_frame
	check("common_failure_observed",not pipeline.fault_reason().is_empty())
	observations.after=await snapshot(pipeline,"after_failure")
	observations.visible_result=pipeline.result(id)
	if probe_case=="display_upload":check("known_unrecorded",observations.visible_result.get("cancelled",false) and not observations.visible_result.get("submitted",true))
	else:check("no_fabricated_gpu_result",observations.visible_result.is_empty())
	pipeline.cleanup_fault();await process_frame;await process_frame
	if probe_case=="display_unknown":
		check("unknown_retains_actual_work_lease",pipeline.active_count()==1 and not pipeline.released and pipeline.visuals.active_count==0)
		RenderingServer.call_on_render_thread(_allow_display_terminal);await process_frame;await process_frame;pipeline.cleanup_fault()
	start=Time.get_ticks_msec()
	while pipeline.active_count()!=0 and Time.get_ticks_msec()-start<10000:await process_frame
	check("real_terminal_retires_lease",pipeline.active_count()==0)
	await shutdown_visuals()
	observations.closed_results=pipeline.drain_closed_results()
	if probe_case!="display_upload":
		var row: Dictionary=observations.closed_results.get(id,{})
		check("closed_recording_remains_unknown",row.get("unknown",false) and row.get("submitted",false) and not row.has("outcome"))
	finish()

func _allow_display_terminal() -> void:pipeline.transport.inject_terminal_unavailable=false
func _poison_display_control() -> void:
	var bytes:=PackedByteArray();bytes.resize(4);bytes.encode_u32(0,2);pipeline.transport.rd.buffer_update(pipeline.transport.control,4,4,bytes)

func _mixed() -> void:
	pipeline.hold_completions=true
	var emission:=emit_request(FIRST,Vector2(-2,0),17)
	check("mixed_emit",pipeline.submit_display_intent(emission).accepted)
	check("mixed_edit",pipeline.submit_intent(request(FIRST+1,&"fill_v1",Vector2(-2,0),0.05)).accepted)
	check("mixed_tick",pipeline.request_tick(0.001).is_empty())
	var start:=Time.get_ticks_msec()
	while pipeline.pending_count()!=0 and Time.get_ticks_msec()-start<10000:await process_frame
	check("mixed_three_slots_without_cpu_receipts",pipeline.active_count()==3 and pipeline.completed_state_seq==0 and pipeline.visuals.active_count==0)
	observations.ahead=await snapshot(pipeline,"ahead")
	reference_done=false;RenderingServer.call_on_render_thread(_reference_initialize)
	while not reference_done and Time.get_ticks_msec()-start<15000:await process_frame
	old_gravel=PackedByteArray();RenderingServer.call_on_render_thread(_old_emit.bind([emission],true))
	while old_gravel.is_empty() and Time.get_ticks_msec()-start<20000:await process_frame
	observations.reference=save_fields({"gravel":old_gravel},"reference")
	check("mixed_emit_edit_tick_original_bytes",observations.ahead["visual/gravel_0"].sha256==observations.reference.gravel.sha256)
	pipeline.hold_completions=false;await await_idle()
	check("mixed_actual_population",pipeline.visuals.active_count==17 and pipeline.completed_tick==1 and pipeline.completed_revision==2)
	observations.results=[pipeline.take_result(FIRST),pipeline.take_result(FIRST+1)]
	candidate=Pipeline.new();var copy=Domain.new(256,0.125);copy.domain_id=domain.domain_id;copy.generation=domain.generation+1
	for field in ["rock","sand","water","wetness","compaction"]:copy.set(field,domain.get(field).duplicate())
	copy.set_meta("edit_validation_initial_qx",domain.get_meta("edit_validation_initial_qx").duplicate())
	check("physical_reference_configure",candidate.configure(registry,configuration,copy.generation).is_empty())
	RenderingServer.call_on_render_thread(candidate.initialize_render.bind(copy));start=Time.get_ticks_msec()
	while not candidate.initialized and Time.get_ticks_msec()-start<25000:await process_frame
	check("physical_reference_ready",candidate._ready);candidate_pump=true
	var edit:=request(FIRST+1,&"fill_v1",Vector2(-2,0),0.05);edit.generation=copy.generation;edit.sim_tick=0
	check("physical_only_edit",candidate.submit_intent(edit).accepted);check("physical_only_tick",candidate.request_tick(0.001).is_empty())
	start=Time.get_ticks_msec()
	while (candidate.pending_count()!=0 or candidate.active_count()!=0) and Time.get_ticks_msec()-start<15000:await process_frame
	observations.physical_only=await snapshot(candidate,"physical_only")
	for key in observations.ahead:
		if key in ["control","stamp","display_active_count"] or key.begins_with("visual"):continue
		check("mixed_physics_exact_"+key,observations.ahead[key].sha256==observations.physical_only[key].sha256)
	check("mixed_ledger_only_physical_edit",pipeline.accounting.ledger==candidate.accounting.ledger and pipeline.accounting.ledger.sand_source_m3==0.05)
	await shutdown_visuals();finish()

func finish() -> void:
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"pass":not failed,"case":probe_case,"checks":checks,"observations":observations,"source_hashes":source_hashes,"scope":"Tagged display input in common slots, original gravel mode3/step bytes, native count proof and continuation; no formal cutover"},"\t"));quit(1 if failed else 0)

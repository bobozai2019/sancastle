extends "res://tests/integration/unified_edit_restore_probe.gd"

class Receiver extends Node:
	var calls:=0
	func receive(_result: Dictionary) -> void:calls+=1

var checkpoint_result: Dictionary={}
var checkpoint_callbacks:=0
var pause_pump:=false
var source_surface
var commands: Array=[]
var receiver
var bad_completion:=PackedByteArray()

func _process(_delta: float) -> bool:
	if not pause_pump:pipeline.pump()
	if candidate_pump:candidate.pump()
	return false

func intent(id: int, profile_id: StringName, parameters: Dictionary={}, point:=Vector2.ZERO) -> Dictionary:
	var profile: Dictionary=registry.profile(profile_id)
	var value:={"domain_id":"main_beach","generation":9007199254740993,"command_id":id,"sim_tick":pipeline.completed_tick,"profile_id":profile_id,"profile_version":profile.version,"profile_hash":profile.profile_hash,"start_xz_m":point,"parameters":parameters,"features":{"water_policy":0}}
	if profile.shape==L.Profile.Shape.SWEPT_CAPSULE:value.end_xz_m=point+Vector2(1,0)
	if profile.stroke_policy!=0:value.stroke_id=8001;value.baseline_token=9001;value.sample_index=1
	return value

func admit(value: Dictionary) -> void:commands.append(value.duplicate(true));check("admit_"+str(value.command_id),pipeline.submit_intent(value).accepted)

func begin(id: int) -> void:
	check("begin_"+str(id),pipeline.submit_control("begin",{"domain_id":"main_beach","generation":9007199254740993,"command_id":id,"sim_tick":pipeline.completed_tick,"stroke_id":8001,"baseline_token":9001}).accepted)

func workload() -> void:
	if probe_case=="checkpoint_capacity":
		begin(1);admit(intent(2,&"wall_v1",{},Vector2(-0.5,2)));await await_idle()
		for id in range(3,513):
			check("reserve_cancel_"+str(id),pipeline.submit_intent(intent(id,&"fill_v1",{"amount_m3":0.07})).accepted and pipeline.cancel_pending(id))
		return
	admit(intent(1,&"fill_v1",{"amount_m3":0.01,"strength":0.7} if probe_case=="checkpoint_quantized" else {"amount_m3":0.05},Vector2(3,1)))
	var rejected:=intent(2,&"fill_v1",{"amount_m3":0.05},Vector2(3,1));rejected.authorization={"available_m3":0.0};admit(rejected)
	admit(intent(3,&"dig_v1",{"amount_m3":0.04},Vector2(-3,-1)))
	check("cancel_before_recording",pipeline.submit_intent(intent(4,&"fill_v1",{"amount_m3":0.07})).accepted and pipeline.cancel_pending(4))
	check("queue_tick",pipeline.request_tick(0.001).is_empty())
	admit(intent(5,&"smooth_v1",{"strength":0.2},Vector2(4,3)))
	admit(intent(6,&"compact_v1",{"strength":0.2},Vector2(4,3)))
	begin(7);admit(intent(8,&"wall_v1",{},Vector2(-0.5,2)))

func _run() -> void:
	started=Time.get_ticks_msec();DisplayServer.window_set_size(Vector2i(1280,720));DisplayServer.window_set_title("Unified production checkpoint lifecycle")
	var created: Dictionary=load("res://assets/unified_edit/default_catalog.tres").instantiate_registry();registry=created.registry;check("registry",created.error.is_empty())
	var simulation:={"enable_erosion":true,"enable_brush_water":true,"unrestricted_sand_tools":true,"enable_structures":false,"local_front_history":false,"rise_front_history":false,"contact_history":false}
	var extra:=PackedStringArray(Pipeline.SOURCE_PATHS+Pipeline.ADAPTER_SOURCES);extra.append(get_script().resource_path);extra.append("res://tests/integration/unified_edit_restore_probe.gd")
	var frozen:=Config.freeze(registry,"main_beach",simulation,{"foam_enabled":false,"gravel_enabled":false},{},{"engine":Engine.get_version_info().string,"probe":probe_case},extra)
	check("configuration",frozen.error.is_empty());configuration=frozen.value;source_hashes=configuration.sources.duplicate(true)
	check("configure",pipeline.configure(registry,configuration,9007199254740993).is_empty())
	domain=Domain.new(256,0.125);domain.domain_id=&"main_beach";domain.generation=9007199254740993
	domain.rock.fill(0.05);domain.sand.fill(0.25);domain.water.fill(0.1);domain.sediment.fill(0.01);domain.wetness.fill(0.1);domain.compaction.fill(0.3)
	# Explicit f64 historical water-ledger seed; GPU cumulative anchors start at 0.
	domain.water_source_m3=0.123456789012345;domain.water_sink_m3=0.023456789012345
	observations.initial=save_fields({"sand":domain.sand.to_byte_array(),"sediment":domain.sediment.to_byte_array(),"rock":domain.rock.to_byte_array()},"initial_cpu_seed")
	RenderingServer.call_on_render_thread(pipeline.initialize_render.bind(domain))
	while not pipeline.initialized and Time.get_ticks_msec()-started<20000:await process_frame
	check("initialized",pipeline.initialized and pipeline.fault_reason().is_empty())
	if not pipeline.fault_reason().is_empty():finish();return
	if probe_case=="checkpoint_physics":
		source_surface=load("res://scenes/unified_edit_height_surface.tscn").instantiate();root.add_child(source_surface)
		source_surface.consumer=pipeline.heights;pipeline.heights.proxy=source_surface;pipeline.heights.hold_physics=true;pipeline.heights.notify_complete()
	if probe_case in ["checkpoint_upload","checkpoint_readback"]:
		RenderingServer.call_on_render_thread(_inject_work_failure)
		await process_frame
	await workload()
	if probe_case not in ["checkpoint_queued","checkpoint_recorded","checkpoint_upload","checkpoint_readback","checkpoint_quantized"]:await await_idle()
	if probe_case=="checkpoint_recorded":
		pause_pump=true;pipeline.hold_completions=true;pipeline.pump();await process_frame;await process_frame
		var deadline:=Time.get_ticks_msec()
		while pipeline.accounting.ledger.sand_source_m3!=0.1 and pipeline.fault_reason().is_empty() and Time.get_ticks_msec()-deadline<10000:await process_frame
		observations.recorded={"active":pipeline.active_count(),"completed_state_seq":pipeline.completed_state_seq,"ledger":pipeline.ledger_snapshot()}
		check("book_on_known_recording_before_cpu_completion",pipeline.active_count()==3 and pipeline.completed_state_seq==0 and pipeline.accounting.ledger.sand_source_m3==0.1 and pipeline.accounting.ledger.sand_sink_m3==0.04)
	if probe_case=="checkpoint_physics":
		var before:=Time.get_ticks_msec()
		while pipeline.heights.active_count()!=2 and Time.get_ticks_msec()-before<10000:await process_frame
		check("two_physical_consumers_held",pipeline.heights.active_count()==2)
	if probe_case=="checkpoint_identity":
		check("max_id_cancelled",pipeline.submit_intent(intent(L.INT64_MAX,&"fill_v1")).accepted and pipeline.cancel_pending(L.INT64_MAX))
	var path:=output.get_base_dir()+"/production.sandue"
	if probe_case=="checkpoint_existing":FileAccess.open(path,FileAccess.WRITE).store_string("sentinel")
	if probe_case in ["checkpoint_existing","checkpoint_identity"]:observations.before_refusal=await snapshot(pipeline,"before_refusal")
	var selection:={"policy":0,"speed":0.0,"brush":{"tool":&"place_sand","parameters":{},"dig_amount_m3":0.05,"fill_amount_m3":0.05}}
	var callback: Callable=_checkpoint_done
	if probe_case=="checkpoint_receiver":receiver=Receiver.new();root.add_child(receiver);callback=receiver.receive
	var accepted:=pipeline.save_checkpoint(path,selection,callback)
	selection.brush.fill_amount_m3=0.9
	if probe_case=="checkpoint_existing":
		check("existing_path_rejected_before_barrier",not accepted.accepted and accepted.error==&"already_exists" and pipeline.checkpoint_capture==null and pipeline.command_highwater()==8 and not pipeline.accounting.stroke.is_empty() and FileAccess.get_file_as_string(path)=="sentinel")
		observations.existing={"text":FileAccess.get_file_as_string(path),"sha256":FileAccess.get_sha256(path)}
		observations.after_refusal=await snapshot(pipeline,"after_refusal")
		for key in observations.before_refusal:check("existing_rejection_unchanged_"+key,observations.before_refusal[key].sha256==observations.after_refusal[key].sha256)
		await shutdown();finish();return
	check("save_accepted",accepted.accepted)
	if not accepted.accepted:await shutdown();finish();return
	if probe_case in ["checkpoint_held","checkpoint_cancel_read","checkpoint_close","checkpoint_receiver"]:pipeline.checkpoint_capture.hold_delivery=true
	if probe_case in ["checkpoint_registration","checkpoint_unknown"]:pipeline.checkpoint_capture.inject_registration_failure_once=true
	if probe_case=="checkpoint_truncate":pipeline.checkpoint_capture.inject_packet_fault_once="truncate"
	if probe_case=="checkpoint_corrupt":pipeline.checkpoint_capture.inject_packet_fault_once="corrupt"
	if probe_case=="checkpoint_unknown":RenderingServer.call_on_render_thread(_disable_idle_proof)
	if probe_case=="checkpoint_cancel":check("cancel_queued_checkpoint",pipeline.cancel_checkpoint())
	check("barrier_blocks_all_new_work",not pipeline.submit_intent(intent(700,&"fill_v1")).accepted and pipeline.request_tick(0.001)==&"checkpoint_busy" and not pipeline.submit_control("end",{"domain_id":"main_beach","generation":9007199254740993,"command_id":701,"sim_tick":0,"stroke_id":8001,"baseline_token":9001}).accepted)
	if probe_case=="checkpoint_recorded":
		check("checkpoint_waits_for_real_completions",checkpoint_callbacks==0 and pipeline.checkpoint_status().phase==&"draining")
		pipeline.hold_completions=false;pause_pump=false
	if probe_case in ["checkpoint_held","checkpoint_cancel_read","checkpoint_close","checkpoint_receiver"]:
		var before:=Time.get_ticks_msec()
		while pipeline.checkpoint_capture!=null and pipeline.checkpoint_capture.held.size()<26 and Time.get_ticks_msec()-before<20000:await process_frame
		observations.held={"status":pipeline.checkpoint_status(),"owners":pipeline.ownership_counts(),"callbacks":checkpoint_callbacks}
		check("all_26_readers_hold_barrier",pipeline.checkpoint_capture!=null and pipeline.checkpoint_capture.pending==26 and checkpoint_callbacks==0 and not pipeline.released)
		RenderingServer.call_on_render_thread(_duplicate_held)
		await process_frame;await process_frame
		if probe_case=="checkpoint_cancel_read":check("cancel_recorded_checkpoint",pipeline.cancel_checkpoint())
		if probe_case=="checkpoint_close":pipeline.close_admission()
		if probe_case=="checkpoint_receiver":receiver.free();receiver=null
		RenderingServer.call_on_render_thread(pipeline.checkpoint_capture.release_held_render)
	if probe_case=="checkpoint_unknown":
		var before:=Time.get_ticks_msec()
		while pipeline.checkpoint_capture!=null and not pipeline.checkpoint_capture.unknown and Time.get_ticks_msec()-before<20000:await process_frame
		observations.unknown={"status":pipeline.checkpoint_status(),"owners":pipeline.ownership_counts(),"callbacks":checkpoint_callbacks,"released":pipeline.released}
		check("unknown_keeps_barrier_and_every_owner",pipeline.checkpoint_capture!=null and pipeline.checkpoint_capture.unknown and checkpoint_callbacks==0 and not pipeline.released and pipeline.request_tick(0.001)==&"checkpoint_busy")
		RenderingServer.call_on_render_thread(_enable_idle_proof);pipeline.retry_checkpoint_lifetime()
	var before:=Time.get_ticks_msec()
	while pipeline.checkpoint_capture!=null and Time.get_ticks_msec()-before<30000:await process_frame
	check("checkpoint_terminal_once",pipeline.checkpoint_capture==null and (checkpoint_callbacks==1 if probe_case!="checkpoint_receiver" else checkpoint_callbacks==0))
	observations.info=pipeline.last_checkpoint_info.duplicate(true);observations.ledger=pipeline.ledger_snapshot();observations.reservations=pipeline.result_reservations();observations.results=pipeline._results.duplicate(true)
	observations.commands=commands.duplicate(true);observations.after=await snapshot(pipeline,"after_checkpoint")
	if probe_case=="checkpoint_receiver":
		var loaded:=Codec.load(path,configuration);check("freed_receiver_still_finishes_safe_save",loaded.error.is_empty() and pipeline.last_checkpoint_info.error.is_empty())
		if loaded.error.is_empty():checkpoint_result={"error":&"","checkpoint":loaded.checkpoint}
	var success: bool=probe_case in ["checkpoint_queued","checkpoint_recorded","checkpoint_completed","checkpoint_physics","checkpoint_capacity","checkpoint_held","checkpoint_receiver","checkpoint_quantized"]
	if success:
		check("production_container_created",checkpoint_result.error.is_empty() and FileAccess.file_exists(path))
		if checkpoint_result.error.is_empty():await verify_saved(path,checkpoint_result.checkpoint)
		else:
			observations.unexpected_failure={"error":String(checkpoint_result.error),"fault":String(pipeline.fault_reason()),"ledger":pipeline.ledger_snapshot()}
			pipeline.cleanup_fault();before=Time.get_ticks_msec()
			while pipeline.active_count()>0 and Time.get_ticks_msec()-before<10000:await process_frame
			if probe_case=="checkpoint_quantized":
				RenderingServer.call_on_render_thread(_read_bad_completion)
				while bad_completion.is_empty() and Time.get_ticks_msec()-before<10000:await process_frame
				observations.unexpected_failure.raw_result=save_fields({"completion":bad_completion},"failed_quantized").completion
	else:
		var expected: StringName={"checkpoint_registration":&"checkpoint_readback_registration","checkpoint_unknown":&"checkpoint_readback_registration","checkpoint_truncate":&"checkpoint_readback_size","checkpoint_corrupt":&"checkpoint_immutable_field_mismatch","checkpoint_cancel":&"checkpoint_cancelled","checkpoint_cancel_read":&"checkpoint_cancelled","checkpoint_close":&"checkpoint_cancelled","checkpoint_identity":&"identity_exhausted","checkpoint_upload":&"upload_failed","checkpoint_readback":&"readback_submit_failed"}[probe_case]
		check("failed_snapshot_never_writes_file",checkpoint_result.error==expected and not FileAccess.file_exists(path))
		observations.failure={"error":String(checkpoint_result.error),"idle_receipt_hex":pipeline.transport.idle_receipt.hex_encode(),"idle_serial":pipeline.transport._idle_serial}
		if probe_case=="checkpoint_identity":
			for key in observations.before_refusal:check("identity_refusal_unchanged_"+key,observations.before_refusal[key].sha256==observations.after[key].sha256)
		if probe_case in ["checkpoint_upload","checkpoint_readback"]:
			check("known_vs_unknown_nominal_history",pipeline.accounting.ledger.sand_source_m3==(0.0 if probe_case=="checkpoint_upload" else 0.1))
			if probe_case=="checkpoint_upload":check("known_unrecorded_results_retained",pipeline.result(1).get("cancelled",false) and pipeline.result(1).get("submitted",true)==false)
			pipeline.cleanup_fault();before=Time.get_ticks_msec()
			while pipeline.active_count()>0 and Time.get_ticks_msec()-before<10000:await process_frame
			check("fault_work_ownership_drained",pipeline.active_count()==0)
		elif probe_case not in ["checkpoint_close","checkpoint_identity"]:
			var id:=pipeline.command_highwater()+1;check("resume_after_failed_snapshot",pipeline.submit_intent(intent(id,&"fill_v1",{"amount_m3":0.01},Vector2(5,4))).accepted);await await_idle();check("resumed_result",pipeline.result(id).outcome==L.Outcome.APPLIED)
	if source_surface!=null:await settle_source_physics()
	await shutdown();finish()

func _checkpoint_done(result: Dictionary) -> void:checkpoint_callbacks+=1;checkpoint_result=result
func _read_bad_completion() -> void:pipeline.transport.rd.buffer_get_data_async(pipeline.transport.resources[0].output,_bad_completion_render,0,96+3*384)
func _bad_completion_render(bytes: PackedByteArray) -> void:call_deferred("_bad_completion_main",bytes)
func _bad_completion_main(bytes: PackedByteArray) -> void:bad_completion=bytes
func _disable_idle_proof() -> void:pipeline.transport.inject_idle_fence_unavailable=true
func _enable_idle_proof() -> void:pipeline.transport.inject_idle_fence_unavailable=false
func _inject_work_failure() -> void:
	if probe_case=="checkpoint_upload":pipeline.transport.inject_upload_failure_once=true
	else:pipeline.transport.inject_readback_failure_once=true

func _duplicate_held() -> void:
	var reader=pipeline.checkpoint_capture;var pending: int=reader.pending;var key: String=reader.held.keys()[0]
	reader._arrived(reader.held[key],key);reader._arrived(reader.held[key],"stale_capture_key")
	call_deferred("check","duplicate_snapshot_readers_do_not_release",reader.pending==pending)

func snapshot(subject, label: String) -> Dictionary:
	snapshot_fields={};snapshot_pending=26;RenderingServer.call_on_render_thread(_snapshot_render.bind(subject))
	var before:=Time.get_ticks_msec()
	while snapshot_pending>0 and Time.get_ticks_msec()-before<10000:await process_frame
	check("snapshot_"+label,snapshot_pending==0 and snapshot_fields.size()==26);return save_fields(snapshot_fields,label)

func _snapshot_render(subject) -> void:
	super._snapshot_render(subject)
	if subject.transport.rd.buffer_get_data_async(subject.executor.buffers.stroke,_snapshot_arrived.bind("stroke"),0,64)!=OK:call_deferred("_snapshot_failed","stroke")

func verify_saved(path: String, checkpoint: Dictionary) -> void:
	var loaded:=Codec.load(path,configuration);check("load_production_container",loaded.error.is_empty() and loaded.get("checkpoint")==checkpoint)
	observations.container={"path":path,"sha256":FileAccess.get_sha256(path)};observations.native=save_native(checkpoint.native,"saved")
	observations.header={"generation":checkpoint.generation,"state_seq":checkpoint.state_seq,"tick":checkpoint.sim_tick,"revision":checkpoint.revision,"time_s":checkpoint.advanced_time_s,"highwater":checkpoint.highwater_id,"ledger":checkpoint.ledger.duplicate(true),"initial_sand_total_m3":checkpoint.initial_sand_total_m3,"nominal_upper_supply":checkpoint.nominal_upper_supply,"selection":checkpoint.selection.duplicate(true),"material_ever_used":checkpoint.native.material.ever_used}
	check("f64_water_history_preserved",checkpoint.ledger.water_source_m3==0.123456789012345 and checkpoint.ledger.water_sink_m3==0.023456789012345)
	check("selection_frozen",checkpoint.selection.brush.fill_amount_m3==0.05)
	check("public_results_not_stolen_by_save",pipeline.result_reservations()==(512 if probe_case=="checkpoint_capacity" else 8) and pipeline._results.size()==pipeline.result_reservations())
	check("private_end_uses_common_gpu_result",pipeline.last_checkpoint_info.end_id==checkpoint.highwater_id and pipeline.last_checkpoint_info.end_result.outcome==L.Outcome.NO_CHANGE and not pipeline._results.has(pipeline.last_checkpoint_info.end_id))
	check("saved_stroke_really_ended",FileAccess.get_file_as_bytes(observations.after.stroke.path).decode_u32(0)==0 and pipeline.accounting.stroke.is_empty())
	if probe_case=="checkpoint_physics":check("save_does_not_wait_for_physics",pipeline.heights.hold_physics and pipeline.heights.active_count()==2)
	if source_surface!=null:await settle_source_physics()
	candidate=Pipeline.new();candidate.restore_verifier.capture_bytes=true
	check("production_restore_configure",candidate.configure_restore(registry,configuration,EPOCH,checkpoint).is_empty())
	RenderingServer.call_on_render_thread(candidate.initialize_render.bind(candidate.restore_domain()))
	var before:=Time.get_ticks_msec()
	while not candidate.initialized and Time.get_ticks_msec()-before<20000:await process_frame
	check("production_restore_actual_35_verifications",candidate._ready and candidate.restore_verifier.passed)
	observations.restored={"records":candidate.restore_verifier.records.duplicate(true),"native":await snapshot(candidate,"restored"),"ledger":candidate.ledger_snapshot()}
	await verify_physics(checkpoint)
	if probe_case=="checkpoint_capacity":
		check("full_results_still_backpressure",not pipeline.submit_intent(intent(pipeline.command_highwater()+1,&"fill_v1")).accepted)
		pipeline.take_result(4)
	for subject in [pipeline,candidate]:
		var id: int=subject.command_highwater()+1;var value:=intent(id,&"fill_v1",{"amount_m3":0.02},Vector2(5,4));value.generation=subject._generation;value.sim_tick=subject.completed_tick
		check("continue_after_save_"+str(subject._generation),subject.submit_intent(value).accepted and subject.request_tick(0.001).is_empty())
	candidate_pump=true;await await_idle();before=Time.get_ticks_msec()
	while (candidate.active_count()>0 or candidate.pending_count()>0) and Time.get_ticks_msec()-before<15000:await process_frame
	observations.continued={"source":await snapshot(pipeline,"continued_source"),"candidate":await snapshot(candidate,"continued_candidate"),"source_ledger":pipeline.ledger_snapshot(),"candidate_ledger":candidate.ledger_snapshot()}
	for key in observations.continued.source:
		if key in ["control","stamp","stroke"]:continue
		check("restored_continuation_exact_"+key,observations.continued.source[key].sha256==observations.continued.candidate[key].sha256)
	check("restored_ledger_continues_exact",pipeline.accounting.ledger==candidate.accounting.ledger)
	var selection: Dictionary=checkpoint.selection.duplicate(true);var result: Dictionary={}
	var requested: Dictionary=candidate.request_checkpoint(selection,func(value: Dictionary):result.merge(value,true))
	check("second_production_snapshot_accepted",requested.accepted);before=Time.get_ticks_msec()
	while result.is_empty() and Time.get_ticks_msec()-before<20000:await process_frame
	check("second_snapshot_restored_history",not result.is_empty() and result.error.is_empty() and result.checkpoint.ledger==candidate.accounting.ledger and result.checkpoint.initial_sand_total_m3==checkpoint.initial_sand_total_m3 and result.checkpoint.native.foam==checkpoint.native.foam)
	if not result.is_empty() and result.error.is_empty():observations.second_native=save_native(result.checkpoint.native,"second_saved");observations.second_header={"ledger":result.checkpoint.ledger,"state_seq":result.checkpoint.state_seq,"tick":result.checkpoint.sim_tick,"highwater":result.checkpoint.highwater_id}

func settle_source_physics() -> void:
	pipeline.heights.hold_physics=false;var before:=Time.get_ticks_msec()
	while (pipeline.heights.active_count()>0 or pipeline.heights.hinted) and Time.get_ticks_msec()-before<15000:await process_frame
	check("source_physics_drained",pipeline.heights.active_count()==0)
	pipeline.heights.close();source_surface.consumer=null;pipeline.heights.proxy=null;source_surface.queue_free();source_surface=null;await process_frame

func finish() -> void:
	observations.callbacks=checkpoint_callbacks;observations.final_ownership=pipeline.ownership_counts();observations.final_fault=String(pipeline.fault_reason())
	# JSON is diagnostic and rounds f64 values. Preserve actual Variant values for
	# independent accounting/result audits without accepting rounded JSON totals.
	var exact:={"results":observations.get("results",{}),"header":observations.get("header",{}),"recorded":observations.get("recorded",{}),"second_header":observations.get("second_header",{}),"continued":observations.get("continued",{}),"ledger":observations.get("ledger",{})}
	var exact_path:=output.get_base_dir()+"/exact_accounting.variant";FileAccess.open(exact_path,FileAccess.WRITE).store_buffer(var_to_bytes(exact))
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"pass":not failed,"case":probe_case,"checks":checks,"observations":observations,"exact_accounting":{"path":exact_path,"bytes":FileAccess.get_file_as_bytes(exact_path).size(),"sha256":FileAccess.get_sha256(exact_path)},"source_hashes":source_hashes,"engine":Engine.get_version_info(),"scope":"Production common checkpoint capture/save, ledger settlement, real automatic END, result retention and native restore continuation. No enabled effects/boundary or formal main scene handoff claim."},"\t"));quit(1 if failed else 0)

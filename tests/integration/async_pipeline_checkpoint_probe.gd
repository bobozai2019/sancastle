extends "res://tests/integration/async_pipeline_main_probe.gd"

const Checkpoint=preload("res://scripts/simulation/edit_validation/frame_pipeline/async_checkpoint_codec.gd")
var snapshot:={}
var admission_during_capture: StringName=&"missing"
var wave_during_capture: StringName=&"missing"
var reference_foam
var reference_front
var front_results:={}
var front_registered:=false
var front_released:=false

func _reference_front_render() -> void:
	reference_foam=preload("res://scripts/simulation/edit_validation/checkpoint_foam_field.gd").new()
	reference_foam.native_history=snapshot.native.foam
	reference_front=preload("res://tests/visual_water_alignment/prototypes/reference_local_front_field.gd").new()
	if not reference_foam.initialize(preview.solver,preview.spirvs[17],PackedFloat32Array(),snapshot.native.fields.rock.to_float32_array(),true) or not reference_front.initialize(preview.solver,reference_foam,preview.local_front_x_spirv,preview.local_front_z_spirv) or not reference_front.dispatch(preview.solver,reference_foam,true):
		call_deferred("_front_registration",false);return
	var rd: RenderingDevice=preview.solver.rd
	for pair in [["original",reference_front.texture],["pipeline",preview.local_front_field.texture]]:
		if rd.texture_get_data_async(pair[1],0,_front_arrived.bind(pair[0]))!=OK:call_deferred("_front_result",PackedByteArray(),pair[0])
	call_deferred("_front_registration",true)

func _front_arrived(bytes: PackedByteArray, key: String) -> void:call_deferred("_front_result",bytes,key)
func _front_result(bytes: PackedByteArray, key: String) -> void:front_results[key]=bytes
func _front_registration(ok: bool) -> void:
	front_registered=true
	if not ok:front_results={"original":PackedByteArray(),"pipeline":PackedByteArray()}
func _release_front_reference() -> void:
	if reference_front!=null:reference_front.release()
	if reference_foam!=null:reference_foam.release()
	call_deferred("_front_release_done")
func _front_release_done() -> void:front_released=true

func _attempt_during_capture() -> void:
	admission_during_capture=preview.input_scheduler.submit(command(9000))
	wave_during_capture=preview.request_wave({"request_id":preview.wave_highwater_id+1}).code

func invalid(label: String, candidate: Dictionary) -> void:
	check(label,not Checkpoint.validate(candidate,preview.source_signature).is_empty())

func _run() -> void:
	preview=load(scene_path).instantiate()
	preview.async_pipeline_enabled=true
	preview.playing=false
	root.add_child(preview)
	var deadline:=Time.get_ticks_msec()+60000
	while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	check("checkpoint_main_ready",preview.ready_for_ticks and preview.async_backend_ready and preview.last_error.is_empty())
	if preview.ready_for_ticks:
		await tools()
		preview._start_tick()
		preview._start_tick()
		for i in 8:check("pending_admission_%d"%i,preview.input_scheduler.submit(command(800+i)).is_empty())
		preview.domain.sand_source_m3+=10.0
		call_deferred("_attempt_during_capture")
		var captured: Dictionary=await preview.capture_async_checkpoint_data()
		check("capture_completed",captured.error.is_empty())
		if captured.error.is_empty():
			snapshot=captured.checkpoint
			check("capture_freezes_input_admission",admission_during_capture==&"transition_busy")
			check("capture_freezes_wave_admission",wave_during_capture==&"transition_busy")
			check("capture_drains_accepted_work",preview.command_queue.pending.is_empty() and preview.async_controller.idle() and preview.completed_ticks==2)
			check("capture_metadata_matches_boundary",snapshot.state_seq==preview.async_controller.state_seq and snapshot.revision==preview.solver.state_revision and snapshot.advanced_time_s==preview.async_controller.actual_time)
			check("capture_versions",snapshot.version==5 and snapshot.native.version==3 and snapshot.pipeline_protocol_version==1)
			check("capture_approximate_without_prefix",snapshot.ledger_precision=="approximate" and snapshot.ledger.sand_source_m3>=10.0 and not snapshot.has("prefix") and not snapshot.has("shadow") and preview.gpu_prefix.is_empty())
			check("capture_material_used",snapshot.native.material.ever_used)
			check("capture_gravel_drop",snapshot.visual_extensions.gravel_v1.active_count==514)
			check("capture_all_authority",snapshot.native.fields.size()==10 and snapshot.native.spare.size()==8 and snapshot.native.foam.size()==5 and snapshot.native.control.size()==128)
			check("effective_local_front_captured",snapshot.simulation.local_front_history and snapshot.native.histories.local_front.size()==65536*8)
			check("effective_local_front_advances",Array(snapshot.native.histories.local_front.to_float32_array()).max()>0.0)
			check("capture_current_raw_matches",snapshot.native.fields.sand==await read("sand") and snapshot.native.fields.water==await read("water"))
			check("capture_gpu_clock_matches",snapshot.advanced_time_s==(await read("clock")).decode_float(0))
			check("capture_admission_restored",preview.input_scheduler.accepting and not preview.async_controller.frozen and not preview.async_checkpoint_running)
			var base:=output.get_basename()
			var save_error:=Checkpoint.save(base+".sandgp",snapshot)
			check("new_container_save",save_error.is_empty())
			check("new_container_create_only",Checkpoint.save(base+".sandgp",snapshot)==&"already_exists")
			var loaded:=Checkpoint.load(base+".sandgp",preview.source_signature)
			check("new_container_roundtrip",loaded.error.is_empty() and loaded.checkpoint==snapshot)
			var file:=FileAccess.open(base+".sandgp",FileAccess.READ)
			var bytes:=file.get_buffer(file.get_length());file.close()
			check("new_container_magic",bytes.slice(0,8).get_string_from_ascii()==Checkpoint.MAGIC)
			bytes[bytes.size()-1]^=1
			file=FileAccess.open(base+"_corrupt.sandgp",FileAccess.WRITE);file.store_buffer(bytes);file.close()
			check("checksum_rejects",Checkpoint.load(base+"_corrupt.sandgp").error==&"checksum_mismatch")
			bytes=bytes.slice(0,47)
			file=FileAccess.open(base+"_short.sandgp",FileAccess.WRITE);file.store_buffer(bytes);file.close()
			check("truncated_rejects",Checkpoint.load(base+"_short.sandgp").error==&"invalid_file_size")
			for field in ["version","pipeline_protocol_version","grid_size","domain_id","generation","state_seq","sim_tick","revision","advanced_time_s","ledger_precision","configuration"]:
				var bad:=snapshot.duplicate(true)
				if field=="configuration":bad.configuration={}
				elif field=="domain_id":bad[field]="other"
				elif field=="ledger_precision":bad[field]="exact"
				elif field=="advanced_time_s":bad[field]=NAN
				else:bad[field]=-1
				invalid("invalid_"+field,bad)
			var bad:=snapshot.duplicate(true);bad.native.fields.sand.encode_float(0,-1.0);invalid("negative_authority",bad)
			bad=snapshot.duplicate(true);bad.version=5.0;invalid("float_version_rejects",bad)
			bad=snapshot.duplicate(true);bad.native.current_index=0.0;invalid("float_slot_rejects",bad)
			bad=snapshot.duplicate(true);bad.native.spare.momentum_x.encode_float(0,NAN);invalid("nan_spare",bad)
			bad=snapshot.duplicate(true);bad.native.fields.wetness.encode_half(0,2.0);invalid("invalid_half",bad)
			bad=snapshot.duplicate(true);bad.native.fields.obstacle[0]=1;invalid("invalid_obstacle",bad)
			bad=snapshot.duplicate(true);bad.native.control.encode_u64(16,snapshot.state_seq+1);invalid("control_state_mismatch",bad)
			bad=snapshot.duplicate(true);bad.native.control.encode_float(32,2.0);invalid("control_clock_mismatch",bad)
			bad=snapshot.duplicate(true);bad.native.control.encode_u32(80,65);invalid("invalid_saved_cfl",bad)
			bad=snapshot.duplicate(true);bad.native.foam.foam_0.encode_float(0,2.0);invalid("invalid_foam",bad)
			bad=snapshot.duplicate(true);bad.native.histories.local_front.encode_float(0,NAN);invalid("invalid_local_front",bad)
			bad=snapshot.duplicate(true);bad.native.material.current_support.encode_float(0,1000000.0);invalid("invalid_material",bad)
			bad=snapshot.duplicate(true);bad.visual_extensions.gravel_v1.state_0.encode_float(0,100.0);invalid("invalid_gravel",bad)
			bad=snapshot.duplicate(true)
			if bad.wave_start_times.is_empty():bad.wave_start_times[1]=0.0
			else:bad.wave_start_times.clear()
			invalid("wave_clock_set_mismatch",bad)
			bad=snapshot.duplicate(true);bad.ledger.sand_source_m3=-1.0;invalid("negative_approximate_ledger",bad)
			bad=snapshot.duplicate(true);bad.simulation.contact_history=true;invalid("unrecorded_history_rejects",bad)
			preview._start_tick()
			check("local_front_reference_tick",await idle())
			RenderingServer.call_on_render_thread(_reference_front_render)
			while not front_registered or front_results.size()!=2:await process_frame
			check("local_front_matches_original_gpu",front_results.original.size()==65536*8 and front_results.original==front_results.pipeline)
			RenderingServer.call_on_render_thread(_release_front_reference)
			while not front_released:await process_frame
			preview.playing=true
			check("public_save_api",(await preview.save_gpu_checkpoint(base+"_api.sandgp")).is_empty())
			check("public_save_resumes_playing",preview.playing and preview.input_scheduler.accepting)
			preview.playing=false
			check("public_save_new_format",Checkpoint.load(base+"_api.sandgp",preview.source_signature).error.is_empty())
			check("post_capture_edit_admission",preview.input_scheduler.submit(command(999)).is_empty())
			check("post_capture_edit_completion",await idle())
		else:print("CAPTURE_ERROR ",captured.error)
	check("checkpoint_runtime_healthy",preview.last_error.is_empty())
	var evidence:={}
	if not snapshot.is_empty():
		evidence={"state_seq":snapshot.state_seq,"tick":snapshot.sim_tick,"actual_time":snapshot.advanced_time_s,"configuration":snapshot.configuration,"domain_id":snapshot.domain_id,"simulation":snapshot.simulation,"wave_request_count":snapshot.wave_requests.size(),"local_front_sha256":digest(snapshot.native.histories.local_front),"sand_sha256":digest(snapshot.native.fields.sand),"water_sha256":digest(snapshot.native.fields.water),"saved_without_prefix":not snapshot.has("prefix")}
	await preview.shutdown()
	check("checkpoint_resources_released",preview.gpu_release_done and preview.solver.rd==null)
	preview.queue_free();await process_frame
	var log_text:=FileAccess.get_file_as_string(output.get_basename()+".log")
	check("checkpoint_no_engine_errors",not log_text.is_empty() and not log_text.contains("SCRIPT ERROR:") and not log_text.contains("\nERROR:"))
	var result:=FileAccess.open(output,FileAccess.WRITE)
	result.store_string(JSON.stringify({"pass":not failed,"checks":checks,"evidence":evidence},"\t"));result.close()
	quit(1 if failed else 0)

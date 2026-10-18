extends "res://tests/integration/async_pipeline_fault_probe.gd"

var task_done:=false
var task_error: StringName=&""
var closed:=false
var cross_evidence:={}

func _save_task() -> void:
	task_error=await preview.save_gpu_checkpoint(output.get_basename()+"_invalid.sandgp")
	task_done=true

func _restore_task(value: Dictionary) -> void:
	task_error=await preview.restore_gpu_checkpoint_data(value)
	task_done=true

func _shutdown_task() -> void:
	await preview.shutdown()
	closed=true

func _wait_task() -> bool:
	var end:=Time.get_ticks_msec()+30000
	while not task_done and Time.get_ticks_msec()<end:await process_frame
	return task_done

func _run() -> void:
	preview=load(scene_path).instantiate();preview.async_pipeline_enabled=true;preview.playing=false;root.add_child(preview)
	var end:=Time.get_ticks_msec()+60000
	while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_msec()<end:await process_frame
	check("cross_owner_ready",preview.ready_for_ticks and preview.async_backend_ready and preview.last_error.is_empty())
	if preview.ready_for_ticks:
		var loaded:=loaded_code()
		var epoch: int=preview.generation
		var old_solver=preview.solver
		if fault_case=="capture-error":
			preview.inject_async_capture_hold_results=true
			call_deferred("_save_task")
			end=Time.get_ticks_msec()+15000
			while (preview.async_capture_owners.is_empty() or preview.async_capture_owners[0].held_results.is_empty()) and Time.get_ticks_msec()<end:await process_frame
			check("cross_capture_native_result_held",preview.async_capture_owners.size()==1 and not task_done)
			var job=preview.async_capture_owners[0]
			preview._fail("GPU pipeline fatal: cross-owner capture boundary")
			call_deferred("_shutdown_task")
			for i in 6:await process_frame
			check("cross_capture_close_retains_cpu_consumer",not closed and not preview.gpu_release_done and old_solver.rd!=null and not preview.async_capture_owners.is_empty())
			job.release_held_results()
			check("cross_capture_returns_failure",await _wait_task() and task_error==&"backend_failed_during_capture")
			check("cross_capture_all_callbacks_drained",job.received.size()==job.expected.size() and job.received.size()>20 and preview.async_capture_owners.is_empty())
		elif fault_case=="candidate-error":
			var baseline: Dictionary=await preview.capture_async_checkpoint_data()
			check("cross_candidate_baseline",baseline.error.is_empty())
			check("cross_candidate_mutation",preview.input_scheduler.submit(command(7300)).is_empty())
			check("cross_candidate_mutation_settled",await idle())
			var seq: int=preview.async_controller.state_seq
			preview.inject_async_candidate_hold_results=true
			call_deferred("_restore_task",baseline.checkpoint)
			end=Time.get_ticks_msec()+20000
			while (preview.beach_restore_candidate==null or preview.beach_restore_candidate.held_results.is_empty()) and Time.get_ticks_msec()<end:await process_frame
			var candidate=preview.beach_restore_candidate
			check("cross_candidate_native_result_held",candidate!=null and candidate.pending>0 and not task_done)
			preview._fail("GPU pipeline fatal: cross-owner candidate boundary")
			call_deferred("_shutdown_task")
			for i in 6:await process_frame
			check("cross_candidate_both_owners_retained",not closed and not candidate.released and old_solver.rd!=null and candidate.solver.rd!=null)
			candidate.release_held_results()
			check("cross_candidate_rejects_late_commit",await _wait_task() and task_error==&"backend_failed_during_restore" and preview.generation==epoch and preview.async_controller.state_seq==seq and preview.solver==old_solver)
			check("cross_candidate_drained_then_discarded",candidate.pending==0 and candidate.observed.size()==31 and candidate.released and candidate.terminal_done and preview.beach_restore_candidate==null)
		elif fault_case=="published-error":
			var baseline: Dictionary=await preview.capture_async_checkpoint_data()
			check("cross_publish_baseline",baseline.error.is_empty())
			check("cross_publish_mutation",preview.input_scheduler.submit(command(7301)).is_empty())
			check("cross_publish_mutation_settled",await idle())
			preview.inject_async_restore_failure_after_publish=true
			task_error=await preview.restore_gpu_checkpoint_data(baseline.checkpoint)
			check("cross_publish_error_bounded",task_error==&"backend_failed_after_restore_commit" and not preview.beach_restore_running and preview.beach_restore_candidate==null)
			check("cross_publish_atomic_commit_not_rollback",preview.generation==epoch+1 and preview.solver!=old_solver and old_solver.rd==null and preview.solver.rd!=null)
			check("cross_publish_new_owner_stopped",not preview.async_controller.fault_reason.is_empty() and not preview.async_controller.slots.accepting and not preview.ready_for_ticks and preview.async_controller.collision.pending.is_empty())
			check("cross_publish_verified_fields_preserved",await read("sand")==baseline.checkpoint.native.fields.sand)
		elif fault_case=="legacy-save-error":
			check("cross_legacy_shape_begin",(await preview.begin_shape_stroke(971)).is_empty())
			preview.collision_proxy.inject_readback_failure_once=true
			var brush:=Brush.make_command(&"wall_v1",{"height_m":0.2,"bottom_width_m":1.0,"top_width_m":0.5},Vector2(-3,-0.25),Vector2(-3,0.25),preview.domain.domain_id,preview.generation,preview.command_queue.last_command_id+1,971,0,preview.completed_ticks,preview.shape_baseline_token)
			check("cross_legacy_shape_admitted",preview.input_scheduler.submit(brush).is_empty())
			preview.input_running=true;preview.call_deferred("_drain_input")
			call_deferred("_save_task")
			check("cross_legacy_save_terminates",await _wait_task() and not task_error.is_empty())
			check("cross_legacy_failed_snapshot_not_saved",not preview.last_error.is_empty() and not preview.async_checkpoint_running and preview.async_capture_owners.is_empty())
		else:
			var before: PackedByteArray=preview.shadow_domain.sand.to_byte_array()
			preview.shadow_revision=-1
			preview.inject_async_shadow_readback_failure_once=true
			preview.async_terminal.inject_unavailable=fault_case=="shadow-unknown"
			check("cross_shadow_failed_before_baseline",not (await preview.begin_shape_stroke(972)).is_empty() and preview.shape_stroke_id==0)
			end=Time.get_ticks_msec()+15000
			while (not preview.async_shadow_jobs.is_empty() or preview.async_fault_probe_running or preview.async_terminal.pending) and Time.get_ticks_msec()<end:await process_frame
			check("cross_shadow_registered_consumers_drained",preview.async_shadow_jobs.is_empty() and preview.async_last_shadow_drain.get("registered")==3 and preview.async_last_shadow_drain.get("received")==3 and preview.shadow_sync_reason.is_empty())
			check("cross_shadow_no_partial_cpu_copy",preview.shadow_domain.sand.to_byte_array()==before and not preview.last_error.is_empty() and not preview.ready_for_ticks)
			if fault_case=="shadow-unknown":
				call_deferred("_dispose_task")
				end=Time.get_ticks_msec()+15000
				while not dispose_done and Time.get_ticks_msec()<end:await process_frame
				check("cross_shadow_unknown_bounded",dispose_done and not dispose_result and preview.async_terminal.unconfirmed_ownership and not preview.gpu_release_done and old_solver.rd!=null)
				preview.async_terminal.inject_unavailable=false
				check("cross_shadow_recover_proof_only",await preview.retry_async_terminal_proof() and not preview.ready_for_ticks)
		check("cross_owner_no_failed_save_file",not FileAccess.file_exists(output.get_basename()+"_invalid.sandgp"))
		check("cross_owner_admission_stays_closed",not preview.ready_for_ticks and not preview.input_scheduler.accepting and not preview.last_error.is_empty())
		cross_evidence={"case":fault_case,"error":preview.last_error,"result_error":String(task_error),"configuration":preview.source_signature,"loaded_scripts":loaded,"shadow_drain":preview.async_last_shadow_drain.duplicate(),"physical_device_loss":false}
		if fault_case in ["capture-error","candidate-error"]:
			end=Time.get_ticks_msec()+20000
			while not closed and Time.get_ticks_msec()<end:await process_frame
		else:await preview.shutdown()
	check("cross_owner_safe_shutdown",preview.gpu_release_done and preview.solver.rd==null and preview.collision_proxy.rd==null and preview.async_terminal.rd==null and preview.async_shadow_jobs.is_empty())
	preview.queue_free();await process_frame
	var log_text:=FileAccess.get_file_as_string(output.get_basename()+".log")
	var errors:=[]
	for line in log_text.split("\n"):
		if line.begins_with("ERROR:"):errors.append(line.strip_edges())
	check("cross_owner_only_expected_error",errors.size()==1 and errors[0].begins_with("ERROR: GPU pipeline fatal:") and not log_text.contains("SCRIPT ERROR:"))
	var file:=FileAccess.open(output,FileAccess.WRITE);file.store_string(JSON.stringify({"pass":not failed,"checks":checks,"evidence":cross_evidence},"\t"));file.close()
	quit(1 if failed else 0)

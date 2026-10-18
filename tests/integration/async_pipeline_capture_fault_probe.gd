extends "res://tests/integration/async_pipeline_fault_probe.gd"

var capture_evidence:={}
var recovered:=false

func _configure_render() -> void:
	preview.solver.async_transport.inject_fence_unavailable=fault_case=="capture-unknown"
	call_deferred("_configured")

func _recover_capture_render() -> void:
	preview.solver.async_transport.inject_fence_unavailable=false
	call_deferred("_retry_capture")

func _retry_capture() -> void:
	for job in preview.async_capture_owners:job.retry_terminal()
	recovered=true

func _run() -> void:
	preview=load(scene_path).instantiate();preview.async_pipeline_enabled=true;preview.playing=false;root.add_child(preview)
	var end:=Time.get_ticks_msec()+60000
	while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_msec()<end:await process_frame
	check("capture_fault_ready",preview.ready_for_ticks and preview.async_backend_ready and preview.last_error.is_empty())
	if preview.ready_for_ticks:
		check("capture_seed_admitted",preview.input_scheduler.submit(command(5000)).is_empty())
		check("capture_seed_settled",await idle())
		var before: PackedByteArray=await read("sand")
		var state: int=preview.async_controller.state_seq
		var revision: int=preview.solver.state_revision
		var source: float=preview.domain.sand_source_m3
		RenderingServer.call_on_render_thread(_configure_render)
		while not configured:await process_frame
		preview.inject_async_capture_registration_failures=999 if fault_case=="capture-all" else 1
		var path:=output.get_basename()+"_invalid.sandgp"
		var save_error: StringName=await preview.save_gpu_checkpoint(path)
		check("capture_failed_without_file",not save_error.is_empty() and not FileAccess.file_exists(path))
		check("capture_no_authority_ack",preview.async_controller.state_seq==state and preview.solver.state_revision==revision and preview.domain.sand_source_m3==source)
		check("capture_failure_boundary_finished",not preview.async_checkpoint_running and not preview.async_controller.frozen and not preview.async_controller.transitioning)
		if fault_case=="capture-unknown":
			check("capture_unknown_owner_retained",save_error==&"checkpoint_ownership_unconfirmed" and preview.async_capture_owners.size()==1 and preview._async_ownership_unconfirmed())
			check("capture_unknown_stops_pipeline",not preview.last_error.is_empty() and not preview.ready_for_ticks and not preview.input_scheduler.accepting)
			var job=preview.async_capture_owners[0]
			RenderingServer.call_on_render_thread(_attempt_release_render)
			while not render_done:await process_frame
			# Direct controller release is not a checkpoint owner API. Root release
			# and SceneService must retain all resources including this controller.
			check("capture_controller_not_partially_released",not render_result and preview.solver.rd!=null)
			call_deferred("_dispose_task")
			end=Time.get_ticks_msec()+15000
			while not dispose_done and Time.get_ticks_msec()<end:await process_frame
			check("capture_unknown_dispose_bounded",dispose_done and not dispose_result and not preview.gpu_release_done and preview.async_shutdown_error==&"ownership_unconfirmed" and preview.is_inside_tree())
			RenderingServer.call_on_render_thread(_recover_capture_render)
			end=Time.get_ticks_msec()+20000
			while (not recovered or not preview.async_capture_owners.is_empty()) and Time.get_ticks_msec()<end:await process_frame
			check("capture_recovery_only_confirms_lifetime",preview.async_capture_owners.is_empty() and job.terminal_done and job.terminal_proofs==1 and not job.unconfirmed_ownership and not preview.last_error.is_empty() and not preview.ready_for_ticks)
			check("capture_registered_cpu_consumers_drained",job.received.size()==job.expected.size() and job.expected.size()>20)
		else:
			check("capture_failed_reads_drained",preview.async_capture_owners.is_empty() and preview.solver.async_transport.terminal_fences==1)
			check("capture_failure_preserves_admission",preview.last_error.is_empty() and preview.ready_for_ticks and preview.input_scheduler.accepting)
			check("capture_failure_preserves_gpu_state",before==await read("sand"))
			var retry: Dictionary=await preview.capture_async_checkpoint_data()
			check("capture_retry_complete_not_placeholder",retry.error.is_empty() and retry.checkpoint.native.fields.sand==before and preview.async_capture_owners.is_empty())
			check("capture_after_failure_edit_admitted",preview.input_scheduler.submit(command(5001)).is_empty())
			preview._start_tick()
			check("capture_after_failure_edit_and_water",await idle() and preview.async_controller.state_seq>state and preview.completed_ticks==1)
		capture_evidence={"case":fault_case,"error":String(save_error),"terminal_fences":preview.solver.async_transport.terminal_fences,"configuration":preview.source_signature,"loaded_scripts":loaded_code(),"physical_device_loss":false}
	await preview.shutdown()
	check("capture_fault_safe_shutdown",preview.gpu_release_done and preview.solver.rd==null and preview.async_capture_owners.is_empty())
	preview.queue_free();await process_frame
	var log_text:=FileAccess.get_file_as_string(output.get_basename()+".log")
	var expected_errors:=1 if fault_case=="capture-unknown" else 0
	var fatal_lines:=0;var unexpected:=[]
	for line in log_text.split("\n"):
		if line.begins_with("ERROR:"):
			if line.begins_with("ERROR: GPU pipeline fatal:"):fatal_lines+=1
			else:unexpected.append(line)
	check("capture_fault_only_expected_errors",fatal_lines==expected_errors and unexpected.is_empty() and not log_text.contains("SCRIPT ERROR:"))
	var file:=FileAccess.open(output,FileAccess.WRITE);file.store_string(JSON.stringify({"pass":not failed,"checks":checks,"evidence":capture_evidence},"\t"));file.close()
	quit(1 if failed else 0)

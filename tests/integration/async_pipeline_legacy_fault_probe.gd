extends "res://tests/integration/async_pipeline_fault_probe.gd"

var legacy_evidence:={}
var close_done:=false

func _configure_render() -> void:
	if fault_case.begins_with("suspended"):preview.solver.inject_receipt_failure_once=true
	elif fault_case.begins_with("shape-register"):preview.shape_gpu.inject_transport_failure_once=true
	else:preview.shape_gpu.hold_finalize=true
	preview.async_terminal.inject_unavailable=fault_case.ends_with("unknown")
	call_deferred("_configured")

func _close_task() -> void:
	await preview.shutdown()
	close_done=true

func _run() -> void:
	preview=load(scene_path).instantiate();preview.async_pipeline_enabled=true;preview.playing=false;root.add_child(preview)
	var end:=Time.get_ticks_msec()+60000
	while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_msec()<end:await process_frame
	check("legacy_fault_ready",preview.ready_for_ticks and preview.async_backend_ready and preview.last_error.is_empty())
	if preview.ready_for_ticks:
		var loaded_at_ready:=loaded_code()
		var before: PackedByteArray=await read("sand")
		var initial_state: int=preview.async_controller.state_seq
		var initial_source: float=preview.domain.sand_source_m3
		var deferred_case:=fault_case.begins_with("shape-finalize")
		if not fault_case.begins_with("suspended"):check("legacy_shape_baseline",(await preview.begin_shape_stroke(901)).is_empty())
		RenderingServer.call_on_render_thread(_configure_render)
		while not configured:await process_frame
		var submitted: Dictionary
		if fault_case.begins_with("suspended"):
			submitted=command(7000);submitted.sand_destination="suspended_v1"
		else:
			submitted=Brush.make_command(&"wall_v1",{"height_m":0.2,"bottom_width_m":1.0,"top_width_m":0.5},Vector2(-3,-0.25),Vector2(-3,0.25),preview.domain.domain_id,preview.generation,preview.command_queue.last_command_id+1,901,0,preview.completed_ticks,preview.shape_baseline_token)
		check("legacy_fault_admitted",preview.input_scheduler.submit(submitted).is_empty())
		if not fault_case.begins_with("suspended"):preview.input_running=true;preview.call_deferred("_drain_input")
		end=Time.get_ticks_msec()+20000
		if deferred_case:
			while preview.shape_gpu.held_finalizations.is_empty() and Time.get_ticks_msec()<end:await process_frame
			check("legacy_native_done_cpu_finalize_held",preview.shape_gpu.held_finalizations.size()==1 and preview.shape_gpu.finalize_pending==1 and preview.solver.receipt_pending)
			preview._fail("GPU pipeline fatal: deferred legacy finalize boundary")
		else:
			while preview.last_error.is_empty() and Time.get_ticks_msec()<end:await process_frame
		check("legacy_fault_stopped",not preview.last_error.is_empty() and not preview.ready_for_ticks and not preview.input_scheduler.accepting and not preview.async_controller.slots.accepting)
		end=Time.get_ticks_msec()+15000
		while (preview.async_fault_probe_running or preview.async_terminal.pending) and Time.get_ticks_msec()<end:await process_frame
		check("legacy_probe_terminal_result",not preview.async_fault_probe_running and not preview.async_terminal.pending and preview.async_terminal.events.size()==1)
		check("legacy_no_normal_batch_ack",preview.async_controller.state_seq==initial_state and preview.async_controller.accepted_commands==0 and preview.domain.sand_source_m3==initial_source and preview.async_controller.records.is_empty())
		RenderingServer.call_on_render_thread(_attempt_release_render)
		while not render_done:await process_frame
		check("legacy_no_release_before_final_stream",not render_result and preview.async_controller.water.rd!=null and preview.solver.rd!=null and (preview.shape_gpu==null or preview.shape_gpu.rd!=null))
		if fault_case.ends_with("unknown"):
			check("legacy_unknown_retained",preview.async_terminal.unconfirmed_ownership and preview._async_ownership_unconfirmed() and preview.async_terminal.anchor.is_valid())
			call_deferred("_dispose_task")
			end=Time.get_ticks_msec()+15000
			while not dispose_done and Time.get_ticks_msec()<end:await process_frame
			check("legacy_unknown_close_bounded",dispose_done and not dispose_result and preview.async_shutdown_error==&"ownership_unconfirmed" and not preview.gpu_release_done and preview.is_inside_tree())
			preview.async_terminal.inject_unavailable=false
			check("legacy_recovered_probe_only",await preview.retry_async_terminal_proof() and not preview.async_terminal.confirmed and not preview.ready_for_ticks)
		if deferred_case:
			call_deferred("_close_task")
			for i in 8:await process_frame
			check("legacy_close_waits_cpu_finalize",not close_done and not preview.gpu_release_done and preview.shape_gpu.finalize_pending==1 and preview.solver.rd!=null)
			preview.shape_gpu.release_held_finalizations()
		end=Time.get_ticks_msec()+15000
		while (preview.input_running or preview.input_scheduler.pumping or preview.gpu_busy or preview.async_legacy_running) and Time.get_ticks_msec()<end:await process_frame
		if not deferred_case:check("legacy_rollback_restores_authority",await read("sand")==before)
		check("legacy_terminal_is_failure",preview.input_scheduler.terminal.size()==1 and not preview.input_scheduler.terminal[0].result.has("status") and preview.input_scheduler.policies.is_empty() and preview.input_scheduler.reservations.is_empty())
		check("legacy_no_cpu_receipt_after_failure",not preview.gpu_settled and preview.gpu_prefix.is_empty() and preview.domain.sand_source_m3==initial_source)
		legacy_evidence={"case":fault_case,"error":preview.last_error,"configuration":preview.source_signature,"loaded_scripts":loaded_at_ready,"terminal_results":preview.input_scheduler.terminal.duplicate(true),"physical_device_loss":false}
		if deferred_case:
			end=Time.get_ticks_msec()+20000
			while not close_done and Time.get_ticks_msec()<end:await process_frame
		else:await preview.shutdown()
		legacy_evidence.terminal_proofs=preview.async_terminal.events.duplicate(true)
	check("legacy_fault_safe_shutdown",preview.gpu_release_done and preview.solver.rd==null and preview.async_terminal.rd==null and preview.async_terminal.confirmed)
	preview.queue_free();await process_frame
	var log_text:=FileAccess.get_file_as_string(output.get_basename()+".log")
	var allowed:="ERROR: GPU pipeline fatal: deferred legacy finalize boundary" if fault_case.begins_with("shape-finalize") else ("ERROR: beach GPU dispatch failed" if fault_case.begins_with("suspended") else "ERROR: shape GPU dispatch failed")
	var errors:=[]
	for line in log_text.split("\n"):
		if line.begins_with("ERROR:"):errors.append(line.strip_edges())
	check("legacy_only_expected_error",errors==[allowed] and not log_text.contains("SCRIPT ERROR:"))
	var file:=FileAccess.open(output,FileAccess.WRITE);file.store_string(JSON.stringify({"pass":not failed,"checks":checks,"evidence":legacy_evidence},"\t"));file.close()
	quit(1 if failed else 0)

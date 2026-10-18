extends "res://tests/integration/async_pipeline_fault_probe.gd"

const ToolBrush=preload("res://scripts/simulation/brushes/brush_protocol.gd")

func _run() -> void:
	preview=load(scene_path).instantiate();preview.playing=false;root.add_child(preview)
	var deadline:=Time.get_ticks_msec()+60000
	while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	check("tool_fault_ready",preview.ready_for_ticks and preview.last_error.is_empty())
	if preview.ready_for_ticks:
		check("tool_fault_begin",(await preview.begin_shape_stroke(901)).is_empty())
		var sequence: int=preview.async_controller.state_seq
		RenderingServer.call_on_render_thread(_configure_render)
		while not configured:await process_frame
		var value:=ToolBrush.make_command(&"wall_v1",{"height_m":0.2,"bottom_width_m":1.0,"top_width_m":0.5},Vector2(3,0),Vector2(3,0.5),preview.domain.domain_id,preview.generation,preview.command_queue.last_command_id+1,901,0,preview.completed_ticks,preview.shape_baseline_token)
		value.material_profile_id=&"molded_v1"
		check("tool_fault_admitted",preview.input_scheduler.submit(value).is_empty())
		deadline=Time.get_ticks_msec()+15000
		while preview.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
		check("tool_fault_reported",preview.last_error.begins_with("GPU pipeline fatal:") and not preview.async_controller.fault_reason.is_empty())
		check("tool_fault_no_false_ack",preview.async_controller.state_seq==sequence and preview.input_scheduler.terminal.all(func(row):return row.command.command_id!=value.command_id or not row.result.has("gpu_complete")))
		check("tool_fault_closes_admission",not preview.input_scheduler.accepting and not preview.async_controller.slots.accepting)
		if fault_case=="unknown":
			deadline=Time.get_ticks_msec()+10000
			while not preview._async_ownership_unconfirmed() and Time.get_ticks_msec()<deadline:await process_frame
			check("tool_unknown_owner_retained",preview._async_ownership_unconfirmed() and preview.async_controller.records.size()==1 and preview.async_controller.tools!=null and preview.solver.rd!=null)
			RenderingServer.call_on_render_thread(_attempt_release_render)
			while not render_done:await process_frame
			check("tool_release_refused_without_proof",not render_result)
			call_deferred("_dispose_task")
			deadline=Time.get_ticks_msec()+10000
			while not dispose_done and Time.get_ticks_msec()<deadline:await process_frame
			check("tool_unknown_close_bounded",dispose_done and not dispose_result and preview.is_inside_tree() and not preview.gpu_release_done)
			RenderingServer.call_on_render_thread(_recover_fence_render)
		deadline=Time.get_ticks_msec()+15000
		while not preview.async_controller.records.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
		check("tool_fault_drains_after_proof",preview.async_controller.records.is_empty() and preview.async_controller.slots.active_count()==0 and not preview.async_controller.unconfirmed_ownership)
		check("tool_fault_exactly_once",preview.async_controller.submitted_edits==2 and preview.async_controller.submitted_water==0 and preview.input_scheduler.terminal.size()==2 and preview.input_scheduler.terminal.filter(func(row):return row.command.command_id==value.command_id).size()==1)
		check("tool_fault_result_aborted",preview.input_scheduler.terminal.any(func(row):return row.command.command_id==value.command_id and row.result.get("aborted",false) and not row.result.has("gpu_complete")))
		fault_evidence={"case":fault_case,"error":preview.last_error,"configuration":preview.source_signature,"events":preview.async_controller.events.duplicate(true),"terminal_fences":preview.solver.async_transport.terminal_fences}
	await preview.shutdown()
	check("tool_fault_safe_release",preview.gpu_release_done and preview.solver.rd==null and preview.async_controller.tools==null)
	preview.queue_free();await process_frame
	var log:=FileAccess.get_file_as_string(output.get_basename()+".log")
	var errors:=[]
	for line in log.split("\n"):
		if line.begins_with("ERROR:"):errors.append(line)
	check("tool_fault_only_expected_error",errors.size()==1 and errors[0].begins_with("ERROR: GPU pipeline fatal:") and not log.contains("SCRIPT ERROR:"))
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"pass":not failed,"checks":checks,"evidence":fault_evidence},"\t"))
	quit(1 if failed else 0)

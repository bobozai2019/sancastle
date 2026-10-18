extends "res://tests/integration/async_pipeline_fault_probe.gd"

var bootstrap_evidence:={}

func _shape_hashes() -> Dictionary:
	var values:={}
	for key in preview.collision_proxy.shapes:
		var node=preview.collision_proxy.shapes[key]
		if node.shape!=null:values[key]=digest(node.shape.map_data.to_byte_array())
	return values

func _configure_render() -> void:
	preview.collision_proxy.inject_readback_failure_once=true
	preview.collision_proxy.terminal.inject_unavailable=fault_case.ends_with("unknown")
	call_deferred("_configured")

func _run() -> void:
	var boot:=fault_case.begins_with("bootstrap")
	preview=load(scene_path).instantiate();preview.async_pipeline_enabled=true;preview.playing=false
	if boot:
		if fault_case.begins_with("bootstrap-collision"):
			preview.get_node("GpuCollisionProxy").inject_readback_failure_once=true
			preview.get_node("GpuCollisionProxy").terminal.inject_unavailable=fault_case.ends_with("unknown")
		else:preview.inject_async_bootstrap_failure_phase=fault_case.trim_prefix("bootstrap-")
	root.add_child(preview)
	var end:=Time.get_ticks_msec()+60000
	while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_msec()<end:await process_frame
	var prior_shapes:={}
	if not boot:
		check("original_collision_main_ready",preview.ready_for_ticks and preview.async_backend_ready)
		prior_shapes=_shape_hashes()
		check("original_collision_has_64_shapes",prior_shapes.size()==64)
		check("original_collision_shape_begin",(await preview.begin_shape_stroke(951)).is_empty())
		RenderingServer.call_on_render_thread(_configure_render)
		while not configured:await process_frame
		var brush:=Brush.make_command(&"wall_v1",{"height_m":0.2,"bottom_width_m":1.0,"top_width_m":0.5},Vector2(-3,-0.25),Vector2(-3,0.25),preview.domain.domain_id,preview.generation,preview.command_queue.last_command_id+1,951,0,preview.completed_ticks,preview.shape_baseline_token)
		check("original_collision_shape_admitted",preview.input_scheduler.submit(brush).is_empty())
		preview.input_running=true;preview.call_deferred("_drain_input")
		end=Time.get_ticks_msec()+20000
		while preview.last_error.is_empty() and Time.get_ticks_msec()<end:await process_frame
	check("bootstrap_or_collision_error_reported",not preview.last_error.is_empty())
	check("bootstrap_no_false_ready",not preview.ready_for_ticks and not preview.input_scheduler.accepting and not preview.async_controller.slots.accepting)
	check("bootstrap_no_new_batch_ack",preview.async_controller.state_seq==0 and preview.async_controller.accepted_commands==0 and preview.completed_ticks==0)
	var proxy=preview.collision_proxy
	var loaded:=loaded_code()
	if fault_case.ends_with("unknown"):
		end=Time.get_ticks_msec()+15000
		while not proxy.terminal.unconfirmed_ownership and Time.get_ticks_msec()<end:await process_frame
		check("original_collision_unknown_keeps_snapshot",proxy.failed_readback_owned and proxy.staging_texture.is_valid() and proxy.uniform_set.is_valid() and proxy.rd!=null and proxy.terminal.anchor.is_valid() and preview._async_ownership_unconfirmed())
		RenderingServer.call_on_render_thread(_attempt_release_render)
		while not render_done:await process_frame
		check("original_collision_no_partial_release",not render_result and preview.solver.rd!=null and proxy.rd!=null)
		call_deferred("_dispose_task")
		end=Time.get_ticks_msec()+15000
		while not dispose_done and Time.get_ticks_msec()<end:await process_frame
		check("original_collision_close_bounded",dispose_done and not dispose_result and not preview.gpu_release_done and preview.async_shutdown_error==&"ownership_unconfirmed" and preview.is_inside_tree())
		proxy.terminal.inject_unavailable=false
		proxy.retry_failed_readback()
	if "collision" in fault_case:
		end=Time.get_ticks_msec()+15000
		while (proxy.failed_readback_owned or proxy.terminal_running) and Time.get_ticks_msec()<end:await process_frame
		check("original_collision_proof_discards_snapshot",not proxy.failed_readback_owned and not proxy.staging_texture.is_valid() and not proxy.uniform_set.is_valid() and proxy.terminal.confirmed and proxy.invalid_readbacks==1)
		check("original_collision_failure_stays_stopped",not preview.ready_for_ticks and not preview.input_scheduler.accepting and not preview.last_error.is_empty())
		if not boot:check("original_collision_previous_shapes_retained",_shape_hashes()==prior_shapes)
	check("bootstrap_save_rejected",not (await preview.save_gpu_checkpoint(output.get_basename()+"_invalid.sandgp")).is_empty() and not FileAccess.file_exists(output.get_basename()+"_invalid.sandgp"))
	bootstrap_evidence={"case":fault_case,"error":preview.last_error,"configuration":preview.source_signature,"loaded_scripts":loaded,"old_collision_terminal":proxy.terminal.events.duplicate(true),"physical_device_loss":false}
	await preview.shutdown()
	check("bootstrap_all_owners_released",preview.gpu_release_done and preview.solver.rd==null and preview.async_controller.water.rd==null and preview.async_controller.collision.rd==null and proxy.rd==null and proxy.terminal.rd==null and preview.async_terminal.rd==null)
	bootstrap_evidence.final_stream=preview.async_terminal.events.duplicate(true)
	preview.queue_free();await process_frame
	var log_text:=FileAccess.get_file_as_string(output.get_basename()+".log")
	var errors:=[]
	for line in log_text.split("\n"):
		if line.begins_with("ERROR:"):errors.append(line.strip_edges())
	check("bootstrap_only_expected_error",errors.size()==1 and (errors[0].begins_with("ERROR: GPU pipeline fatal:") or errors[0].begins_with("ERROR: GPU pipeline initialization:")) and not log_text.contains("SCRIPT ERROR:"))
	var file:=FileAccess.open(output,FileAccess.WRITE);file.store_string(JSON.stringify({"pass":not failed,"checks":checks,"evidence":bootstrap_evidence},"\t"));file.close()
	quit(1 if failed else 0)

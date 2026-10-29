extends "res://tests/integration/async_pipeline_fault_probe.gd"

func _configure_render() -> void:
	preview.async_controller.collision.inject_readback_failure_once=true
	preview.solver.async_transport.inject_fence_unavailable=fault_case=="height-unknown"
	call_deferred("_configured")

func _run() -> void:
	preview=load(scene_path).instantiate();preview.async_pipeline_enabled=true;preview.playing=false;root.add_child(preview)
	var end:=Time.get_ticks_msec()+60000
	while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_msec()<end:await process_frame
	check("height_fault_ready",preview.ready_for_ticks and preview.last_error.is_empty())
	if preview.ready_for_ticks:
		preview.async_controller.collision.observe=true
		RenderingServer.call_on_render_thread(_configure_render)
		while not configured:await process_frame
		check("height_fault_edit_admitted",preview.input_scheduler.submit(command(3400)).is_empty())
		var heights=preview.async_controller.collision
		if fault_case=="height-unknown":
			end=Time.get_ticks_msec()+20000
			while not heights.unconfirmed_ownership and Time.get_ticks_msec()<end:await process_frame
			check("height_fault_unknown_retained",heights.unconfirmed_ownership and heights.active_count()>0 and not heights.blocked_fences.is_empty() and preview._async_ownership_unconfirmed())
			end=Time.get_ticks_msec()+20000
			while not preview.async_controller.records.is_empty() and Time.get_ticks_msec()<end:await process_frame
			RenderingServer.call_on_render_thread(_attempt_release_render)
			while not render_done:await process_frame
			check("height_fault_dependent_resources_kept",not render_result and heights.rd!=null and preview.async_controller.water.rd!=null and preview.solver.rd!=null)
			call_deferred("_dispose_task")
			end=Time.get_ticks_msec()+15000
			while not dispose_done and Time.get_ticks_msec()<end:await process_frame
			check("height_fault_close_bounded",dispose_done and not dispose_result and preview.is_inside_tree() and not preview.gpu_release_done and preview.async_shutdown_error==&"ownership_unconfirmed")
			RenderingServer.call_on_render_thread(_recover_fence_render)
			end=Time.get_ticks_msec()+20000
			while heights.active_count()>0 and Time.get_ticks_msec()<end:await process_frame
			check("height_fault_terminal_releases_only_after_proof",heights.active_count()==0 and not heights.unconfirmed_ownership and heights.blocked_fences.is_empty())
			check("height_fault_pipeline_stays_failed",not preview.async_controller.fault_reason.is_empty() and not preview.input_scheduler.accepting and not preview.last_error.is_empty())
		else:
			end=Time.get_ticks_msec()+20000
			while heights.invalid_results==0 and Time.get_ticks_msec()<end:await process_frame
			check("height_fault_retry_drains",await idle() and heights.invalid_results==1 and not heights.unconfirmed_ownership and preview.last_error.is_empty())
			var rock: PackedFloat32Array=(await read("rock")).to_float32_array()
			var sand: PackedFloat32Array=(await read("sand")).to_float32_array()
			for i in rock.size():rock[i]+=sand[i]
			var exact: bool=not heights.applied_state_seq.is_empty()
			for chunk in heights.applied_state_seq:
				var values: PackedFloat32Array=preview.collision_proxy.shapes[chunk].shape.map_data
				for z in 33:
					for x in 33:
						exact=exact and values[z*33+x]==rock[mini((chunk/8)*32+z,255)*256+mini((chunk%8)*32+x,255)]
			check("height_fault_real_height_recovered",exact)
			check("height_fault_input_continues",preview.input_scheduler.submit(command(3401)).is_empty())
			preview._start_tick()
			check("height_fault_water_continues",await idle() and preview.completed_ticks==1 and preview.last_error.is_empty())
		check("height_fault_fence_was_real",preview.solver.async_transport.terminal_fences>0)
		fault_evidence={"case":fault_case,"configuration":preview.source_signature,"loaded_scripts":loaded_code(),"height_events":heights.events.duplicate(true),"invalid_results":heights.invalid_results,"terminal_fences":preview.solver.async_transport.terminal_fences,"pipeline_error":preview.last_error,"physical_device_loss":false}
	await preview.shutdown()
	check("height_fault_shutdown_safe",preview.gpu_release_done and preview.solver.rd==null and preview.async_controller.collision.rd==null and preview.async_controller.water.rd==null)
	preview.queue_free();await process_frame
	var log_text:=FileAccess.get_file_as_string(output.get_basename()+".log")
	var unexpected:=[];var expected:=0
	for line in log_text.split("\n"):
		if line.begins_with("ERROR:"):
			if line.begins_with("ERROR: GPU pipeline fatal: collision:height_terminal_unavailable"):expected+=1
			else:unexpected.append(line)
	check("height_fault_only_expected_error",not log_text.is_empty() and not log_text.contains("SCRIPT ERROR:") and unexpected.is_empty() and expected==(1 if fault_case=="height-unknown" else 0))
	var file:=FileAccess.open(output,FileAccess.WRITE);file.store_string(JSON.stringify({"pass":not failed,"checks":checks,"evidence":fault_evidence},"\t"));file.close()
	quit(1 if failed else 0)

extends "res://tests/water_material_natural/capture.gd"

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	var setup:={"requested_viewport":[1920,1080],"initial_window_size":root.size,
		"initial_window_mode":root.mode,"screen_size":DisplayServer.screen_get_size(),
		"screen_usable_rect":DisplayServer.screen_get_usable_rect()}
	root.mode=Window.MODE_EXCLUSIVE_FULLSCREEN
	for i in range(8):await process_frame
	setup["fullscreen_window_size"]=root.size
	setup["fullscreen_window_mode"]=root.mode
	setup["window_visible"]=root.visible
	var file:=FileAccess.open(output+"/window_setup.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(setup,"\t"));file.close()
	if root.size!=Vector2i(1920,1080) or not root.visible:
		_fail("native fullscreen output is not visible 1920x1080; see window_setup.json");return
	await super._run()

func _lighting_sweep(before: Dictionary) -> void:
	if root.size != Vector2i(1920,1080) or not root.visible or root.mode == Window.MODE_MINIMIZED:
		_fail("full cost requires visible 1920x1080 window");return
	preview.set_fixture_camera(&"close")
	var viewport_rid := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(viewport_rid,true)
	# Same completed warm state, all scene layers and solver resources retained.
	for i in range(60):
		await process_frame
		await RenderingServer.frame_post_draw
	var frame_ms := []
	var gpu_ms := []
	var cpu_ms := []
	var tick_samples := []
	var start_tick: int = preview.completed_ticks
	var initial_visual_time: float = preview.visual_time_s
	var start_revision: int = preview.solver.state_revision
	var initial_style: Dictionary = preview.get("effective_style") if preview.get("effective_style") is Dictionary else {}
	var sampling_start_unix := Time.get_unix_time_from_system()
	var start := Time.get_ticks_usec()
	var previous := start
	preview.accumulator = 0.
	preview.replay_target_tick = -1
	preview.playing = true
	while Time.get_ticks_usec() - start < 60000000:
		await process_frame
		await RenderingServer.frame_post_draw
		if not preview.last_error.is_empty():_fail("full cost runtime: "+preview.last_error);return
		if not root.visible or root.mode == Window.MODE_MINIMIZED or root.size != Vector2i(1920,1080):
			_fail("full cost window became hidden/minimized/resized");return
		var now := Time.get_ticks_usec()
		frame_ms.append(float(now-previous)/1000.);previous=now
		gpu_ms.append(RenderingServer.viewport_get_measured_render_time_gpu(viewport_rid))
		cpu_ms.append(RenderingServer.viewport_get_measured_render_time_cpu(viewport_rid))
		tick_samples.append({"wall_us":now-start,"completed_tick":preview.completed_ticks,
			"revision":preview.solver.state_revision,"tick_pending":preview.tick_pending,"visual_time_s":preview.visual_time_s})
	var endpoint_tick: int = preview.completed_ticks
	var endpoint_time: float = preview.visual_time_s
	preview.playing = false
	var endpoint_image := output + "/window_endpoint.png"
	root.get_texture().get_image().save_png(endpoint_image)
	var file := FileAccess.open(output + "/full_cost.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"frame_ms":frame_ms,"gpu_render_ms":gpu_ms,"cpu_render_ms":cpu_ms,
		"ticks":tick_samples,"sampling_elapsed_us":previous-start,"sampling_start_unix":sampling_start_unix,
		"sampling_end_unix":sampling_start_unix+float(previous-start)/1000000.,
		"start_tick":start_tick,"endpoint_tick":endpoint_tick,"start_revision":start_revision,
		"initial_visual_time_s":initial_visual_time,"endpoint_visual_time_s":endpoint_time,
		"initial_fields":before,"initial_style":initial_style,"viewport_px":root.size,
		"window_visible":root.visible,"window_mode":root.mode,"window_position":DisplayServer.window_get_position(),
		"screen_size":DisplayServer.screen_get_size(),"adapter":RenderingServer.get_video_adapter_name(),
		"driver":RenderingServer.get_current_rendering_driver_name(),"vsync":DisplayServer.window_get_vsync_mode(),
		"render_scale":root.scaling_3d_scale,"msaa":root.msaa_3d,"screen_aa":root.screen_space_aa,"taa":root.use_taa,
		"enable_erosion":preview.enable_erosion,"wave_workload":preview.staging_wave_workload,
		"wave_requests":preview.wave_requests,"edit_commands":[],"requested_profile":preview.render_profile_path,
		"requested_profile_sha256":preview.requested_render_profile_sha256,
		"water_shader":preview.water_material.shader.resource_path,"water_shader_sha256":FileAccess.get_sha256(preview.water_material.shader.resource_path),
		"endpoint_image":endpoint_image,"endpoint_image_sha256":FileAccess.get_sha256(endpoint_image),
		"measurement":"60 wall seconds of visible full scene with active ordinary water/sand simulation and repeated wave schedule; no edits in this input. Frame-post-draw intervals include CPU/render scheduling; GPU/CPU render monitors are supplemental, not solver-inclusive GPU timings. Initialization and 60 frozen warm frames excluded. Tick endpoints recorded; not fixed-state rendering or 30Hz throughput proof."},"\t"));file.close()

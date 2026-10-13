extends SceneTree

const MOVIE_SCENE = preload("res://tests/visual_water_alignment/prototypes/reference_local_front_movie.tscn")

var output_dir := ""
var run_id := ""
var crest_height_m := 0.25
var lift_depth_scale := 1.5
var front_foam_enabled := true
var foreground_mode := 0
var foreground_orbit := false
var target_tick := 240
var args_valid := true


func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			output_dir = arg.trim_prefix("--output=")
		elif arg.begins_with("--run-id="):
			run_id = arg.trim_prefix("--run-id=")
		elif arg.begins_with("--crest-height="):
			crest_height_m = float(arg.trim_prefix("--crest-height="))
		elif arg.begins_with("--lift-depth-scale="):
			lift_depth_scale = float(arg.trim_prefix("--lift-depth-scale="))
		elif arg.begins_with("--tick="):
			target_tick = int(arg.trim_prefix("--tick="))
		elif arg == "--no-front-foam":
			front_foam_enabled = false
		elif arg.begins_with("--foreground-mode="):
			foreground_mode = int(arg.trim_prefix("--foreground-mode="))
		elif arg == "--foreground-orbit":
			foreground_orbit = true
		else:
			args_valid = false
	call_deferred("_run")


func _run() -> void:
	if not args_valid or output_dir.is_empty() or run_id.is_empty() or \
			target_tick < 1 or crest_height_m < 0.0 or crest_height_m > 0.4 or \
			lift_depth_scale < 1.0 or lift_depth_scale > 3.0 or \
			foreground_mode < 0 or foreground_mode > 2 or \
			(foreground_mode > 0 and not foreground_orbit) or \
			not DirAccess.dir_exists_absolute(output_dir) or \
			root.size != Vector2i(1920, 1080) or \
			DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED:
		_fail("arguments or viewport invalid")
		return
	var preview: Node3D = MOVIE_SCENE.instantiate()
	preview.movie_crest_height_m = crest_height_m
	preview.movie_lift_depth_scale = lift_depth_scale
	preview.movie_front_foam_enabled = front_foam_enabled
	preview.movie_foreground_mode = foreground_mode
	root.add_child(preview)
	var frames := 0
	while not preview.ready_for_ticks and preview.last_error.is_empty() and frames < 1800:
		await process_frame
		frames += 1
	if not preview.ready_for_ticks or not preview.last_error.is_empty() or \
			preview.wave_requests.size() != 80:
		_fail("initialization: " + preview.last_error)
		return
	if foreground_orbit:
		_set_foreground_orbit_camera(preview, 0.0)
	else:
		preview.aim_player_camera(Vector3(-6.2, 1.5, -7.9),
			Vector3(-2.6, 0.18, -6.9))
	preview.player_camera.fov = 50.0
	preview.set_player_camera(true)
	var camera_transform: Transform3D = preview.player_camera.global_transform
	var timeline := []
	frames = 0
	while preview.completed_ticks < target_tick and preview.last_error.is_empty() and \
			frames < 18000:
		if foreground_orbit:
			_set_foreground_orbit_camera(preview,
				float(frames) / float(target_tick * 2))
		await process_frame
		frames += 1
		timeline.append({"drawn_frame": Engine.get_frames_drawn(),
			"completed_tick": preview.completed_ticks,
			"visual_time_s": preview.visual_time_s,
			"source_started": bool(preview.water_material.get_shader_parameter(
				"prototype_front_face_source_started"))})
	preview.playing = false
	while preview.tick_pending and frames < 18300:
		await process_frame
		frames += 1
		timeline.append({"drawn_frame": Engine.get_frames_drawn(),
			"completed_tick": preview.completed_ticks,
			"visual_time_s": preview.visual_time_s,
			"source_started": bool(preview.water_material.get_shader_parameter(
				"prototype_front_face_source_started"))})
	if not preview.last_error.is_empty() or preview.completed_ticks != target_tick or \
			preview.tick_pending or timeline.size() != target_tick * 2:
		_fail("runtime tick/timeline: " + preview.last_error)
		return
	var movie_prefix := output_dir.path_join(run_id + "_coupled")
	var timeline_file := FileAccess.open(movie_prefix + "_timeline.json", FileAccess.WRITE)
	if timeline_file == null:
		_fail("timeline write")
		return
	timeline_file.store_string(JSON.stringify(timeline, "\t"))
	timeline_file.close()
	var manifest := {"role": "w09_local_front_height_movie",
		"run_id": run_id, "case": "coupled", "target_tick": target_tick,
		"completed_tick": preview.completed_ticks,
		"visual_time_s": preview.visual_time_s,
		"crest_height_m": crest_height_m,
		"lift_depth_scale": lift_depth_scale,
		"foreground_mode": foreground_mode,
		"foreground_orbit": foreground_orbit,
		"front_foam_enabled": front_foam_enabled,
		"wave_requests": preview.wave_requests,
		"viewport_px": [root.size.x, root.size.y],
		"camera_transform": str(camera_transform),
		"water_shader": preview.water_material.shader.resource_path,
		"timeline_sample_count": timeline.size(),
		"rendering_driver": RenderingServer.get_current_rendering_driver_name(),
		"adapter": RenderingServer.get_video_adapter_name()}
	var file := FileAccess.open(movie_prefix + "_manifest.json", FileAccess.WRITE)
	if file == null:
		_fail("manifest write")
		return
	file.store_string(JSON.stringify(manifest, "\t"))
	file.close()
	print("PASS: W09 local front height movie tick=%d" % preview.completed_ticks)
	quit(0)


func _set_foreground_orbit_camera(preview: Node3D, phase: float) -> void:
	var x := -2.6 + lerpf(-3.0, 3.0, clampf(phase, 0.0, 1.0))
	preview.aim_player_camera(Vector3(x, 1.5, -10.9),
		Vector3(-2.6, 0.5, -6.9))


func _fail(message: String) -> void:
	printerr("FAIL: W09 local front height movie " + message)
	quit(1)

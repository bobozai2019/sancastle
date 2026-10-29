extends SceneTree

const SCENE := preload("res://scenes/water_render_coupled_v8_preview.tscn")
const PROFILE := "res://tests/visual_water_alignment/prototypes/water_render_staging_v8.json"
const SAMPLE_FIRST := 900
const SAMPLE_LAST := 9900
const SAMPLE_STEP := 30
const PIXEL_STRIDE := 4
const CHANNEL_DELTA := 12

var output_dir := ""
var run_id := ""
var preview: Node3D


func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			output_dir = arg.trim_prefix("--output=")
		elif arg.begins_with("--run-id="):
			run_id = arg.trim_prefix("--run-id=")
	call_deferred("_run")


func _run() -> void:
	if output_dir.is_empty() or run_id.is_empty() or not DirAccess.dir_exists_absolute(output_dir) or root.size != Vector2i(1920, 1080) or DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED:
		_fail("arguments or 1080p/VSync-off viewport")
		return
	preview = SCENE.instantiate()
	root.add_child(preview)
	var frames := 0
	while not preview.ready_for_ticks and preview.last_error.is_empty() and frames < 1800:
		await process_frame
		frames += 1
	if not preview.ready_for_ticks or not preview.last_error.is_empty() or preview.render_profile_path != PROFILE or preview.requested_render_profile_sha256 != FileAccess.get_sha256(PROFILE) or preview.staging_wave_workload != "continuous_packets_v1" or preview.wave_requests.size() != 80:
		_fail("initialization/profile/workload: " + preview.last_error)
		return
	preview.playing = false
	while preview.tick_pending:
		await process_frame
	preview.accumulator = 0.0
	if not preview.set_fixture_camera(&"close"):
		_fail("close camera")
		return
	var initial_hashes := {
		"rock": hash(preview.shadow_domain.rock),
		"sand": hash(preview.shadow_domain.sand),
		"water": hash(preview.shadow_domain.water),
	}
	var material: ShaderMaterial = preview.water_material
	var settings := {
		"phase2_foam": material.get_shader_parameter("phase2_foam"),
		"prototype_crest_white_face": material.get_shader_parameter("prototype_crest_white_face"),
		"prototype_offshore_core": material.get_shader_parameter("prototype_offshore_core"),
		"prototype_front_face_rim_tone": material.get_shader_parameter("prototype_front_face_rim_tone"),
	}
	var csv_path := output_dir.path_join(run_id + "_timeline.csv")
	var csv := FileAccess.open(csv_path, FileAccess.WRITE)
	if csv == null:
		_fail("CSV open")
		return
	csv.store_csv_line(["tick", "revision", "whitewater_delta_pixels_estimate",
		"whitewater_delta_ratio", "elapsed_s"])
	var samples := []
	var screenshots := []
	var start_us := Time.get_ticks_usec()
	for sample_tick in range(SAMPLE_FIRST, SAMPLE_LAST + 1, SAMPLE_STEP):
		var steps := 0
		while preview.completed_ticks < sample_tick and preview.last_error.is_empty() and steps < SAMPLE_STEP * 600:
			if not preview.tick_pending and not preview.checkpoint_capture_pending:
				preview._start_tick()
			await process_frame
			steps += 1
		if preview.completed_ticks != sample_tick or preview.tick_pending or 	not preview.last_error.is_empty():
			csv.close()
			_fail("sample tick %d got %d: %s" % [
				sample_tick, preview.completed_ticks, preview.last_error])
			return
		preview.set_visual_time(float(sample_tick) / 30.0)
		for settle in 3:
			await RenderingServer.frame_post_draw
		var normal := root.get_texture().get_image()
		normal.convert(Image.FORMAT_RGBA8)
		for key in settings:
			material.set_shader_parameter(key, false)
		for settle in 3:
			await RenderingServer.frame_post_draw
		var ablated := root.get_texture().get_image()
		ablated.convert(Image.FORMAT_RGBA8)
		for key in settings:
			material.set_shader_parameter(key, settings[key])
		if normal.get_size() != Vector2i(1920, 1080) or 	ablated.get_size() != Vector2i(1920, 1080):
			csv.close()
			_fail("screen size at tick %d" % sample_tick)
			return
		var a := normal.get_data()
		var b := ablated.get_data()
		var changed := 0
		for y in range(0, 1080, PIXEL_STRIDE):
			for x in range(0, 1920, PIXEL_STRIDE):
				var at := (y * 1920 + x) * 4
				if maxi(absi(int(a[at]) - int(b[at])),
						maxi(absi(int(a[at + 1]) - int(b[at + 1])),
						absi(int(a[at + 2]) - int(b[at + 2])))) >= CHANNEL_DELTA:
					changed += 1
		var estimate := changed * PIXEL_STRIDE * PIXEL_STRIDE
		var ratio := float(changed) / float(1920 * 1080 / (PIXEL_STRIDE * PIXEL_STRIDE))
		var elapsed := float(Time.get_ticks_usec() - start_us) / 1000000.0
		csv.store_csv_line([str(sample_tick), str(preview.solver.state_revision),
			str(estimate), "%.8f" % ratio, "%.6f" % elapsed])
		samples.append({"tick": sample_tick, "revision": preview.solver.state_revision,
			"delta_pixels_estimate": estimate, "ratio": ratio})
		if sample_tick in [900, 1800, 3600, 5400, 7200, 9000, 9900]:
			var normal_path := output_dir.path_join("%s_tick%d_normal.png" % [run_id, sample_tick])
			var ablated_path := output_dir.path_join("%s_tick%d_ablated.png" % [run_id, sample_tick])
			if normal.save_png(normal_path) != OK or ablated.save_png(ablated_path) != OK:
				csv.close()
				_fail("PNG write at tick %d" % sample_tick)
				return
			screenshots.append(normal_path)
			screenshots.append(ablated_path)
		if sample_tick % 900 == 0:
			print("FOAM_TIMELINE tick=%d delta_px=%d" % [sample_tick, estimate])
	csv.close()
	var manifest := {
		"role": "w14_v8_visible_foam_timeline",
		"run_id": run_id,
		"profile_sha256": preview.requested_render_profile_sha256,
		"effective_profile_sha256": preview.effective_render_profile_sha256,
		"fixture_id": String(preview.fixture_id),
		"wave_requests": preview.wave_requests.size(),
		"camera": "close",
		"initial_hashes": initial_hashes,
		"viewport_px": [root.size.x, root.size.y],
		"adapter": RenderingServer.get_video_adapter_name(),
		"sample_first_tick": SAMPLE_FIRST,
		"sample_last_tick": SAMPLE_LAST,
		"sample_step_ticks": SAMPLE_STEP,
		"ablation_parameters": settings,
		"pixel_stride": PIXEL_STRIDE,
		"channel_delta_8bit": CHANNEL_DELTA,
		"csv": csv_path,
		"screenshots": screenshots,
		"samples": samples,
		"nan_events": preview.solver.nan_events,
		"overload_events": preview.solver.overload_events,
		"wave_clamp_events": preview.wave_clamp_events,
	}
	var file := FileAccess.open(output_dir.path_join(run_id + "_manifest.json"), FileAccess.WRITE)
	if file == null:
		_fail("manifest write")
		return
	file.store_string(JSON.stringify(manifest, "\t"))
	file.close()
	print("PASS: W14 v8 whitewater timeline samples=%d" % samples.size())
	quit(0)


func _fail(message: String) -> void:
	printerr("FAIL: W14 v8 whitewater timeline " + message)
	quit(1)


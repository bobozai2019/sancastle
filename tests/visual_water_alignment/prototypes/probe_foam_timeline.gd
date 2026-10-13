extends SceneTree

const WATER_SCENE := preload("res://tests/visual_water_alignment/prototypes/reference_fixed.tscn")
const COUPLED_SCENE := preload("res://tests/visual_water_alignment/prototypes/reference_coupled.tscn")
const GRID_SIZE := 256
const SNAPSHOT_TICKS := [360, 900, 1500, 2100, 2700]

var case_id := "coupled"
var wave_load := "continuous"
var output_dir := ""
var run_id := ""
var target_tick := 2700
var interval_ticks := 60
var readbacks := {}
var preview: Node3D


func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--case="):
			case_id = arg.trim_prefix("--case=")
		elif arg.begins_with("--wave-load="):
			wave_load = arg.trim_prefix("--wave-load=")
		elif arg.begins_with("--output="):
			output_dir = arg.trim_prefix("--output=")
		elif arg.begins_with("--run-id="):
			run_id = arg.trim_prefix("--run-id=")
		elif arg.begins_with("--target-tick="):
			target_tick = int(arg.trim_prefix("--target-tick="))
		elif arg.begins_with("--interval="):
			interval_ticks = int(arg.trim_prefix("--interval="))
	call_deferred("_run")


func _run() -> void:
	if case_id not in ["water", "coupled"] or wave_load not in ["continuous", "none"] or \
			output_dir.is_empty() or run_id.is_empty() or target_tick < 1 or \
			interval_ticks < 1 or target_tick % interval_ticks != 0:
		_fail("invalid arguments")
		return
	if root.size != Vector2i(1920, 1080) or not DirAccess.dir_exists_absolute(output_dir):
		_fail("requires existing output and actual 1920x1080 viewport")
		return
	preview = WATER_SCENE.instantiate() if case_id == "water" else COUPLED_SCENE.instantiate()
	root.add_child(preview)
	var init_us := Time.get_ticks_usec()
	while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_usec() - init_us < 30000000:
		await process_frame
	if not preview.ready_for_ticks or not preview.last_error.is_empty():
		_fail("fixture initialization: " + preview.last_error)
		return
	preview.playing = false
	while preview.tick_pending:
		await process_frame
	if preview.completed_ticks >= interval_ticks:
		_fail("fixture advanced before controlled stepping")
		return
	preview.accumulator = 0.0
	preview.water_material.set_shader_parameter("prototype_eta_normals", true)
	preview.water_material.set_shader_parameter("prototype_crest_height_m", 0.16)
	preview.water_material.set_shader_parameter("prototype_irregular_foam", true)
	preview.water_material.set_shader_parameter("prototype_screen_optics", false)
	if not preview.set_fixture_camera(&"oblique"):
		_fail("oblique camera unavailable")
		return
	var initial_hashes := {"rock": hash(preview.shadow_domain.rock),
		"sand": hash(preview.shadow_domain.sand),
		"water": hash(preview.shadow_domain.water)}
	var requests: Array[Dictionary] = []
	if wave_load == "continuous":
		for request_id in range(1, 81):
			var request := {"domain_id": preview.shadow_domain.domain_id,
				"generation": preview.generation, "request_id": request_id,
				"start_tick": preview.completed_ticks + 8 + (request_id - 1) * 180,
				"profile_id": &"test_packet", "amplitude_m": 0.18,
				"duration_s": 6.0, "seed": 31 + request_id * 17}
			var admitted: Dictionary = preview.request_wave(request)
			if not admitted.ok:
				_fail("wave rejected: " + String(admitted.code))
				return
			requests.append(request)
	var csv_path := output_dir.path_join("%s_%s_timeline.csv" % [run_id, case_id])
	var csv := FileAccess.open(csv_path, FileAccess.WRITE)
	if csv == null:
		_fail("CSV open")
		return
	csv.store_csv_line(["tick", "revision", "foam_sum", "coverage_05", "coverage_20",
		"coverage_50", "dry_foam", "strong_centroid_x_cell",
		"screen_bright_neutral_px_estimate", "wall_elapsed_s"])
	var samples: Array[Dictionary] = []
	var screenshots: Array[String] = []
	var start_us := Time.get_ticks_usec()
	for sample_tick in range(interval_ticks, target_tick + 1, interval_ticks):
		var steps := 0
		while preview.completed_ticks < sample_tick and preview.last_error.is_empty() and steps < interval_ticks * 600:
			if not preview.tick_pending and not preview.checkpoint_capture_pending:
				preview._start_tick()
			await process_frame
			steps += 1
		if preview.completed_ticks != sample_tick or preview.tick_pending or not preview.last_error.is_empty():
			csv.close()
			_fail("exact sample tick %d failed; got %d %s" % [sample_tick, preview.completed_ticks, preview.last_error])
			return
		preview.set_visual_time(float(sample_tick) / 30.0)
		readbacks.clear()
		RenderingServer.call_on_render_thread(_request_readback.bind(preview))
		var wait_frames := 0
		while readbacks.size() < 2 and wait_frames < 600:
			await process_frame
			wait_frames += 1
		if readbacks.size() != 2 or readbacks["foam"].size() != GRID_SIZE * GRID_SIZE * 8 or \
				readbacks["water"].size() != GRID_SIZE * GRID_SIZE * 4:
			csv.close()
			_fail("readback missing or wrong byte count at tick %d" % sample_tick)
			return
		var values: PackedFloat32Array = readbacks["foam"].to_float32_array()
		var water: PackedFloat32Array = readbacks["water"].to_float32_array()
		var sum_foam := 0.0
		var coverage_05 := 0
		var coverage_20 := 0
		var coverage_50 := 0
		var dry_foam := 0
		var strong_weight := 0.0
		var strong_x_weight := 0.0
		var save_snapshot: bool = sample_tick in SNAPSHOT_TICKS
		var foam_image := Image.create(GRID_SIZE, GRID_SIZE, false, Image.FORMAT_RGBA8) if save_snapshot else null
		for cell in GRID_SIZE * GRID_SIZE:
			var foam: float = values[cell * 2]
			if not is_finite(foam) or foam < 0.0:
				csv.close()
				_fail("invalid foam field at tick %d" % sample_tick)
				return
			sum_foam += foam
			if foam > 0.05:
				coverage_05 += 1
			if foam > 0.20:
				coverage_20 += 1
				strong_weight += foam
				strong_x_weight += foam * float(cell % GRID_SIZE)
			if foam > 0.50:
				coverage_50 += 1
			if water[cell] <= 0.0015 and foam > 0.001:
				dry_foam += 1
			if save_snapshot:
				foam_image.set_pixel(cell % GRID_SIZE, cell / GRID_SIZE,
					Color(foam, foam, foam, 1.0))
		var centroid := strong_x_weight / strong_weight if strong_weight > 0.0 else -1.0
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var screen_image := root.get_texture().get_image()
		if screen_image.get_size() != Vector2i(1920, 1080):
			csv.close()
			_fail("screen readback size at tick %d" % sample_tick)
			return
		screen_image.convert(Image.FORMAT_RGBA8)
		var screen_pixels := screen_image.get_data()
		var bright_samples := 0
		for py in range(280, 1080, 2):
			for px in range(950, 1600, 2):
				var pixel_index := (py * 1920 + px) * 4
				var red: int = screen_pixels[pixel_index]
				var green: int = screen_pixels[pixel_index + 1]
				var blue: int = screen_pixels[pixel_index + 2]
				if mini(red, mini(green, blue)) >= 205 and \
						maxi(red, maxi(green, blue)) - mini(red, mini(green, blue)) <= 45:
					bright_samples += 1
		var screen_bright_estimate := bright_samples * 4
		var elapsed_s := float(Time.get_ticks_usec() - start_us) / 1000000.0
		csv.store_csv_line([str(sample_tick), str(preview.solver.state_revision),
			"%.6f" % sum_foam, str(coverage_05), str(coverage_20),
			str(coverage_50), str(dry_foam), "%.6f" % centroid,
			str(screen_bright_estimate),
			"%.6f" % elapsed_s])
		samples.append({"tick": sample_tick, "foam_sum": sum_foam,
			"coverage_05": coverage_05, "coverage_20": coverage_20,
			"coverage_50": coverage_50, "dry_foam": dry_foam,
			"strong_centroid_x_cell": centroid,
			"screen_bright_neutral_px_estimate": screen_bright_estimate})
		if save_snapshot:
			var field_path := output_dir.path_join("%s_%s_tick%d_field.png" % [run_id, case_id, sample_tick])
			if foam_image.save_png(field_path) != OK:
				csv.close()
				_fail("field PNG write")
				return
			screenshots.append(field_path)
			var screen_path := output_dir.path_join("%s_%s_tick%d_screen.png" % [run_id, case_id, sample_tick])
			if screen_image.save_png(screen_path) != OK:
				csv.close()
				_fail("screen PNG write")
				return
			screenshots.append(screen_path)
		if sample_tick % 300 == 0:
			print("FOAM_PROGRESS case=%s load=%s tick=%d coverage20=%d" % [case_id, wave_load, sample_tick, coverage_20])
	csv.close()
	var manifest := {"role": "w07_foam_activity_timeline", "run_id": run_id,
		"case": case_id, "wave_load": wave_load, "fixture_id": String(preview.fixture_id),
		"target_tick": target_tick, "interval_ticks": interval_ticks,
		"screen_bright_neutral_proxy": {"roi_px": [950, 280, 1600, 1080],
			"stride_px": 2, "min_rgb": 205, "max_channel_spread": 45,
			"pixel_estimate_scale": 4},
		"viewport_px": [root.size.x, root.size.y],
		"adapter": RenderingServer.get_video_adapter_name(),
		"rendering_driver": "d3d12", "sim_hz": 30,
		"initial_state_hashes": initial_hashes, "wave_requests": requests,
		"candidate": {"phase2_optics": true, "phase2_foam": true,
			"prototype_eta_normals": true, "prototype_crest_height_m": 0.16,
			"prototype_irregular_foam": true, "prototype_screen_optics": false},
		"camera": str(root.get_camera_3d().global_transform),
		"camera_fov_deg": root.get_camera_3d().fov,
		"samples": samples, "csv": csv_path, "screenshots": screenshots,
		"nan_events": preview.solver.nan_events,
		"overload_events": preview.solver.overload_events,
		"wave_clamp_events": preview.wave_clamp_events}
	var manifest_path := output_dir.path_join("%s_%s_manifest.json" % [run_id, case_id])
	var file := FileAccess.open(manifest_path, FileAccess.WRITE)
	if file == null:
		_fail("manifest open")
		return
	file.store_string(JSON.stringify(manifest, "\t"))
	file.close()
	print("PASS: W07 foam timeline %s %s samples=%d" % [case_id, wave_load, samples.size()])
	quit(0)


func _request_readback(scene: Node3D) -> void:
	if scene.foam_field.request_data(_on_readback.bind("foam")) != OK:
		call_deferred("_receive_readback", PackedByteArray(), "foam")
	if scene.solver.request_data("water", _on_readback.bind("water")) != OK:
		call_deferred("_receive_readback", PackedByteArray(), "water")


func _on_readback(data: PackedByteArray, field: String) -> void:
	call_deferred("_receive_readback", data, field)


func _receive_readback(data: PackedByteArray, field: String) -> void:
	readbacks[field] = data


func _fail(message: String) -> void:
	printerr("FAIL: W07 foam timeline " + message)
	quit(1)

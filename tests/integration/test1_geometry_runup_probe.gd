extends "res://tests/integration/test1_geometry_probe.gd"

var samples := []
var end_seconds := 40.0

func key_event(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)

func camera_checks() -> void:
	var camera: Camera3D = preview.player_camera
	var original := camera.transform
	root.gui_release_focus()
	for code in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_Q, KEY_E]:
		camera.transform = original
		key_event(code, true)
		await process_frame
		await process_frame
		key_event(code, false)
		check("camera_key_" + OS.get_keycode_string(code), camera.position.distance_to(original.origin) > 0.001)
		await process_frame
	camera.transform = original
	var input: SpinBox = preview.brush_panel.get_node("%DigAmount")
	input.get_line_edit().grab_focus()
	key_event(KEY_W, true)
	await process_frame
	await process_frame
	key_event(KEY_W, false)
	check("numeric_focus_still_blocks_movement", camera.transform == original)
	root.gui_release_focus()
	key_event(KEY_F5, true)
	await process_frame
	key_event(KEY_F5, false)
	check("f5_fixed_view", not preview.use_player_camera and preview.overview_camera.current)
	key_event(KEY_F5, true)
	await process_frame
	key_event(KEY_F5, false)
	check("f5_restores_free_view", preview.use_player_camera and camera.current)
	preview.hide_hud = true
	preview._update_status()
	await process_frame
	var button := InputEventMouseButton.new()
	button.position = Vector2(640, 400)
	button.button_index = MOUSE_BUTTON_RIGHT
	button.pressed = true
	Input.parse_input_event(button.duplicate())
	await process_frame
	check("right_mouse_captures_camera", camera.look_active)
	var rotation_before := camera.rotation
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(640, 400)
	motion.relative = Vector2(25, -12)
	motion.screen_relative = motion.relative
	Input.parse_input_event(motion)
	await process_frame
	check("mouse_motion_rotates_camera", camera.rotation.distance_to(rotation_before) > 0.001)
	button.pressed = false
	Input.parse_input_event(button.duplicate())
	await process_frame
	check("right_mouse_release_unlocks", not camera.look_active and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE)
	camera.transform = original
	preview.hide_hud = false
	preview._update_status()

func measure(cp: Dictionary) -> Dictionary:
	var bed: PackedFloat32Array = cp.native.fields.sand.to_float32_array()
	var h: PackedFloat32Array = cp.native.fields.water.to_float32_array()
	var qx: PackedFloat32Array = cp.native.fields.momentum_x.to_float32_array()
	var shore_amount := 0.0
	var shore_flow := 0.0
	var dry := 0
	var upper_dry := 0
	var upper := 0
	var wet_shore := 0
	var shore_count := 0
	var sea_eta_error := 0.0
	for z in range(68, 188):
		for x in range(8, 248):
			var i := z * 256 + x
			if h[i] < 0.005: dry += 1
			if bed[i] > 1.65:
				upper += 1
				if h[i] < 0.005: upper_dry += 1
			if bed[i] > 1.0 and bed[i] < 1.5:
				shore_count += 1
				shore_amount += h[i] * 0.015625
				if h[i] > 0.005:
					wet_shore += 1
					shore_flow += qx[i]
			if x < 32 and h[i] > 0.005:
				sea_eta_error = maxf(sea_eta_error, absf(bed[i] + h[i] - 0.95))
	var row := {"seconds":cp.advanced_time_s, "tick":cp.sim_tick, "boundary_level":cp.native.control.decode_float(96),
		"shore_water_m3":shore_amount, "wet_shore_cells":wet_shore, "shore_cells":shore_count,
		"mean_shore_qx":shore_flow/maxi(wet_shore, 1), "dry_fraction":float(dry)/28800.0,
		"upper_dry_fraction":float(upper_dry)/maxi(upper, 1), "sea_eta_error_from_rest":sea_eta_error}
	return row

func record(label: String) -> void:
	var cp := await capture(label)
	if cp.is_empty(): return
	var row := measure(cp)
	var validation: StringName = preview.AsyncCheckpoint.validate(cp, preview.source_signature)
	row["checkpoint_validation"] = String(validation)
	samples.append(row)
	print("RUNUP_SAMPLE ", JSON.stringify(row))
	var file := FileAccess.open(output.get_base_dir().path_join("samples.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(samples, "\t"))
	if int(roundf(float(row.seconds))) % 4 == 0: await screenshot("cycle_%02d" % int(roundf(float(row.seconds))))

func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--cycle-seconds="): end_seconds = maxf(arg.trim_prefix("--cycle-seconds=").to_float(), 20.0)
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	root.size = Vector2i(1280, 720)
	service = root.get_node("BeachScenes")
	preview = load("res://scenes/main.tscn").instantiate()
	preview.playing = false
	root.add_child(preview)
	current_scene = preview
	if not await wait_ready(): await finish(); return
	preview.get_node("Interface/PerformancePanel/Margin/Rows/Header/Sampling").button_pressed = false
	if not await switch_to("test1_geometry"): await finish(); return
	check("default_free_camera", preview.use_player_camera and preview.player_camera.current)
	await camera_checks()
	await record("rest_initial")
	check("calm_initial_sea", samples[0].sea_eta_error_from_rest < 0.00001)
	check("initial_beach_exposed", samples[0].dry_fraction > 0.50 and samples[0].shore_water_m3 == 0)
	var next_sample := 2.0
	while next_sample <= end_seconds and preview.last_error.is_empty():
		preview.playing = true
		var deadline := Time.get_ticks_msec() + 120000
		while preview.async_controller.actual_time < next_sample and preview.last_error.is_empty() and Time.get_ticks_msec() < deadline: await process_frame
		preview.playing = false
		check("sample_time_%02d" % int(next_sample), preview.async_controller.actual_time >= next_sample and preview.last_error.is_empty())
		check("sample_idle_%02d" % int(next_sample), await idle())
		await record("cycle_%02d" % int(next_sample))
		if failed: break
		next_sample += 2.0
	if samples.size() > 5:
		var peak := 0.0
		var peak_time := 0.0
		var retreat := INF
		var retreat_time := 0.0
		var negative_flow := false
		var upper_stays_dry := true
		var bounded_target := true
		var max_shore_cells := 0
		for row in samples:
			if row.seconds < 20.0 and row.shore_water_m3 > peak:
				peak = row.shore_water_m3; peak_time = row.seconds
			if row.seconds >= 12.0 and row.seconds < 20.0 and row.shore_water_m3 < retreat:
				retreat = row.shore_water_m3; retreat_time = row.seconds
			if row.mean_shore_qx < -0.00001: negative_flow = true
			if row.upper_dry_fraction < 0.90 or row.dry_fraction < 0.20: upper_stays_dry = false
			# At tick zero the boundary kernel has not run; control[24] is unset.
			if row.tick > 0 and (row.boundary_level < 0.9499 or row.boundary_level > 1.4001): bounded_target = false
			max_shore_cells = maxi(max_shore_cells, row.wet_shore_cells)
		check("real_water_runs_onto_initially_dry_beach", peak > 0.5 and max_shore_cells > 100)
		check("real_flow_reverses_toward_sea", negative_flow)
		check("real_shore_water_recedes", retreat < peak * 0.65 and retreat_time > peak_time)
		check("beach_not_entirely_submerged", upper_stays_dry)
		check("boundary_level_within_profile", bounded_target)
		evidence.runup = {"peak_m3":peak, "peak_time":peak_time, "retreat_m3":retreat, "retreat_time":retreat_time, "samples":samples}
	var before := await capture("pause_before")
	for frame in 10: await process_frame
	var paused := await capture("pause_after")
	check("paused_wave_clock_and_water_frozen", before.advanced_time_s == paused.advanced_time_s and before.native.fields.water == paused.native.fields.water)
	var saved_camera: Transform3D = preview.player_camera.transform
	if await switch_to("main"):
		if await switch_to("test1_geometry"):
			check("return_free_camera_operable", preview.use_player_camera and preview.player_camera.current and preview.player_camera.transform == saved_camera)
			var returned := await capture("cycle_returned")
			check("return_preserves_cycle_phase", returned.advanced_time_s == paused.advanced_time_s and returned.native.fields.water == paused.native.fields.water)
	evidence.samples = samples
	await finish()

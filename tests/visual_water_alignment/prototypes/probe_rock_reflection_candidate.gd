extends SceneTree

const FIXED := preload("res://scenes/water_render_demo_rock_reflection_candidate.tscn")
const COUPLED := preload("res://scenes/water_render_coupled_rock_reflection_candidate.tscn")
const PROFILE := "res://tests/visual_water_alignment/prototypes/water_render_staging_v7.json"
const FIELDS := ["rock", "sand", "water"]

var output_dir := ""
var run_id := ""
var target_tick := 30
var received := {}


func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			output_dir = arg.trim_prefix("--output=")
		elif arg.begins_with("--run-id="):
			run_id = arg.trim_prefix("--run-id=")
		elif arg.begins_with("--tick="):
			target_tick = int(arg.trim_prefix("--tick="))
	call_deferred("_run")


func _run() -> void:
	if output_dir.is_empty() or run_id.is_empty() or target_tick < 1 or \
			not DirAccess.dir_exists_absolute(output_dir) or \
			root.size != Vector2i(1920, 1080) or \
			DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED:
		_fail("output/run-id or viewport invalid")
		return
	var cases := {}
	for item in [{"name": "fixed", "scene": FIXED},
			{"name": "coupled", "scene": COUPLED}]:
		var preview: Node3D = item.scene.instantiate()
		root.add_child(preview)
		var frames := 0
		while not preview.ready_for_ticks and preview.last_error.is_empty() and \
				frames < 1800:
			await process_frame
			frames += 1
		if not preview.ready_for_ticks or not preview.last_error.is_empty():
			_fail(item.name + " initialization: " + preview.last_error)
			return
		if preview.render_profile_path != PROFILE or \
				preview.staging_wave_workload != "continuous_packets_v1" or \
				preview.requested_render_profile_sha256 != FileAccess.get_sha256(PROFILE) or \
				preview.wave_requests.size() != 80 or \
				preview.effective_render_profile.get("reference_bed") != \
				"estuary_branched_v1" or \
				preview.effective_render_profile.get("shallow_preserve") != true or \
				preview.water_material.get_shader_parameter(
					"prototype_optical_shallow_preserve") != true or \
				not is_equal_approx(float(preview.effective_render_profile.get(
					"caustic_softness", -1.0)), 1.0) or \
				not is_equal_approx(float(preview.effective_render_profile.get(
					"caustic_strength", -1.0)), 0.5) or \
				not is_equal_approx(float(preview.effective_render_profile.get(
					"caustic_uv_scale", -1.0)), 1.1) or \
				preview.water_material.get_shader_parameter(
					"prototype_planar_reflection_enabled") != true or \
				(preview.get_node("ReflectionViewport") as SubViewport).size != \
					Vector2i(960, 540) or \
				preview.get_node_or_null("ReflectionRockEnvironment") == null:
			_fail(item.name + " profile/material/workload mismatch")
			return
		frames = 0
		while preview.completed_ticks < target_tick and preview.last_error.is_empty() and \
				frames < max(3600, target_tick * 60):
			await process_frame
			frames += 1
		preview.playing = false
		while preview.tick_pending and frames < 3900:
			await process_frame
			frames += 1
		if preview.completed_ticks != target_tick or not preview.last_error.is_empty() or \
				not is_equal_approx(preview.visual_time_s,
				float(target_tick) / 30.0):
			_fail(item.name + " tick/time: " + preview.last_error)
			return
		var state: Dictionary = await _read_state(preview)
		if state.size() != FIELDS.size():
			_fail(item.name + " GPU readback")
			return
		var field_sha := {}
		for field in FIELDS:
			var field_path := output_dir.path_join("%s_%s_%s.bin" % [
				run_id, item.name, field])
			var field_file := FileAccess.open(field_path, FileAccess.WRITE)
			if field_file == null or state[field].size() != 256 * 256 * 4:
				_fail(item.name + " field write: " + field)
				return
			field_file.store_buffer(state[field])
			field_file.close()
			field_sha[field] = FileAccess.get_sha256(field_path)
		var images := {}
		for camera_id in [&"oblique", &"close", &"grazing"]:
			if not preview.set_fixture_camera(camera_id):
				_fail(item.name + " " + String(camera_id) + " camera")
				return
			for settle in 4:
				await RenderingServer.frame_post_draw
			var png_path := output_dir.path_join("%s_%s_%s.png" % [
				run_id, item.name, String(camera_id)])
			if root.get_texture().get_image().save_png(png_path) != OK:
				_fail(item.name + " PNG write")
				return
			images[String(camera_id)] = {
				"path": png_path, "sha256": FileAccess.get_sha256(png_path)}
		cases[item.name] = {
			"fixture_id": String(preview.fixture_id),
			"profile_sha256": preview.requested_render_profile_sha256,
			"effective_profile_sha256": preview.effective_render_profile_sha256,
			"initial_state_hashes": {
				"rock": hash(preview.shadow_domain.rock),
				"sand": hash(preview.shadow_domain.sand),
				"water": hash(preview.shadow_domain.water),
			},
			"wave_requests": preview.wave_requests.size(),
			"reflection_enabled": preview.water_material.get_shader_parameter(
				"prototype_planar_reflection_enabled"),
			"reflection_environment": "reflection_rock_environment.tscn",
			"reflection_viewport_px": [960, 540],
			"field_sha256": field_sha,
			"tick": preview.completed_ticks,
			"visual_time_s": preview.visual_time_s,
			"images": images,
		}
		preview.queue_free()
		for settle in 12:
			await process_frame
	var file := FileAccess.open(output_dir.path_join(run_id + "_manifest.json"),
		FileAccess.WRITE)
	if file == null:
		_fail("manifest write")
		return
	file.store_string(JSON.stringify({"run_id": run_id, "cases": cases,
		"viewport_px": [root.size.x, root.size.y]}, "\t"))
	file.close()
	print("PASS: W10 rock reflection candidate fixed/coupled tick%d" % target_tick)
	quit(0)


func _read_state(scene: Node3D) -> Dictionary:
	received.clear()
	RenderingServer.call_on_render_thread(_read.bind(scene))
	for frame in 1800:
		if received.size() == FIELDS.size():
			return received.duplicate(true)
		await process_frame
	return {}


func _read(scene: Node3D) -> void:
	var rd := RenderingServer.get_rendering_device()
	var data := {}
	for field in FIELDS:
		data[field] = rd.texture_get_data(scene.solver.current_texture(field), 0)
	call_deferred("_receive", data)


func _receive(data: Dictionary) -> void:
	received.merge(data)


func _fail(message: String) -> void:
	push_error("FAIL: W08 v7 preview " + message)
	quit(1)

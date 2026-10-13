extends SceneTree

const FIXED := preload("res://scenes/water_render_demo_v5_preview.tscn")
const COUPLED := preload("res://scenes/water_render_coupled_v5_preview.tscn")
const PROFILE := "res://tests/visual_water_alignment/prototypes/water_render_staging_v5.json"
const CAMERAS := [&"oblique", &"close", &"grazing"]
const FIELDS := ["rock", "sand", "water"]

var output_dir := ""
var run_id := ""
var case_id := "coupled"
var target_tick := 240
var received := {}


func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			output_dir = arg.trim_prefix("--output=")
		elif arg.begins_with("--run-id="):
			run_id = arg.trim_prefix("--run-id=")
		elif arg.begins_with("--case="):
			case_id = arg.trim_prefix("--case=")
		elif arg.begins_with("--tick="):
			target_tick = int(arg.trim_prefix("--tick="))
	call_deferred("_run")


func _run() -> void:
	if case_id not in ["fixed", "coupled"] or output_dir.is_empty() or \
			run_id.is_empty() or target_tick < 1 or \
			not DirAccess.dir_exists_absolute(output_dir) or \
			root.size != Vector2i(1920, 1080) or \
			DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED:
		_fail("invalid arguments or viewport")
		return
	var packed: PackedScene = FIXED if case_id == "fixed" else COUPLED
	var preview: Node3D = packed.instantiate()
	root.add_child(preview)
	var frames := 0
	while not preview.ready_for_ticks and preview.last_error.is_empty() and frames < 1800:
		await process_frame
		frames += 1
	if not preview.ready_for_ticks or not preview.last_error.is_empty():
		_fail("initialization: " + preview.last_error)
		return
	if preview.render_profile_path != PROFILE or \
			preview.requested_render_profile_sha256 != FileAccess.get_sha256(PROFILE) or \
			preview.wave_requests.size() != 80 or \
			preview.effective_render_profile.get("reference_bed") != \
			"estuary_branched_v1" or \
			preview.effective_render_profile.get("shallow_preserve") != true or \
			preview.water_material.get_shader_parameter(
				"prototype_screen_sky_gradient") == true:
		_fail("profile, workload or baseline material mismatch: " +
			str([preview.render_profile_path,
				preview.requested_render_profile_sha256,
				preview.wave_requests.size(),
				preview.effective_render_profile.get("reference_bed"),
				preview.effective_render_profile.get("shallow_preserve"),
				preview.water_material.get_shader_parameter(
					"prototype_screen_sky_gradient")]))
		return
	frames = 0
	while preview.completed_ticks < target_tick and preview.last_error.is_empty() and \
			frames < max(3600, target_tick * 60):
		await process_frame
		frames += 1
	preview.playing = false
	while preview.tick_pending and frames < max(3900, target_tick * 60):
		await process_frame
		frames += 1
	if preview.completed_ticks != target_tick or not preview.last_error.is_empty():
		_fail("tick/time: " + preview.last_error)
		return
	var before: Dictionary = await _read_state(preview)
	if before.size() != FIELDS.size():
		_fail("GPU readback before")
		return
	var images := {}
	for camera in CAMERAS:
		if not preview.set_fixture_camera(camera):
			_fail("camera " + String(camera))
			return
		for variant in ["baseline", "sky_gradient"]:
			preview.water_material.set_shader_parameter(
				"prototype_screen_sky_gradient", variant == "sky_gradient")
			for settle in 4:
				await RenderingServer.frame_post_draw
			var path := output_dir.path_join("%s_%s_%s_%s.png" % [
				run_id, case_id, String(camera), variant])
			if root.get_texture().get_image().save_png(path) != OK:
				_fail("PNG write " + path)
				return
			images["%s_%s" % [String(camera), variant]] = {
				"path": path, "sha256": FileAccess.get_sha256(path)}
	preview.water_material.set_shader_parameter("prototype_screen_sky_gradient", false)
	var after: Dictionary = await _read_state(preview)
	if after.size() != FIELDS.size():
		_fail("GPU readback after")
		return
	var state_sha := {}
	for field in FIELDS:
		if before[field] != after[field]:
			_fail("physical field changed: " + field)
			return
		var digest := HashingContext.new()
		digest.start(HashingContext.HASH_SHA256)
		digest.update(before[field])
		state_sha[field] = digest.finish().hex_encode()
	var manifest := {
		"run_id": run_id, "case": case_id, "tick": preview.completed_ticks,
		"visual_time_s": preview.visual_time_s,
		"viewport_px": [root.size.x, root.size.y],
		"rendering_driver": RenderingServer.get_current_rendering_driver_name(),
		"profile_path": PROFILE,
		"profile_sha256": preview.requested_render_profile_sha256,
		"effective_profile_sha256": preview.effective_render_profile_sha256,
		"wave_requests": preview.wave_requests.size(),
		"water_shader": preview.water_material.shader.resource_path,
		"state_sha256": state_sha, "images": images}
	var manifest_file := FileAccess.open(
		output_dir.path_join(run_id + "_" + case_id + "_manifest.json"), FileAccess.WRITE)
	if manifest_file == null:
		_fail("manifest write")
		return
	manifest_file.store_string(JSON.stringify(manifest, "\t"))
	manifest_file.close()
	print("PASS: W10 v5 sky gradient %s tick%d" % [case_id, target_tick])
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
	push_error("FAIL: W10 v5 sky gradient " + message)
	quit(1)

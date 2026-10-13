extends SceneTree

const WATER_SCENE := preload("res://scenes/water_render_demo.tscn")
const COUPLED_SCENE := preload("res://scenes/water_render_coupled.tscn")
const CAMERAS := [&"oblique", &"close", &"grazing"]
const FIELDS := ["water", "sand", "wetness", "momentum_x",
	"momentum_z", "foam_history", "local_front_history"]

var output_dir := ""
var run_id := ""
var received := {}


func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			output_dir = arg.trim_prefix("--output=")
		elif arg.begins_with("--run-id="):
			run_id = arg.trim_prefix("--run-id=")
	call_deferred("_run")


func _run() -> void:
	if output_dir.is_empty() or run_id.is_empty() or \
			not DirAccess.dir_exists_absolute(output_dir) or \
			root.size != Vector2i(1920, 1080) or \
			DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED:
		_fail("output/run-id or 1080p VSync-off invalid")
		return
	var cases := {}
	for case in [{"name": "fixed", "scene": WATER_SCENE},
			{"name": "coupled", "scene": COUPLED_SCENE}]:
		var preview: Node3D = case.scene.instantiate()
		root.add_child(preview)
		if not await _wait_ready(preview):
			_fail(case.name + " initialization: " + preview.last_error)
			return
		var initial_hashes := {"rock": hash(preview.shadow_domain.rock),
			"sand": hash(preview.shadow_domain.sand),
			"water": hash(preview.shadow_domain.water)}
		if preview.wave_requests.size() != 1 or \
				preview.wave_requests[0].start_tick != 8 or \
				preview.wave_requests[0].seed != 31:
			_fail(case.name + " shared wave workload")
			return
		var wave: Dictionary = preview.wave_requests[0].duplicate(true)
		for frame in 18000:
			if preview.completed_ticks >= 240 or not preview.last_error.is_empty():
				break
			await process_frame
		preview.playing = false
		while preview.tick_pending:
			await process_frame
		if preview.completed_ticks != 240 or not preview.last_error.is_empty() or \
				not is_equal_approx(preview.visual_time_s, 8.0):
			_fail(case.name + " tick/time: " + preview.last_error)
			return
		var before: Dictionary = await _read_state(preview)
		if before.size() != FIELDS.size():
			_fail(case.name + " initial GPU readback")
			return
		var terrain: ShaderMaterial = preview.terrain_material
		var water: ShaderMaterial = preview.water_material
		var wetness_texture: Texture2D = terrain.get_shader_parameter("wetness_state")
		if wetness_texture == null or \
				water.get_shader_parameter("prototype_use_local_front") != true:
			_fail(case.name + " expected baseline bindings")
			return
		var zero_image := Image.create(256, 256, false, Image.FORMAT_RF)
		zero_image.fill(Color(0.0, 0.0, 0.0, 1.0))
		var zero_wetness := ImageTexture.create_from_image(zero_image)
		var images := {}
		for camera_id in CAMERAS:
			if not preview.set_fixture_camera(camera_id):
				_fail(case.name + " camera " + String(camera_id))
				return
			images[String(camera_id)] = {}
			for variant in ["baseline", "dry_wetness", "no_local_front"]:
				terrain.set_shader_parameter("wetness_state",
					zero_wetness if variant == "dry_wetness" else wetness_texture)
				water.set_shader_parameter("prototype_use_local_front",
					variant != "no_local_front")
				for settle in 10:
					await RenderingServer.frame_post_draw
				var path := output_dir.path_join("%s_%s_%s_%s.png" % [
					run_id, case.name, String(camera_id), variant])
				if root.get_texture().get_image().save_png(path) != OK:
					_fail(case.name + " image write " + path)
					return
				images[String(camera_id)][variant] = path
		terrain.set_shader_parameter("wetness_state", wetness_texture)
		water.set_shader_parameter("prototype_use_local_front", true)
		var after: Dictionary = await _read_state(preview)
		var equal_fields := {}
		for field in FIELDS:
			equal_fields[field] = before.has(field) and after.has(field) and \
				before[field].size() > 0 and before[field] == after[field]
			if not equal_fields[field]:
				_fail(case.name + " display changed GPU field " + field)
				return
		cases[case.name] = {"fixture_id": String(preview.fixture_id),
			"tick": preview.completed_ticks, "revision": preview.solver.state_revision,
			"visual_time_s": preview.visual_time_s,
			"requested_profile_sha256": preview.requested_render_profile_sha256,
			"effective_profile_sha256": preview.effective_render_profile_sha256,
			"water_shader": water.shader.resource_path,
			"terrain_shader": terrain.shader.resource_path,
			"initial_state_hashes": initial_hashes,
			"gpu_fields_unchanged": equal_fields, "images": images,
			"wave_request": wave}
		preview.queue_free()
		for cleanup in 4:
			await process_frame
	var path := output_dir.path_join(run_id + "_manifest.json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_fail("manifest open")
		return
	file.store_string(JSON.stringify({"run_id": run_id, "cases": cases,
		"viewport_px": [root.size.x, root.size.y],
		"adapter": RenderingServer.get_video_adapter_name()}, "\t"))
	file.close()
	print("PASS: W08 staging wetness/local-front A/B fixed/coupled")
	quit(0)


func _wait_ready(scene: Node3D) -> bool:
	for frame in 1800:
		if scene.ready_for_ticks:
			return true
		if not scene.last_error.is_empty():
			return false
		await process_frame
	return false


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
		var texture: RID = scene.foam_field.current_texture() if field == \
			"foam_history" else (scene.local_front_field.texture if field == \
			"local_front_history" else scene.solver.current_texture(field))
		data[field] = rd.texture_get_data(texture, 0)
	call_deferred("_receive", data)


func _receive(data: Dictionary) -> void:
	received.merge(data)


func _fail(message: String) -> void:
	push_error("FAIL: W08 staging consumption " + message)
	quit(1)

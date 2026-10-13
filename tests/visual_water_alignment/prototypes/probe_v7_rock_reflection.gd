extends SceneTree

const SCENE := preload("res://scenes/water_render_coupled_v7_preview.tscn")
const ROCKS := preload("res://tests/visual_water_alignment/prototypes/reflection_rock_environment.tscn")
const PROFILE := "res://tests/visual_water_alignment/prototypes/water_render_staging_v7.json"
const CAMERAS := [&"oblique", &"close", &"grazing"]
const FIELDS := ["rock", "sand", "water"]

var output_dir := ""
var run_id := ""
var target_tick := 240
var preview: Node3D
var reflection_viewport: SubViewport
var reflection_camera: Camera3D
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
	if (output_dir.is_empty() or run_id.is_empty() or target_tick < 1 or
			not DirAccess.dir_exists_absolute(output_dir) or
			root.size != Vector2i(1920, 1080) or
			DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED):
		_fail("arguments or 1080p/VSync-off viewport")
		return
	preview = SCENE.instantiate()
	root.add_child(preview)
	var frames := 0
	while not preview.ready_for_ticks and preview.last_error.is_empty() and frames < 1800:
		await process_frame
		frames += 1
	if (not preview.ready_for_ticks or not preview.last_error.is_empty() or
			preview.render_profile_path != PROFILE or
			preview.requested_render_profile_sha256 != FileAccess.get_sha256(PROFILE) or
			preview.wave_requests.size() != 80):
		_fail("initialization/profile/workload: " + preview.last_error)
		return
	frames = 0
	while preview.completed_ticks < target_tick and preview.last_error.is_empty() and frames < 36000:
		await process_frame
		frames += 1
	preview.playing = false
	while preview.tick_pending and frames < 37000:
		await process_frame
		frames += 1
	if preview.completed_ticks != target_tick or not preview.last_error.is_empty():
		_fail("tick/time: " + preview.last_error)
		return
	var before: Dictionary = await _read_state()
	if before.size() != FIELDS.size():
		_fail("GPU readback before")
		return
	var rocks: Node3D = ROCKS.instantiate()
	root.add_child(rocks)
	reflection_viewport = SubViewport.new()
	reflection_viewport.size = Vector2i(960, 540)
	reflection_viewport.world_3d = root.world_3d
	reflection_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(reflection_viewport)
	reflection_camera = Camera3D.new()
	reflection_camera.cull_mask = 4
	reflection_viewport.add_child(reflection_camera)
	reflection_camera.make_current()
	(preview.get_node("GpuWaterSurface") as MeshInstance3D).layers = 2
	preview.overview_camera.set_cull_mask_value(3, false)
	preview.player_camera.set_cull_mask_value(3, false)
	var water: ShaderMaterial = preview.water_material
	water.set_shader_parameter("prototype_planar_reflection", reflection_viewport.get_texture())
	water.set_shader_parameter("prototype_planar_reflection_projected", true)
	var image_entries := {}
	for camera_id in CAMERAS:
		if not preview.set_fixture_camera(camera_id):
			_fail("fixture camera " + String(camera_id))
			return
		_update_reflection_camera(root.get_camera_3d(), water)
		for variant in ["baseline", "projected"]:
			water.set_shader_parameter("prototype_planar_reflection_enabled", variant == "projected")
			for settle in 5:
				await RenderingServer.frame_post_draw
			var path := output_dir.path_join("%s_%s_%s.png" % [run_id, String(camera_id), variant])
			if root.get_texture().get_image().save_png(path) != OK:
				_fail("PNG write " + path)
				return
			image_entries["%s_%s" % [String(camera_id), variant]] = {
				"path": path, "sha256": FileAccess.get_sha256(path)}
		var reflected_path := output_dir.path_join("%s_%s_source.png" % [run_id, String(camera_id)])
		if reflection_viewport.get_texture().get_image().save_png(reflected_path) != OK:
			_fail("source PNG write " + reflected_path)
			return
		image_entries["%s_source" % String(camera_id)] = {
			"path": reflected_path, "sha256": FileAccess.get_sha256(reflected_path)}
	water.set_shader_parameter("prototype_planar_reflection_enabled", false)
	var after: Dictionary = await _read_state()
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
		"role": "w10_v7_rock_environment_reflection_probe",
		"run_id": run_id,
		"tick": preview.completed_ticks,
		"revision": preview.solver.state_revision,
		"visual_time_s": preview.visual_time_s,
		"viewport_px": [root.size.x, root.size.y],
		"reflection_viewport_px": [reflection_viewport.size.x, reflection_viewport.size.y],
		"rendering_driver": RenderingServer.get_current_rendering_driver_name(),
		"adapter": RenderingServer.get_video_adapter_name(),
		"profile_path": PROFILE,
		"profile_sha256": preview.requested_render_profile_sha256,
		"effective_profile_sha256": preview.effective_render_profile_sha256,
		"environment_scene": ROCKS.resource_path,
		"wave_requests": preview.wave_requests.size(),
		"state_sha256": state_sha,
		"images": image_entries,
		"nan_events": preview.solver.nan_events,
		"overload_events": preview.solver.overload_events,
	}
	var file := FileAccess.open(output_dir.path_join(run_id + "_manifest.json"), FileAccess.WRITE)
	if file == null:
		_fail("manifest write")
		return
	file.store_string(JSON.stringify(manifest, "\t"))
	file.close()
	print("PASS: W10 v7 rock reflection tick%d" % target_tick)
	quit(0)


func _update_reflection_camera(source_camera: Camera3D, water: ShaderMaterial) -> void:
	reflection_camera.fov = source_camera.fov
	reflection_camera.near = source_camera.near
	reflection_camera.far = source_camera.far
	var source_basis := source_camera.global_transform.basis
	var reflected_position := source_camera.global_position
	reflected_position.y = -reflected_position.y
	var reflected_forward := -source_basis.z
	reflected_forward.y = -reflected_forward.y
	var reflected_up := source_basis.y
	reflected_up.y = -reflected_up.y
	reflection_camera.global_position = reflected_position
	reflection_camera.look_at(reflected_position + reflected_forward, reflected_up)
	var view_projection := reflection_camera.get_camera_projection() * Projection(
		reflection_camera.global_transform.affine_inverse())
	water.set_shader_parameter("prototype_planar_view_projection", view_projection)


func _read_state() -> Dictionary:
	received.clear()
	RenderingServer.call_on_render_thread(_read)
	for frame in 1800:
		if received.size() == FIELDS.size():
			return received.duplicate(true)
		await process_frame
	return {}


func _read() -> void:
	var rd := RenderingServer.get_rendering_device()
	var data := {}
	for field in FIELDS:
		data[field] = rd.texture_get_data(preview.solver.current_texture(field), 0)
	call_deferred("_receive", data)


func _receive(data: Dictionary) -> void:
	received.merge(data)


func _fail(message: String) -> void:
	printerr("FAIL: W10 v7 rock reflection " + message)
	quit(1)

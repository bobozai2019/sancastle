extends SceneTree

const Uniforms := preload("res://scripts/visual/water_render_uniform_snapshot.gd")
var output := "D:/godot/project/sandcastle/test_output/water_material_natural/t00_baseline"
var scene_path := "res://scenes/water_material_natural_candidate/rdc_v1_fixed.tscn"
var target_tick := 360
var normal_debug := 0
var normal_ablation := false
var lighting_ablation := false
var initialization_timeout_s := 180
var fields := {}
var preview: Node3D
var probe_failed := false

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
		if arg.begins_with("--scene="): scene_path = arg.trim_prefix("--scene=")
		if arg.begins_with("--tick="): target_tick = int(arg.trim_prefix("--tick="))
		if arg.begins_with("--normal-debug="): normal_debug = int(arg.trim_prefix("--normal-debug="))
		if arg == "--normal-ablation": normal_ablation = true
		if arg == "--lighting-ablation": lighting_ablation = true
		if arg.begins_with("--init-timeout-s="): initialization_timeout_s = clampi(int(arg.trim_prefix("--init-timeout-s=")),15,900)
	call_deferred("_run")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	preview = load(scene_path).instantiate()
	preview.replay_target_tick = target_tick
	if not _prepare_preview():return
	root.add_child(preview)
	var deadline := Time.get_ticks_msec() + initialization_timeout_s * 1000
	while not preview.replay_ready:
		await process_frame
		if not preview.last_error.is_empty() or Time.get_ticks_msec() > deadline:
			_fail("initialization/tick failure: " + preview.last_error)
			return
	if preview.completed_ticks != target_tick or preview.tick_pending:
		_fail("incomplete state")
		return
	var shader_uniforms := []
	for uniform in preview.water_material.shader.get_shader_uniform_list():
		shader_uniforms.append(String(uniform.name))
	if "rock_state" not in shader_uniforms or "water_state" not in shader_uniforms:
		_fail("invalid water shader interface/compilation")
		return
	RenderingServer.call_on_render_thread(_read_fields)
	while fields.size() < 7:
		await process_frame
		if Time.get_ticks_msec() > deadline:
			_fail("readback timeout")
			return
	var artifacts := {}
	var hash_ctx := HashingContext.new()
	for field in fields:
		var bytes: PackedByteArray = fields[field]
		var expected_bytes := 256 * 256 * (2 if field == "wetness" else (8 if field == "foam" else 4))
		if bytes.size() != expected_bytes:
			_fail("invalid field %s: %d expected %d" % [field, bytes.size(), expected_bytes])
			return
		var path: String = output + "/" + String(field) + ".bin"
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_buffer(bytes)
		file.close()
		hash_ctx.start(HashingContext.HASH_SHA256)
		hash_ctx.update(bytes)
		artifacts[field] = {"path": path, "bytes": bytes.size(), "sha256": hash_ctx.finish().hex_encode()}
	var cameras := {}
	if normal_debug > 0:
		preview.water_material.set_shader_parameter("natural_normal_debug", normal_debug)
	for id in [&"oblique", &"close", &"grazing"]:
		if not preview.set_fixture_camera(id):
			_fail("camera missing")
			return
		for i in range(8): await process_frame
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		var path := output + "/" + String(id) + ".png"
		if image.save_png(path) != OK:
			_fail("capture failure")
			return
		var camera: Camera3D = preview.overview_camera
		cameras[id] = {"image": path, "transform": var_to_str(camera.global_transform),
			"fov": camera.fov, "near": camera.near, "far": camera.far,
			"viewport_px": [image.get_width(), image.get_height()]}
	var env: Environment = preview.get_node("WorldEnvironment").environment
	var manifest := {"role": "water_material_natural_capture_v1", "scene": scene_path,
		"initialization_timeout_s": initialization_timeout_s,
		"pid": OS.get_process_id(), "engine": Engine.get_version_info(),
		"driver": RenderingServer.get_current_rendering_driver_name(),
		"adapter": RenderingServer.get_video_adapter_name(), "vsync": DisplayServer.window_get_vsync_mode(),
		"tick": preview.completed_ticks, "generation": preview.generation,
		"revision": preview.solver.state_revision, "visual_time_s": preview.visual_time_s,
		"requested_profile": preview.render_profile_path,
		"requested_profile_sha256": preview.requested_render_profile_sha256,
		"effective_profile": preview.effective_render_profile,
		"effective_profile_sha256": preview.effective_render_profile_sha256,
		"water_uniforms": Uniforms.material_values(preview.water_material),
		"terrain_uniforms": Uniforms.material_values(preview.terrain_material),
		"wave_workload": preview.staging_wave_workload, "fields": artifacts, "cameras": cameras,
		"environment": {"tonemap_mode": env.tonemap_mode, "exposure": env.tonemap_exposure,
			"ambient_energy": env.ambient_light_energy},
		"render_scale": root.scaling_3d_scale, "msaa": root.msaa_3d,
		"screen_aa": root.screen_space_aa, "taa": root.use_taa}
	if preview.get("effective_candidate") is Dictionary:
		manifest["effective_candidate"] = preview.effective_candidate
	if preview.get("effective_lighting") is Dictionary:
		manifest["effective_lighting"] = preview.effective_lighting
	for name in ["effective_optics","effective_foam","effective_reflection","effective_style","effective_compilation"]:
		if preview.get(name) is Dictionary:
			manifest[name] = preview.get(name)
	manifest["shader_sha256"] = FileAccess.get_sha256(preview.water_material.shader.resource_path)
	manifest["scene_sha256"] = FileAccess.get_sha256(scene_path)
	manifest["normal_debug"] = normal_debug
	var file := FileAccess.open(output + "/manifest.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "\t"))
	file.close()
	if normal_ablation:
		await _sweep(artifacts)
		if probe_failed:return
	if lighting_ablation:
		await _lighting_sweep(artifacts)
		if probe_failed:return
	print("PASS: natural capture complete; visual gate requires review")
	quit(0)

func _lighting_sweep(before: Dictionary) -> void:
	var sun: DirectionalLight3D = preview.get_node("SandFixtureSun")
	var original_rotation := sun.rotation
	var cases := {}
	for id in ["off", "on", "zero_gain", "yaw180"]:
		sun.rotation = original_rotation
		if id == "yaw180": sun.rotation.y += PI
		preview._sync_sun()
		preview.water_material.set_shader_parameter("natural_glint_enabled", id != "off")
		preview.water_material.set_shader_parameter("natural_glint_gain", 0.0 if id == "zero_gain" else preview.lighting_profile.sun_glint_gain)
		var images := {}
		for debug in [0,1]:
			preview.water_material.set_shader_parameter("natural_lighting_debug", debug)
			for camera in [&"oblique", &"close", &"grazing", &"sunward"]:
				preview.set_fixture_camera(camera)
				for i in range(8): await process_frame
				await RenderingServer.frame_post_draw
				var path: String = output + "/%s_debug%d_%s.png" % [String(id), debug, String(camera)]
				if root.get_texture().get_image().save_png(path) != OK:
					_fail("lighting sweep capture failure")
					return
				images["%d_%s" % [debug, String(camera)]] = {"path":path,"sha256":FileAccess.get_sha256(path)}
		cases[id] = {"images":images,"uniforms":Uniforms.material_values(preview.water_material),
			"sun_rotation":str(sun.rotation),"sun_direction":str(sun.global_basis.z.normalized())}
	fields.clear()
	RenderingServer.call_on_render_thread(_read_fields)
	var deadline := Time.get_ticks_msec() + 10000
	while fields.size() < 7:
		await process_frame
		if Time.get_ticks_msec() > deadline:
			_fail("lighting sweep readback timeout")
			return
	var identical := {}
	for field in fields:
		var ctx := HashingContext.new()
		ctx.start(HashingContext.HASH_SHA256);ctx.update(fields[field])
		identical[field] = ctx.finish().hex_encode() == before[field].sha256
		if not identical[field]:
			_fail("lighting sweep authority changed")
			return
	var file := FileAccess.open(output + "/lighting_ablation.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"cases":cases,"authority_identical":identical,
		"tick":preview.completed_ticks,"generation":preview.generation,"revision":preview.solver.state_revision,
		"clock":preview.visual_time_s,"scope":"manual sun glint; no shadow claim"},"\t"))
	file.close()

func _sweep(before: Dictionary) -> void:
	var revision: int = preview.solver.state_revision
	var generation: int = preview.generation
	var cases := {}
	var original0: Vector4 = preview.water_material.get_shader_parameter("natural_layer0")
	var original1: Vector4 = preview.water_material.get_shader_parameter("natural_layer1")
	for mode in range(5):
		preview.water_material.set_shader_parameter("natural_normal_mode", mini(mode, 2))
		preview.water_material.set_shader_parameter("use_detail_normals", mode != 0 and mode != 4)
		var layer0 := original0
		var layer1 := original1
		if mode == 3:
			layer0.z *= 3.0
			layer1.z *= 3.0
		preview.water_material.set_shader_parameter("natural_layer0", layer0)
		preview.water_material.set_shader_parameter("natural_layer1", layer1)
		var results := {}
		for debug in [0, 1, 2]:
			preview.water_material.set_shader_parameter("natural_normal_debug", debug)
			var images := {}
			for id in [&"oblique", &"close", &"grazing"]:
				preview.set_fixture_camera(id)
				for i in range(8): await process_frame
				await RenderingServer.frame_post_draw
				var path := output + "/mode%d_debug%d_%s.png" % [mode, debug, String(id)]
				var image := root.get_texture().get_image()
				if image.save_png(path) != OK:
					_fail("normal sweep save failed")
					return
				images[id] = {"path": path, "sha256": FileAccess.get_sha256(path)}
			results[str(debug)] = images
		cases[str(mode)] = {"images": results, "uniforms": Uniforms.material_values(preview.water_material)}
	fields.clear()
	RenderingServer.call_on_render_thread(_read_fields)
	var deadline := Time.get_ticks_msec() + 10000
	while fields.size() < 7:
		await process_frame
		if Time.get_ticks_msec() > deadline:
			_fail("normal sweep readback timeout")
			return
	var identical := {}
	for field in fields:
		var ctx := HashingContext.new()
		ctx.start(HashingContext.HASH_SHA256)
		ctx.update(fields[field])
		identical[field] = ctx.finish().hex_encode() == before[field].sha256
		if not identical[field]:
			_fail("normal sweep authority changed: " + field)
			return
	if revision != preview.solver.state_revision or generation != preview.generation or target_tick != preview.completed_ticks:
		_fail("normal sweep state boundary changed")
		return
	var file := FileAccess.open(output + "/normal_ablation.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"cases": cases, "authority_identical": identical,
		"revision": revision, "generation": generation, "tick": target_tick,
		"visual_time_s": preview.visual_time_s, "requested_candidate": preview.candidate_profile_path,
		"runtime_overrides": "cases0/1/2=off/legacy/texture; case3=texture overall gain x3, case4=texture with detail switch off; fixed completed state"}, "\t"))
	file.close()

func _read_fields() -> void:
	for field in ["rock", "sand", "water", "momentum_x", "momentum_z", "wetness"]:
		if preview.solver.request_data(field, _received.bind(field)) != OK:
			call_deferred("_fail", "readback request failed: " + field)
	if preview.foam_field.request_data(_received.bind("foam")) != OK:
		call_deferred("_fail", "foam readback request failed")

func _received(bytes: PackedByteArray, field: String) -> void:
	call_deferred("_store", bytes, field)

func _store(bytes: PackedByteArray, field: String) -> void:
	fields[field] = bytes

func _fail(message: String) -> void:
	probe_failed = true
	push_error(message)
	quit(1)

func _prepare_preview() -> bool:
	return true

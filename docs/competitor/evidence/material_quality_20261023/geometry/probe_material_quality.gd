extends "res://tests/integration/unified_edit_playable_probe.gd"

func _material(m: ShaderMaterial) -> Dictionary:
	var row := {"shader": m.shader.resource_path, "shader_sha256": FileAccess.get_sha256(m.shader.resource_path), "uniforms": {}}
	for u in m.shader.get_shader_uniform_list():
		var value: Variant = m.get_shader_parameter(u.name)
		if value == null: value = RenderingServer.shader_get_parameter_default(m.shader.get_rid(), u.name)
		row.uniforms[u.name] = var_to_str(value)
	return row

func _capture(label: String) -> void:
	for frame in 8:
		await process_frame
		await RenderingServer.frame_post_draw
	check("capture_" + label, root.get_texture().get_image().save_png(output + "/" + label + ".png") == OK)

func _run() -> void:
	orphan_baseline = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	DisplayServer.window_set_size(Vector2i(1280, 720))
	scene = load("res://scenes/main.tscn" if scene_key == "main" else "res://scenes/playable/test1_geometry.tscn").instantiate()
	scene.playing = false
	scene.generation = 1001
	root.add_child(scene)
	var start := Time.get_ticks_msec()
	while (not scene.ready_for_ticks or scene._booting) and scene.last_error.is_empty() and Time.get_ticks_msec() - start < 90000:
		await process_frame
	check("entry_ready", scene.ready_for_ticks and scene.last_error.is_empty())
	if not scene.ready_for_ticks:
		observations.error = String(scene.last_error)
		await _close()
		return
	scene.hide_hud = true
	scene.get_node("Interface").hide()
	var sand: ShaderMaterial = scene.get_node("GpuSandTerrain").material_override
	var water: ShaderMaterial = scene.get_node("GpuWaterSurface").material_override
	var camera: Camera3D = scene.get_viewport().get_camera_3d()
	observations.sources = scene.configuration.sources.duplicate(true)
	observations.configuration = scene.configuration.duplicate(true)
	observations.sand = _material(sand)
	observations.water = _material(water)
	observations.camera = {"transform": var_to_str(camera.global_transform), "fov": camera.fov}
	observations.render = {"size": var_to_str(root.size), "msaa_3d": root.msaa_3d, "screen_space_aa": root.screen_space_aa, "use_taa": root.use_taa, "adapter": RenderingServer.get_video_adapter_name(), "engine": Engine.get_version_info()}
	observations.tick = scene.runtime.current.completed_tick
	observations.time = scene.runtime.current.advanced_time_s
	await _capture("baseline")
	var variants := [[sand, "sand_grain_scale", 70.0, "sand_density_70"], [sand, "sand_grain_gain", 0.06, "sand_color_006"], [sand, "sand_dry_specular", 1.0, "sand_specular_1"], [water, "rdc_normal_gain", 0.55, "water_normal_055"], [water, "rdc_normal_scale", 0.3, "water_scale_03"]]
	for variant in variants:
		var material: ShaderMaterial = variant[0]
		var old: Variant = material.get_shader_parameter(variant[1])
		material.set_shader_parameter(variant[1], variant[2])
		await _capture(variant[3])
		material.set_shader_parameter(variant[1], old)
	var old_shader := sand.shader
	var trial := Shader.new()
	trial.code = old_shader.code.replace("cull_disabled, vertex_lighting, specular_disabled", "cull_disabled, specular_disabled")
	sand.shader = trial
	await _capture("sand_pixel_lighting")
	sand.shader = old_shader
	var wet_trial := Shader.new()
	wet_trial.code = old_shader.code.replace("wetness_state : filter_nearest", "wetness_state : filter_linear")
	sand.shader = wet_trial
	await _capture("sand_wetness_linear")
	sand.shader = old_shader
	root.msaa_3d = Viewport.MSAA_4X
	await _capture("msaa_4x")
	root.msaa_3d = observations.render.msaa_3d
	await _capture("restored")
	check("baseline_restored_identical", FileAccess.get_sha256(output + "/baseline.png") == FileAccess.get_sha256(output + "/restored.png"))
	check("tick_unchanged", scene.runtime.current.completed_tick == observations.tick and scene.runtime.current.advanced_time_s == observations.time)
	await _close()

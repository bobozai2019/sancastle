extends "res://docs/competitor/tools/probe_material_quality.gd"

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
	observations.configuration = scene.configuration.duplicate(true)
	observations.layers = {}
	for path in ["GpuWaterSurface", "ShoreContactOverlay", "PrototypeFrontFoamDense"]:
		var node: MeshInstance3D = scene.get_node(path)
		observations.layers[path] = _material(node.material_override)
		observations.layers[path].visible = node.is_visible_in_tree()
		observations.layers[path].vertices = node.mesh.surface_get_array_len(0)
	var camera: Camera3D = scene.get_viewport().get_camera_3d()
	observations.camera = {"transform": var_to_str(camera.global_transform), "fov": camera.fov}
	observations.render = {"size": var_to_str(root.size), "adapter": RenderingServer.get_video_adapter_name(), "engine": Engine.get_version_info()}
	observations.frames = []
	for target in [0, 120, 240, 360]:
		start = Time.get_ticks_msec()
		while scene.runtime.current.completed_tick < target and Time.get_ticks_msec() - start < 180000:
			var error: StringName = scene.runtime.request_tick(1.0 / 30.0)
			if not error.is_empty():
				observations.tick_error = String(error)
				break
			await _wait_tick()
		check("target_tick_" + str(target), scene.runtime.current.completed_tick == target)
		var label := "t" + str(target)
		await _capture(label)
		observations.frames.append({"file": label + ".png", "tick": scene.runtime.current.completed_tick, "time_s": scene.runtime.current.advanced_time_s, "state_seq": scene.runtime.current.completed_state_seq})
		if target == 240 or target == 360:
			for path in ["ShoreContactOverlay", "PrototypeFrontFoamDense"]:
				var node: Node3D = scene.get_node(path)
				var original := node.visible
				node.hide()
				await _capture(label + "_no_" + path)
				node.visible = original
			var water: ShaderMaterial = scene.get_node("GpuWaterSurface").material_override
			var gain: Variant = water.get_shader_parameter("natural_main_foam_gain")
			water.set_shader_parameter("natural_main_foam_gain", 0.0)
			await _capture(label + "_no_water_foam")
			water.set_shader_parameter("natural_main_foam_gain", gain)
			await _capture(label + "_restored")
			check(label + "_restored_identical", FileAccess.get_sha256(output + "/" + label + ".png") == FileAccess.get_sha256(output + "/" + label + "_restored.png"))
	await _close()

func _wait_tick() -> void:
	var start := Time.get_ticks_msec()
	while (scene.runtime.current.pending_count() != 0 or scene.runtime.current.active_count() != 0) and Time.get_ticks_msec() - start < 30000:
		await process_frame

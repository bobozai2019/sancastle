extends "res://tests/integration/unified_edit_playable_probe.gd"

var hashes: Dictionary = {}
var hash_ready := false

func _read_hashes() -> void:
	var owner = scene.runtime.current
	var result := {}
	for field in ["rock", "sand", "water", "momentum_x", "momentum_z", "sediment", "wetness", "compaction", "mold_support", "obstacle"]:
		var rid: RID = owner.state.textures[field] if field in ["rock", "obstacle"] else owner.state.textures[field][0]
		var bytes: PackedByteArray = owner.state.rd.texture_get_data(rid, 0)
		var hash := HashingContext.new()
		hash.start(HashingContext.HASH_SHA256)
		hash.update(bytes)
		result[field] = hash.finish().hex_encode()
	call_deferred("_hashes_received", result)

func _hashes_received(result: Dictionary) -> void:
	hashes = result
	hash_ready = true

func _snapshot() -> Dictionary:
	hash_ready = false
	RenderingServer.call_on_render_thread(_read_hashes)
	while not hash_ready: await process_frame
	return hashes.duplicate()

func _capture(label: String) -> void:
	for frame in 12:
		await process_frame
		await RenderingServer.frame_post_draw
	check("capture_" + label, root.get_texture().get_image().save_png(output + "/" + label + ".png") == OK)

func _run() -> void:
	orphan_baseline = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	DisplayServer.window_set_size(Vector2i(1280, 720))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	scene = load("res://scenes/main.tscn" if scene_key == "main" else "res://scenes/playable/test1_geometry.tscn").instantiate()
	scene.playing = false
	scene.generation = 1001
	root.add_child(scene)
	var start := Time.get_ticks_msec()
	while (not scene.ready_for_ticks or scene._booting) and scene.last_error.is_empty() and Time.get_ticks_msec() - start < 90000: await process_frame
	check("formal_entry_ready", scene.ready_for_ticks and scene.last_error.is_empty())
	if not scene.ready_for_ticks: observations.error = String(scene.last_error); await _close(); return
	scene.hide_hud = true
	var sand: ShaderMaterial = scene.get_node("GpuSandTerrain").material_override
	var candidate := sand.shader
	check("formal_material_linear", candidate.code.contains("sand_state : filter_linear, repeat_disable"))
	var reference := Shader.new()
	reference.code = candidate.code.replace("sand_state : filter_linear, repeat_disable", "sand_state : filter_nearest, repeat_disable")
	observations.sources = scene.configuration.sources.duplicate(true)
	observations.configuration = scene.configuration.duplicate(true)
	observations.shader = {"path": candidate.resource_path, "sha256": FileAccess.get_sha256(candidate.resource_path)}
	var viewport := root.get_viewport_rid()
	observations.render = {"engine": Engine.get_version_info(), "adapter": RenderingServer.get_video_adapter_name(), "driver": RenderingServer.get_current_rendering_driver_name(), "window": var_to_str(DisplayServer.window_get_size()), "output": var_to_str(root.size), "vsync": DisplayServer.window_get_vsync_mode(), "msaa": root.msaa_3d, "taa": root.use_taa, "max_fps": Engine.max_fps}
	observations.camera = var_to_str(root.get_camera_3d().global_transform)
	observations.initial_hashes = await _snapshot()
	await _capture("after_initial")
	sand.shader = reference
	await _capture("before_initial")
	sand.shader = candidate
	await _capture("after_restored")
	check("candidate_restored_exactly", FileAccess.get_sha256(output + "/after_initial.png") == FileAccess.get_sha256(output + "/after_restored.png"))
	check("initial_authority_unchanged", observations.initial_hashes == await _snapshot())
	# Exercise the actual complete runtime, then freeze the same completed state for render cost isolation.
	scene.playing = true
	await create_timer(4.0).timeout
	scene.playing = false
	await _idle()
	check("live_ticks_advanced", scene.runtime.current.completed_tick > 0 and scene.last_error.is_empty())
	observations.cost_tick = scene.runtime.current.completed_tick
	observations.cost_time = scene.runtime.current.advanced_time_s
	observations.cost_hashes = await _snapshot()
	await _capture("after_live")
	RenderingServer.viewport_set_measure_render_time(viewport, true)
	observations.cost = []
	for phase in ["before_1", "after_1", "after_2", "before_2"]:
		sand.shader = reference if phase.begins_with("before") else candidate
		await create_timer(2.0).timeout
		var samples := []
		var previous := Time.get_ticks_usec()
		var deadline := previous + 4000000
		while Time.get_ticks_usec() < deadline:
			await process_frame
			await RenderingServer.frame_post_draw
			var now := Time.get_ticks_usec()
			samples.append({"gpu_ms": RenderingServer.viewport_get_measured_render_time_gpu(viewport), "frame_ms": (now - previous) / 1000.0, "focused": root.has_focus(), "draws": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), "primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)})
			previous = now
		observations.cost.append({"phase": phase, "samples": samples})
		print("SAND_FILTER_COST ", phase, " ", samples.size())
	sand.shader = candidate
	RenderingServer.viewport_set_measure_render_time(viewport, false)
	check("cost_authority_unchanged", observations.cost_hashes == await _snapshot())
	check("cost_tick_unchanged", scene.runtime.current.completed_tick == observations.cost_tick and scene.runtime.current.advanced_time_s == observations.cost_time)
	observations.source_drift = []
	for path in observations.sources:
		if FileAccess.get_sha256(path) != observations.sources[path]: observations.source_drift.append(path)
	check("sources_stable", observations.source_drift.is_empty())
	observations.scope = "Visible 1280x720 full scene; four seconds live smoke then frozen completed state for ABBA whole-main-viewport GPU rendering cost. No end-to-end simulation performance claim."
	await _close()

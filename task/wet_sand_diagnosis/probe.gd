extends "res://tests/integration/unified_edit_playable_probe.gd"

var read_done := false
var read_result := {}

func _read_fields(label: String) -> void:
	var owner = scene.runtime.current
	var result := {}
	for field in ["rock", "sand", "water", "wetness", "compaction"]:
		var rid: RID = owner.state.textures[field] if field == "rock" else owner.state.textures[field][0]
		var bytes: PackedByteArray = owner.state.rd.texture_get_data(rid, 0)
		var path: String = output + "/" + label + "_" + field + ".bin"
		FileAccess.open(path, FileAccess.WRITE).store_buffer(bytes)
		result[field] = {"path": path, "sha256": FileAccess.get_sha256(path), "bytes": bytes.size()}
	var view_bytes: PackedByteArray = owner.state.rd.texture_get_data(owner.views.textures.wetness, 0)
	var path := output + "/" + label + "_view_wetness.bin"
	FileAccess.open(path, FileAccess.WRITE).store_buffer(view_bytes)
	result.view_wetness = {"path": path, "sha256": FileAccess.get_sha256(path), "bytes": view_bytes.size()}
	call_deferred("_received", result)

func _received(result: Dictionary) -> void:
	read_result = result
	read_done = true

func _snapshot(label: String) -> void:
	read_done = false
	RenderingServer.call_on_render_thread(_read_fields.bind(label))
	while not read_done: await process_frame
	check(label + "_view_matches_authority", read_result.wetness.sha256 == read_result.view_wetness.sha256)
	observations.snapshots.append({"label": label, "tick": scene.runtime.current.completed_tick, "time": scene.runtime.current.advanced_time_s, "fields": read_result.duplicate(true)})

func _capture(label: String) -> void:
	for frame in 6:
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
	while (not scene.ready_for_ticks or scene._booting) and scene.last_error.is_empty() and Time.get_ticks_msec() - start < 90000: await process_frame
	check("formal_entry_ready", scene.ready_for_ticks and scene.last_error.is_empty())
	if not scene.ready_for_ticks: observations.error = String(scene.last_error); await _close(); return
	scene.hide_hud = true
	observations.configuration = scene.configuration.duplicate(true)
	observations.sources = scene.configuration.sources.duplicate(true)
	observations.snapshots = []
	observations.camera = var_to_str(root.get_camera_3d().global_transform)
	var material: ShaderMaterial = scene.get_node("GpuSandTerrain").material_override
	observations.material = {}
	for uniform in material.shader.get_shader_uniform_list():
		var value: Variant = material.get_shader_parameter(uniform.name)
		if not value is Object: observations.material[uniform.name] = value
	check("wetness_bound_to_published_view", material.get_shader_parameter("wetness_state").texture_rd_rid == scene.runtime.current.views.textures.wetness)
	await _snapshot("t00")
	await _capture("t00")
	scene._on_trigger_wave_pressed()
	observations.wave_message = scene.action_message
	for target in [3, 6, 10, 16, 24]:
		scene.playing = true
		start = Time.get_ticks_msec()
		while scene.runtime.current.advanced_time_s < target and scene.last_error.is_empty() and Time.get_ticks_msec() - start < 90000: await process_frame
		scene.playing = false
		await _idle()
		check("advanced_" + str(target), scene.runtime.current.advanced_time_s >= target and scene.last_error.is_empty())
		var label := "t%02d" % target
		await _snapshot(label)
		await _capture(label)
		print("WET_DIAG_STATE ", label, " ", scene.runtime.current.advanced_time_s)
	var original := material.shader
	for forced_wet in [0.0, 1.0]:
		var variant := Shader.new()
		variant.code = original.code.replace("float wet = clamp(texture(wetness_state, UV).r, 0.0, 1.0);", "float wet = %.1f;" % forced_wet)
		material.shader = variant
		await _capture("forced_wet_" + str(int(forced_wet)))
	material.shader = original
	material.set_shader_parameter("debug_mode", 4)
	await _capture("wetness_debug")
	material.set_shader_parameter("debug_mode", 0)
	await _capture("restored")
	await _snapshot("restored")
	check("visual_probe_preserves_wetness", observations.snapshots[-1].fields.wetness.sha256 == observations.snapshots[-2].fields.wetness.sha256)
	check("visual_restored_exactly", FileAccess.get_sha256(output + "/t24.png") == FileAccess.get_sha256(output + "/restored.png"))
	await _close()

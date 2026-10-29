extends "res://tests/integration/async_pipeline_main_probe.gd"

var service: Node
var evidence := {}

func maximum(values: PackedFloat32Array) -> float:
	var result := -INF
	for value in values: result = maxf(result, value)
	return result

func wait_ready() -> bool:
	var deadline := Time.get_ticks_msec() + 90000
	while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_msec() < deadline: await process_frame
	var ok: bool = preview.ready_for_ticks and preview.last_error.is_empty()
	check(preview.scene_key + "_ready", ok)
	return ok

func screenshot(name: String) -> void:
	var old_hide: bool = preview.hide_hud
	preview.hide_hud = true
	preview.get_node("UIVisibility").visible = false
	preview._update_status()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.get_base_dir().path_join(name + ".png"))
	preview.hide_hud = old_hide
	preview.get_node("UIVisibility").visible = true
	preview._update_status()

func switch_to(key: String) -> bool:
	var panel: Node = preview.get_node("Interface/EditPanel/Margin/Controls/SceneSwitcher")
	panel.targets.select(panel.KEYS.find(key))
	panel.switch_button.pressed.emit()
	check("menu_switch_admitted_" + key, service.busy)
	var deadline := Time.get_ticks_msec() + 180000
	while service.busy and Time.get_ticks_msec() < deadline: await process_frame
	preview = service.active_scene
	var ok: bool = not service.busy and preview != null and preview.scene_key == key and service.last_error.is_empty()
	if not ok:
		print("SCENE_SWITCH_FAILURE ", service.last_error)
		evidence["switch_failure_" + key] = {"error":service.last_error, "busy":service.busy, "active":preview.scene_key if preview != null else "none"}
	check("menu_switch_complete_" + key, ok)
	return ok

func capture(label: String) -> Dictionary:
	var result: Dictionary = await preview.capture_async_checkpoint_data()
	check(label + "_capture", result.error.is_empty())
	return result.get("checkpoint", {})

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	root.size = Vector2i(1280, 720)
	service = root.get_node("BeachScenes")
	preview = load("res://scenes/main.tscn").instantiate()
	preview.playing = false
	root.add_child(preview)
	current_scene = preview
	if not await wait_ready(): await finish(); return
	preview.get_node("Interface/PerformancePanel/Margin/Rows/Header/Sampling").button_pressed = false
	var panel: Node = preview.get_node("Interface/EditPanel/Margin/Controls/SceneSwitcher")
	check("main_menu_has_four_scenes", panel.targets.item_count == 4 and panel.KEYS[3] == "test1_geometry")
	var main_before := await read("sand")
	if not await switch_to("test1_geometry"): await finish(); return
	check("new_scene_correct_camera", preview.use_player_camera and preview.player_camera.current and is_equal_approx(preview.player_camera.fov, 30))
	check("low_water_cycle_configured", preview.async_controller.water.tide_mode == 3 and absf(preview.async_controller.water.tide.x - 0.95) < 0.00001 and absf(preview.async_controller.water.tide.y - 0.45) < 0.00001)
	check("no_decorative_gravel", preview.gravel_count == 0 and preview.gravel_field.active_count == 0 and not preview.gravel_layer.visible)
	check("inherited_rock_environment_hidden", not preview.get_node("ReflectionRockEnvironment").visible)
	var mesh: ArrayMesh = preview.get_node("GpuSandTerrain").mesh
	var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var low := Vector3(INF, INF, INF)
	var high := Vector3(-INF, -INF, -INF)
	for p in vertices: low = low.min(p); high = high.max(p)
	check("visible_mesh_exact_30_by_15", low.x == -15 and high.x == 15 and low.z == -7.5 and high.z == 7.5)
	check("water_and_sand_same_mesh", preview.get_node("GpuWaterSurface").mesh == mesh)
	check("sand_side_uses_completed_bed", preview.get_node("SandSides").material_override.get_shader_parameter("sand_state") == preview.sand_texture)
	check("outside_pick_rejected", not preview._pick_current({"position":Vector3(0, 1, 10), "collider":preview.collision_proxy.body}, true))
	var initial := await capture("initial")
	var baked := FileAccess.get_file_as_bytes("res://assets/test1_geometry/initial_state.f32").to_float32_array()
	var sand: PackedFloat32Array = initial.native.fields.sand.to_float32_array()
	var water: PackedFloat32Array = initial.native.fields.water.to_float32_array()
	var initial_exact := true
	for i in 65536:
		if sand[i] != baked[i*5] or water[i] != baked[i*5+1]: initial_exact = false
	check("gpu_initial_sand_water_match_baked_fields", initial_exact)
	check("height_and_zero_rock_base", sand.to_byte_array() == initial.native.fields.sand and maximum(sand) > 6.58 and maximum(sand) < 6.60 and maximum(initial.native.fields.rock.to_float32_array()) == 0)
	evidence.initial = {"sand_sha256":digest(initial.native.fields.sand), "water_sha256":digest(initial.native.fields.water), "max_height":maximum(sand), "mesh_bounds":[low, high]}
	await screenshot("initial_original_camera")
	await physics_frame
	var point := Vector2(-1, -1)
	for y in range(250, 650, 25):
		for x in range(450, 1100, 25):
			var hit: Dictionary = preview.pick(Vector2(x, y))
			if not hit.is_empty() and preview._pick_current(hit, true) and absf(hit.position.x) < 13 and absf(hit.position.z) < 6:
				point = Vector2(x, y); break
		if point.x > 0: break
	check("real_physics_pick", point.x > 0)
	if point.x > 0:
		preview.brush_panel._on_tool_pressed(&"place_sand")
		var mouse := InputEventMouseButton.new()
		mouse.position = point; mouse.button_index = MOUSE_BUTTON_LEFT; mouse.pressed = true
		preview._unhandled_input(mouse)
		mouse.pressed = false; preview._input(mouse)
		check("real_ui_fill_drained", await idle())
		check("real_ui_fill_changed_sand", await read("sand") != initial.native.fields.sand)
		preview.brush_panel._on_tool_pressed(&"remove_sand")
		mouse.pressed = true; preview._unhandled_input(mouse)
		mouse.pressed = false; preview._input(mouse)
		check("real_ui_dig_drained", await idle())
		check("both_edits_accepted", preview.async_controller.accepted_commands == 2)
	preview.playing = true
	var deadline := Time.get_ticks_msec() + 45000
	while preview.completed_ticks < 20 and preview.last_error.is_empty() and Time.get_ticks_msec() < deadline: await process_frame
	preview.playing = false
	check("water_simulation_twenty_ticks", preview.completed_ticks >= 20 and preview.last_error.is_empty())
	check("water_and_edits_drained", await idle())
	var after := await capture("after_simulation")
	var invalid := after.duplicate(true)
	invalid.domain_id = "unknown_geometry_domain"
	check("unknown_domain_rejected", not preview.AsyncCheckpoint.validate(invalid, preview.source_signature).is_empty())
	var padding_dry := true
	var water_after: PackedFloat32Array = after.native.fields.water.to_float32_array()
	for i in 65536:
		if i / 256 < 68 or i / 256 >= 188:
			if water_after[i] != 0: padding_dry = false
	check("z_padding_remains_dry", padding_dry)
	check("initial_rest_phase_does_not_flood", maximum(after.native.fields.water.to_float32_array()) < 1.4)
	check("height_still_readable", maximum(after.native.fields.sand.to_float32_array()) > 6.3)
	await screenshot("after_simulation")
	var save_path := output.get_base_dir().path_join("geometry.sandcp")
	check("new_domain_checkpoint_saves", (await preview.save_gpu_checkpoint(save_path)).is_empty())
	check("new_domain_checkpoint_restores", (await preview.restore_gpu_checkpoint(save_path)).is_empty())
	var restored := await capture("restored")
	for field in after.native.fields: check("restore_field_" + field, after.native.fields[field] == restored.native.fields[field])
	var tick: int = preview.completed_ticks
	if await switch_to("main"):
		check("main_state_preserved", await read("sand") == main_before)
		if await switch_to("test1_geometry"):
			var returned := await capture("returned")
			check("return_tick_preserved", preview.completed_ticks == tick)
			for field in restored.native.fields: check("switch_return_field_" + field, restored.native.fields[field] == returned.native.fields[field])
			check("return_no_gravel", preview.gravel_field.active_count == 0 and not preview.gravel_layer.visible)
			await screenshot("returned")
	await finish()

func finish() -> void:
	if preview != null:
		evidence.last_error = preview.last_error
		hardware = {"engine":Engine.get_version_info(), "adapter":RenderingServer.get_video_adapter_name(), "driver":RenderingServer.get_current_rendering_driver_name(), "window":DisplayServer.window_get_size(), "profile":preview._runtime_configuration_signature()}
		await preview.shutdown()
		check("gpu_resources_released", preview.gpu_release_done and preview.solver.rd == null)
		preview.queue_free()
		await process_frame
	var file := FileAccess.open(output, FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass":not failed, "checks":checks, "evidence":evidence, "runtime":hardware}, "\t"))
	quit(1 if failed else 0)

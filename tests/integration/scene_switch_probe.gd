extends SceneTree

var scene
var service
var output := "D:/godot/project/sandcastle/test_output/scene_switch_20261013_v1"
var checks := []
var snapshots := {}
var saved_states := {}
const FIELDS := ["sand", "water", "momentum_x", "momentum_z", "sediment", "wetness", "compaction", "rock", "obstacle", "flux"]

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			output = arg.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(output)
	call_deferred("_run")

func check(name: String, ok: bool, details: Variant = null) -> void:
	checks.append({"name": name, "pass": ok, "details": details})
	print("SCENE_SWITCH_CHECK ", name, " ", ok)
	if not ok:
		_finish(1)

func _read() -> void:
	for field in FIELDS:
		scene.solver.request_data(field, func(bytes: PackedByteArray) -> void: call_deferred("_received", field, bytes))

func _received(field: String, bytes: PackedByteArray) -> void:
	snapshots[field] = bytes

func snapshot() -> Dictionary:
	snapshots.clear()
	RenderingServer.call_on_render_thread(_read)
	var deadline := Time.get_ticks_msec() + 30000
	while snapshots.size() < FIELDS.size() and Time.get_ticks_msec() < deadline:
		await process_frame
	return snapshots.duplicate()

func _wait_ready() -> void:
	var deadline := Time.get_ticks_msec() + 90000
	while not scene.ready_for_ticks and scene.last_error.is_empty() and Time.get_ticks_msec() < deadline:
		await process_frame
	check(scene.scene_key + "_ready", scene.ready_for_ticks and scene.last_error.is_empty(), scene.last_error)

func tick() -> void:
	var before: int = scene.completed_ticks
	scene._start_tick()
	var deadline := Time.get_ticks_msec() + 30000
	while scene.completed_ticks == before and scene.last_error.is_empty() and Time.get_ticks_msec() < deadline:
		await process_frame
	check(scene.scene_key + "_tick_" + str(before), scene.completed_ticks == before + 1 and scene.last_error.is_empty(), scene.last_error)

func switch_to(key: String, inject_failure: bool = false) -> void:
	var generation: int = scene.generation
	var panel: Node = scene.get_node("Interface/EditPanel/Margin/Controls/SceneSwitcher")
	panel.targets.select(panel.KEYS.find(key))
	service.inject_target_failure_once = inject_failure
	panel.switch_button.pressed.emit()
	check("switch_admitted_" + key, service.busy)
	check("duplicate_switch_blocked", not service.request_switch(key))
	var deadline := Time.get_ticks_msec() + 180000
	while service.busy and Time.get_ticks_msec() < deadline:
		await process_frame
	scene = service.active_scene
	check("switch_completed_" + key, not service.busy and scene != null and scene.ready_for_ticks and scene.last_error.is_empty(), service.last_error)
	check("new_generation_" + key, scene.generation > generation)
	if not inject_failure:
		check("selected_scene_" + key, scene.scene_key == key and service.last_error.is_empty())
	check("controls_carried_" + key, is_equal_approx(scene.dig_amount_m3, 0.025) and is_equal_approx(scene.fill_amount_m3, 0.01) and is_equal_approx(scene.manual_wave_amplitude_m, 0.08))

func pick_screen() -> Vector2:
	var deadline := Time.get_ticks_msec() + 30000
	while (scene.collision_proxy.staging_texture.is_valid() or not scene.collision_proxy.pending_revisions.is_empty()) and Time.get_ticks_msec() < deadline:
		await process_frame
	await physics_frame
	await physics_frame
	for y in range(240, 540, 35):
		for x in range(430, 920, 35):
			var point := Vector2(x, y)
			var hit: Dictionary = scene.pick(point)
			if not hit.is_empty() and scene._pick_current(hit):
				return point
	return Vector2(-1, -1)

func click_tool(tool: String, screen: Vector2, wait_complete: bool = true) -> void:
	scene.get_node("Interface/EditPanel/Margin/Controls/Tools/" + tool).pressed.emit()
	var event := InputEventMouseButton.new()
	event.position = screen
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	scene._unhandled_input(event)
	event.pressed = false
	scene._input(event)
	if wait_complete:
		var deadline := Time.get_ticks_msec() + 30000
		while scene.input_running and Time.get_ticks_msec() < deadline:
			await process_frame
		check(scene.scene_key + "_" + tool + "_applied", not scene.input_running and not scene.input_results.is_empty() and scene.input_results[-1].result.get("status") == 1, scene.input_results.back() if not scene.input_results.is_empty() else scene.last_error)

func _features() -> void:
	await tick()
	await tick()
	var before := await snapshot()
	var screen := await pick_screen()
	check(scene.scene_key + "_physics_pick", screen.x >= 0)
	var stock: float = scene.domain.tool_inventory_m3
	await click_tool("DigTool", screen)
	var dug := await snapshot()
	check(scene.scene_key + "_real_sand_changed", before.sand != dug.sand)
	check(scene.scene_key + "_dig_stock", absf(scene.domain.tool_inventory_m3 - stock - 0.025) < 0.00001)
	await click_tool("FillTool", screen)
	var after := await snapshot()
	check(scene.scene_key + "_fill_sand_changed", after.sand != dug.sand)
	check(scene.scene_key + "_net_stock", absf(scene.domain.tool_inventory_m3 - stock - 0.015) < 0.00001)
	var bed_delta := 0.0
	var old_sand: PackedFloat32Array = before.sand.to_float32_array()
	var new_sand: PackedFloat32Array = after.sand.to_float32_array()
	for i in old_sand.size():
		bed_delta += float(new_sand[i]) - float(old_sand[i])
	check(scene.scene_key + "_sand_ledger", absf(bed_delta * 0.125 * 0.125 + scene.domain.tool_inventory_m3 - stock) < 0.00001, bed_delta * 0.125 * 0.125)
	check(scene.scene_key + "_collision_published", scene._pick_current(scene.pick(screen)))
	var waves: int = scene.wave_requests.size()
	scene.get_node("Interface/EditPanel/Margin/Controls/TriggerWave").pressed.emit()
	check(scene.scene_key + "_manual_wave", scene.wave_requests.size() == waves + 1)
	check(scene.scene_key + "_main_materials", scene._validate_compiled_inputs())
	await process_frame
	await RenderingServer.frame_post_draw
	check(scene.scene_key + "_panel_fits", root.get_visible_rect().encloses(scene.get_node("Interface/EditPanel").get_global_rect()))
	root.get_texture().get_image().save_png(output.path_join(scene.scene_key + ".png"))
	saved_states[scene.scene_key] = {"fields": after, "stock": scene.domain.tool_inventory_m3, "tick": scene.completed_ticks, "waves": scene.wave_requests.size()}

func _run() -> void:
	root.size = Vector2i(1280, 720)
	service = root.get_node("BeachScenes")
	scene = load("res://scenes/main.tscn").instantiate()
	scene.playing = false
	root.add_child(scene)
	current_scene = scene
	await _wait_ready()
	var controls: Node = scene.get_node("Interface/EditPanel/Margin/Controls")
	controls.get_node("DigAmount").value = 0.025
	controls.get_node("FillAmount").value = 0.01
	controls.get_node("WaveAmount").value = 0.08
	scene.get_node("Interface/PerformancePanel/Margin/Rows/Header/Sampling").button_pressed = false
	check("invalid_route_rejected", not service.request_switch("does_not_exist") and service.active_scene == scene)
	await _features()
	await switch_to("test1_capture")
	await _features()
	await switch_to("test1_backwash")
	await _features()
	# Check domain isolation before any restore is admitted.
	var loaded: Dictionary = preload("res://scripts/simulation/checkpoint_store.gd").load(service.saved.main.path)
	var mismatch: StringName = await scene.restore_gpu_checkpoint_data(loaded.checkpoint)
	check("cross_scene_restore_rejected", mismatch == &"scene_checkpoint_mismatch")
	for key in ["main", "test1_capture", "test1_backwash"]:
		await switch_to(key)
		var restored := await snapshot()
		var exact := true
		for field in FIELDS:
			exact = exact and restored[field] == saved_states[key].fields[field]
		check(key + "_restore_ten_fields_exact", exact)
		check(key + "_restore_stock_tick_waves", scene.domain.tool_inventory_m3 == saved_states[key].stock and scene.completed_ticks == saved_states[key].tick and scene.wave_requests.size() == saved_states[key].waves)
	# Switching during a real water tick waits for its completed state.
	scene._start_tick()
	check("inflight_tick_started", scene.tick_pending)
	await switch_to("main")
	await switch_to("test1_backwash")
	check("inflight_tick_saved", scene.completed_ticks == saved_states.test1_backwash.tick + 1)
	# An admitted edit completes before saving and releasing the old scene.
	var point := await pick_screen()
	await click_tool("DigTool", point, false)
	check("inflight_edit_admitted", scene.input_running)
	await switch_to("main")
	await switch_to("test1_backwash")
	check("inflight_edit_saved_once", absf(scene.domain.tool_inventory_m3 - saved_states.test1_backwash.stock - 0.025) < 0.00001)
	var rollback_before := await snapshot()
	await switch_to("test1_capture", true)
	check("failed_target_returns_old_scene", scene.scene_key == "test1_backwash" and not service.last_error.is_empty())
	var rollback_after := await snapshot()
	var same := true
	for field in FIELDS:
		same = same and rollback_before[field] == rollback_after[field]
	check("rollback_ten_fields_exact", same)
	await scene.shutdown()
	check("clean_shutdown", scene.gpu_release_done)
	_finish(0)

func _finish(code: int) -> void:
	var file := FileAccess.open(output.path_join("result.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass": code == 0, "checks": checks, "engine": Engine.get_version_info(), "adapter": RenderingServer.get_video_adapter_name(), "sessions": service.saved if service != null else {}, "session_directory": service.session_directory if service != null else ""}, "\t"))
	quit(code)

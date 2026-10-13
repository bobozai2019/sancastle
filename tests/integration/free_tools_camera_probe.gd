extends SceneTree

const FIELDS := ["sand", "water", "momentum_x", "momentum_z", "sediment", "wetness", "compaction", "rock", "obstacle", "flux"]
const Store := preload("res://scripts/simulation/checkpoint_store.gd")
var scene
var service
var output := ""
var checks := []
var receipts := []
var readbacks := {}

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	if output.is_empty() or FileAccess.file_exists(output.path_join("result.json")):
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	call_deferred("_run")

func check(name: String, ok: bool, details: Variant = null) -> void:
	checks.append({"name": name, "pass": ok, "details": details})
	print("FREE_TOOLS_CHECK ", name, " ", ok)

func _read() -> void:
	for field in FIELDS:
		scene.solver.request_data(field, func(bytes: PackedByteArray) -> void: call_deferred("_received", field, bytes))

func _received(field: String, bytes: PackedByteArray) -> void:
	readbacks[field] = bytes

func snapshot() -> Dictionary:
	readbacks.clear()
	RenderingServer.call_on_render_thread(_read)
	var deadline := Time.get_ticks_msec() + 30000
	while readbacks.size() < FIELDS.size() and Time.get_ticks_msec() < deadline:
		await process_frame
	check(scene.scene_key + "_readback", readbacks.size() == FIELDS.size())
	return readbacks.duplicate()

func _total(fields: Dictionary) -> float:
	var total := 0.0
	for key in ["sand", "sediment"]:
		for value in fields[key].to_float32_array(): total += float(value) * 0.015625
	return total

func _ready_scene() -> bool:
	var deadline := Time.get_ticks_msec() + 90000
	while not scene.ready_for_ticks and scene.last_error.is_empty() and Time.get_ticks_msec() < deadline:
		await process_frame
	check(scene.scene_key + "_ready", scene.ready_for_ticks and scene.last_error.is_empty(), scene.last_error)
	scene.get_node("Interface/PerformancePanel/Margin/Rows/Header/Sampling").button_pressed = false
	return scene.ready_for_ticks

func _pick_dry() -> Vector2:
	while scene.collision_proxy.staging_texture.is_valid() or not scene.collision_proxy.pending_revisions.is_empty(): await process_frame
	await physics_frame
	await physics_frame
	for y in range(200, 660, 30):
		for x in range(300, 930, 30):
			var hit: Dictionary = scene.pick(Vector2(x, y))
			if not hit.is_empty() and scene._pick_current(hit):
				var cell_x := clampi(int((hit.position.x + 16.0) / 0.125), 0, 255)
				var cell_z := clampi(int((hit.position.z + 16.0) / 0.125), 0, 255)
				if scene.domain.water[cell_z * 256 + cell_x] <= 0.001: return Vector2(x, y)
	return Vector2(-1, -1)

func _click(tool: String, amount: float) -> Dictionary:
	var controls: Node = scene.get_node("Interface/EditPanel/Margin/Controls")
	controls.get_node("FillAmount" if tool == "FillTool" else "DigAmount").value = amount
	controls.get_node("Tools/" + tool).pressed.emit()
	var screen := await _pick_dry()
	check(scene.scene_key + "_dry_physics_pick", screen.x >= 0)
	var before: int = scene.input_results.size()
	var event := InputEventMouseButton.new()
	event.position = screen
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	scene._unhandled_input(event)
	event.pressed = false
	scene._input(event)
	var deadline := Time.get_ticks_msec() + 30000
	while scene.input_running and Time.get_ticks_msec() < deadline: await process_frame
	var receipt: Dictionary = scene.input_results.back().result if scene.input_results.size() > before else {}
	check(scene.scene_key + "_" + tool + "_" + str(amount), not scene.input_running and receipt.get("status") == 1, receipt)
	receipts.append({"scene": scene.scene_key, "tool": tool, "requested": amount, "result": receipt})
	check(scene.scene_key + "_no_inventory", scene.domain.tool_inventory_m3 == 0.0)
	return receipt

func _camera() -> void:
	var camera: Camera3D = scene.player_camera
	var transform := camera.transform
	check("camera_default_active", camera.current)
	root.gui_release_focus()
	for code in [KEY_W, KEY_A, KEY_S, KEY_D]:
		var before := camera.global_position
		var expected: Vector3 = {KEY_W: -camera.global_basis.z, KEY_A: -camera.global_basis.x, KEY_S: camera.global_basis.z, KEY_D: camera.global_basis.x}[code]
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = true
		Input.parse_input_event(event)
		await process_frame
		await process_frame
		event.pressed = false
		Input.parse_input_event(event)
		check("camera_key_" + str(code), (camera.global_position - before).dot(expected) > 0.001)
	var dig: SpinBox = scene.get_node("Interface/EditPanel/Margin/Controls/DigAmount")
	dig.get_line_edit().grab_focus()
	var before := camera.position
	var key := InputEventKey.new()
	key.keycode = KEY_W
	key.physical_keycode = KEY_W
	key.pressed = true
	Input.parse_input_event(key)
	await process_frame
	await process_frame
	key.pressed = false
	Input.parse_input_event(key)
	check("numeric_input_does_not_move_camera", camera.position == before)
	root.gui_release_focus()
	var n: int = scene.input_events.size()
	var right := InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	right.position = Vector2(700, 500)
	right.pressed = true
	Input.parse_input_event(right)
	await process_frame
	check("native_right_press_starts_look", camera.look_active and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED)
	var rotation := camera.rotation
	var motion := InputEventMouseMotion.new()
	motion.position = right.position
	motion.relative = Vector2(20, 10)
	motion.screen_relative = Vector2(20, 10)
	motion.button_mask = MOUSE_BUTTON_MASK_RIGHT
	Input.parse_input_event(motion)
	await process_frame
	check("native_mouse_motion_turns_camera", camera.rotation.distance_to(rotation) > 0.001)
	key.pressed = true
	Input.parse_input_event(key)
	before = camera.position
	await process_frame
	await process_frame
	key.pressed = false
	Input.parse_input_event(key)
	check("wasd_while_right_held_moves_in_3d", camera.position.distance_to(before) > 0.001 and absf(camera.position.y - before.y) > 0.0001)
	check("camera_input_does_not_edit", scene.input_events.size() == n and scene.gpu_brush.is_empty())
	right.pressed = false
	Input.parse_input_event(right)
	await process_frame
	check("native_right_release_restores_mouse", not camera.look_active and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE)
	camera._unhandled_input(InputEventMouseButton.new())
	camera.transform = transform

func _switch(key: String) -> void:
	check("switch_admitted_" + key, service.request_switch(key))
	var deadline := Time.get_ticks_msec() + 180000
	while service.busy and Time.get_ticks_msec() < deadline: await process_frame
	scene = service.active_scene
	check("switch_ready_" + key, not service.busy and scene.scene_key == key and scene.ready_for_ticks and scene.last_error.is_empty(), service.last_error)
	scene.playing = false

func _run() -> void:
	root.size = Vector2i(1280, 720)
	service = root.get_node("BeachScenes")
	scene = load("res://scenes/main.tscn").instantiate()
	scene.playing = false
	root.add_child(scene)
	current_scene = scene
	if not await _ready_scene():
		_finish(1)
		return
	var controls: Node = scene.get_node("Interface/EditPanel/Margin/Controls")
	for name in ["DigAmount", "FillAmount"]:
		var box: SpinBox = controls.get_node(name)
		check(name + "_range_and_default", box.min_value == 0.01 and box.max_value == 1.0 and box.step == 0.01 and box.value == 0.1)
	check("inventory_ui_removed", not controls.has_node("Stock") and not "桶" in scene.status_label.text)
	await _camera()
	var initial := await snapshot()
	var initial_total := _total(initial)
	for amount in [0.1, 0.25, 1.0]:
		var receipt := await _click("FillTool", amount)
		check("fill_full_quantity_" + str(amount), absf(float(receipt.get("actual_sand_m3", 0.0)) - amount) < 0.00001)
	await _click("DigTool", 1.0)
	var after := await snapshot()
	var closure: float = _total(after) - initial_total - scene.domain.sand_source_m3 + scene.domain.sand_sink_m3
	check("external_sand_ledger_closes", absf(closure) < 0.00001, closure)
	check("source_and_sink_independent", scene.domain.sand_source_m3 > 1.34 and scene.domain.sand_sink_m3 > 0.0 and scene.domain.tool_inventory_m3 == 0.0)
	for value in after.sand.to_float32_array():
		if not is_finite(value) or value < 0.0:
			check("sand_nonnegative", false)
			break
	var path := output.path_join("free_tools.sandcp")
	var error: StringName = await scene.save_gpu_checkpoint(path)
	check("native_free_tools_save", error.is_empty(), error)
	var saved: Dictionary = Store.load(path).checkpoint
	check("versioned_external_accounting", saved.gpu_beach_edit.version == 3 and saved.gpu_beach_edit.selection.sand_accounting == "external_v1")
	var invalid := saved.duplicate(true)
	invalid.gpu_beach_edit.prefix[0].available_m3 += 10.0
	error = await scene.restore_gpu_checkpoint_data(invalid)
	check("tampered_external_available_rejected", error == &"invalid_external_sand_input", error)
	invalid = saved.duplicate(true)
	invalid.gpu_beach_edit.prefix[0].erase("sand_accounting")
	error = await scene.restore_gpu_checkpoint_data(invalid)
	check("unmarked_inventory_bypass_rejected", not error.is_empty(), error)
	await _click("FillTool", 0.1)
	error = await scene.restore_gpu_checkpoint_data(saved)
	check("native_free_tools_restore", error.is_empty(), error)
	var restored := await snapshot()
	check("ten_fields_restore_exact", after == restored)
	check("external_ledgers_restore_exact", scene.domain.sand_source_m3 == saved.shadow.sand_source_m3 and scene.domain.sand_sink_m3 == saved.shadow.sand_sink_m3 and scene.domain.tool_inventory_m3 == 0.0)
	for target in ["test1_capture", "test1_backwash"]:
		await _switch(target)
		var own_initial := await snapshot()
		await _click("FillTool", 0.1)
		var own_after := await snapshot()
		closure = _total(own_after) - _total(own_initial) - scene.domain.sand_source_m3 + scene.domain.sand_sink_m3
		check(target + "_fill_first_closes", absf(closure) < 0.00001, closure)
	await _switch("main")
	check("scene_switch_restores_external_fields", after == await snapshot())
	check("scene_switch_restores_external_ledger", scene.domain.sand_source_m3 == saved.shadow.sand_source_m3 and scene.domain.sand_sink_m3 == saved.shadow.sand_sink_m3)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("main_free_tools.png"))
	await scene.shutdown()
	check("clean_shutdown", scene.gpu_release_done)
	_finish(0)

func _finish(code: int) -> void:
	var passed := code == 0
	for item in checks: passed = passed and item.pass
	var file := FileAccess.open(output.path_join("result.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass": passed, "checks": checks, "receipts": receipts, "engine": Engine.get_version_info(), "adapter": RenderingServer.get_video_adapter_name()}, "\t"))
	quit(0 if passed else 1)

extends SceneTree

var scene
var harness
var viewport: SubViewport
var checks := []
var fields := {}
var output := "res://test_output/ui_sand_edit_20261016"

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(output)
	call_deferred("_run")

func check(label: String, passed: bool, detail: Variant = null) -> void:
	checks.append({"name": label, "pass": passed, "detail": detail})
	print("UI_SAND ", label, " ", passed)

func send(event: InputEvent) -> void:
	viewport.push_input(event, true)
	await process_frame

func motion(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	await send(event)

func click(point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	await send(event)

func tap(point: Vector2) -> void:
	await motion(point)
	await click(point, true)
	await click(point, false)

func snapshot() -> Dictionary:
	fields = {}
	RenderingServer.call_on_render_thread(_read)
	var deadline := Time.get_ticks_msec() + 30000
	while fields.size() < 2 and Time.get_ticks_msec() < deadline: await process_frame
	return fields.duplicate()

func _read() -> void:
	for field in ["sand", "water"]:
		scene.solver.request_data(field, func(bytes: PackedByteArray) -> void: call_deferred("_received", field, bytes))

func _received(field: String, bytes: PackedByteArray) -> void:
	fields[field] = bytes

func total_sand(state: Dictionary) -> float:
	var total := 0.0
	for value in state.sand.to_float32_array(): total += value * 0.125 * 0.125
	return total

func _run() -> void:
	root.size = Vector2i(1280, 720)
	harness = load("res://tests/experiments/approx_gpu_edit/input_harness.tscn").instantiate()
	root.add_child(harness)
	viewport = harness.get_node("InputViewport")
	for path in ["res://scenes/main.tscn", "res://scenes/playable/test1_capture.tscn", "res://scenes/playable/test1_backwash.tscn"]:
		scene = load(path).instantiate()
		scene.playing = false
		viewport.add_child(scene)
		var deadline := Time.get_ticks_msec() + 90000
		while not scene.ready_for_ticks and scene.last_error.is_empty() and Time.get_ticks_msec() < deadline: await process_frame
		check(scene.scene_key + "_ready", scene.ready_for_ticks, scene.last_error)
		if not scene.ready_for_ticks: break
		scene.get_node("Interface/PerformancePanel/Margin/Rows/Header/Sampling").button_pressed = false
		var toggle: Button = scene.get_node("UIVisibility/ToggleUI")
		for size in [Vector2i(1280, 720), Vector2i(1024, 768)]:
			viewport.size = size
			await process_frame
			check(scene.scene_key + "_toggle_fits_" + str(size), viewport.get_visible_rect().encloses(toggle.get_global_rect()) and not toggle.get_global_rect().intersects(scene.manual_edit_panel.get_global_rect()))
		viewport.size = Vector2i(1280, 720)
		await process_frame
		var edits: int = scene.input_events.size()
		await tap(toggle.get_global_rect().get_center())
		check(scene.scene_key + "_hide_all", scene.hide_hud and not scene.get_node("Interface").visible and toggle.is_visible_in_tree() and toggle.text == "显示 UI")
		await tap(toggle.get_global_rect().get_center())
		check(scene.scene_key + "_show_all", not scene.hide_hud and scene.get_node("Interface").visible)
		var key := InputEventKey.new()
		key.keycode = KEY_F6
		key.pressed = true
		await send(key)
		check(scene.scene_key + "_f6_sync", scene.hide_hud and not scene.get_node("Interface").visible and toggle.button_pressed)
		await tap(toggle.get_global_rect().get_center())
		for name in ["ShapeBrushPanel", "EditPanel", "PerformancePanel", "StatusLabel"]:
			var panel: Control = scene.get_node("Interface/" + name)
			var start := panel.global_position
			var point := start + Vector2(24, 20)
			await motion(point)
			await click(point, true)
			await motion(point + Vector2(0, 30))
			await click(point + Vector2(0, 30), false)
			check(scene.scene_key + "_drag_" + name, panel.global_position.distance_to(start + Vector2(0, 30)) < 1.0, panel.global_position - start)
			panel.global_position = start
		check(scene.scene_key + "_ui_does_not_edit", scene.input_events.size() == edits)
		await tap(scene.brush_panel.get_node("Margin/Controls/Tools/Fill").get_global_rect().get_center())
		check(scene.scene_key + "_select_deposit", scene.ui_tool == &"place_sand")
		scene.brush_panel.get_node("Margin/Controls/OrdinaryParams/FillAmount").value = 0.25
		await tap(toggle.get_global_rect().get_center())
		while (scene.collision_proxy.staging_texture.is_valid() or not scene.collision_proxy.pending_revisions.is_empty() or scene.collision_proxy.has_prepare_in_flight()) and Time.get_ticks_msec() < deadline: await process_frame
		await physics_frame
		await physics_frame
		var before := await snapshot()
		var screen := Vector2(-1, -1)
		var target := Vector3.ZERO
		for y in range(100, 680, 25):
			for x in range(60, 1200, 25):
				var hit: Dictionary = scene.pick(Vector2(x, y))
				if hit.is_empty() or not scene._pick_current(hit): continue
				var ix := clampi(int((hit.position.x + 16.0) / 0.125), 0, 255)
				var iz := clampi(int((hit.position.z + 16.0) / 0.125), 0, 255)
				if before.water.decode_float((iz * 256 + ix) * 4) > 0.03:
					screen = Vector2(x, y)
					target = hit.position
					break
			if screen.x >= 0: break
		check(scene.scene_key + "_underwater_pick", screen.x >= 0, target)
		if screen.x >= 0:
			var source_before: float = scene.domain.sand_source_m3
			await tap(screen)
			deadline = Time.get_ticks_msec() + 30000
			while scene.input_running and Time.get_ticks_msec() < deadline: await process_frame
			var after := await snapshot()
			var added := total_sand(after) - total_sand(before)
			check(scene.scene_key + "_underwater_deposit", absf(added - 0.25) < 0.00001 and scene.input_events.size() == edits + 1, added)
			check(scene.scene_key + "_ledger_closes", absf(added - (scene.domain.sand_source_m3 - source_before)) < 0.00001)
		await tap(toggle.get_global_rect().get_center())
		await RenderingServer.frame_post_draw
		viewport.get_texture().get_image().save_png(output.path_join(scene.scene_key + ".png"))
		await scene.get_node("Interface/PerformancePanel").stop_sampling()
		await scene.shutdown()
		scene.queue_free()
		await process_frame
	var passed := not checks.is_empty()
	for row in checks: passed = passed and row.pass
	var file := FileAccess.open(output.path_join("result.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass": passed, "checks": checks, "engine": Engine.get_version_info()}, "\t"))
	quit(0 if passed else 1)

extends "res://tests/integration/suspended_sand_probe.gd"

var gravel_data := {}
var service
var saved_states := {}

func send(event: InputEvent) -> void:
	root.push_input(event, true)
	await process_frame

func read_gravel() -> Dictionary:
	gravel_data = {}
	RenderingServer.call_on_render_thread(func() -> void: scene.gravel_field.capture_async(_got_gravel, 100))
	var deadline := Time.get_ticks_msec() + 15000
	while gravel_data.size() < 2 and Time.get_ticks_msec() < deadline: await process_frame
	var data := gravel_data.duplicate()
	data.current_index = scene.gravel_field.current_index
	data.active_count = scene.gravel_field.active_count
	return data

func _got_gravel(bytes: PackedByteArray, key: String, _identity: Dictionary) -> void:
	call_deferred("_record_gravel", bytes, key)

func _record_gravel(bytes: PackedByteArray, key: String) -> void:
	gravel_data[key] = bytes

func wait_drop() -> void:
	var deadline := Time.get_ticks_msec() + 30000
	while scene.gravel_drop_pending and Time.get_ticks_msec() < deadline: await process_frame
	check("drop_settles", not scene.gravel_drop_pending, scene.last_error)
	await _settled()

func switch_to(key: String) -> void:
	check("switch_admitted_" + key, service.request_switch(key))
	var deadline := Time.get_ticks_msec() + 180000
	while service.busy and Time.get_ticks_msec() < deadline: await process_frame
	scene = service.active_scene
	check("switch_ready_" + key, not service.busy and scene != null and scene.scene_key == key and scene.ready_for_ticks, service.last_error)
	if scene != null: scene.playing = false

func _run() -> void:
	if output == "res://test_output/ui_sand_edit_20261016": output = "res://test_output/gravel_drop_20261016"
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1280, 720)
	service = root.get_node("BeachScenes")
	scene = load("res://scenes/main.tscn").instantiate()
	scene.playing = false
	root.add_child(scene)
	current_scene = scene
	var deadline := Time.get_ticks_msec() + 90000
	while not scene.ready_for_ticks and scene.last_error.is_empty() and Time.get_ticks_msec() < deadline: await process_frame
	check("main_ready", scene.ready_for_ticks, scene.last_error)
	if not scene.ready_for_ticks: quit(1); return
	for key in ["main", "test1_capture", "test1_backwash"]:
		if scene.scene_key != key: await switch_to(key)
		scene.get_node("Interface/PerformancePanel/Margin/Rows/Header/Sampling").button_pressed = false
		await _settled()
		if scene.hide_hud: await tap(scene.get_node("UIVisibility/ToggleUI").get_global_rect().get_center())
		await tap(scene.brush_panel.get_node("Margin/Controls/Tools/GravelDrop").get_global_rect().get_center())
		check(key + "_tool_selected", scene.ui_tool == &"gravel_drop" and scene.brush_panel.parameters().count == 16)
		check(key + "_panel_fits", root.get_visible_rect().encloses(scene.brush_panel.get_global_rect()))
		await tap(scene.get_node("UIVisibility/ToggleUI").get_global_rect().get_center())
		var authority := await snapshot()
		var initial := await read_gravel()
		var screen := wet_pick(authority, true)
		check(key + "_underwater_pick", screen.x >= 0)
		if screen.x < 0: break
		var hit: Dictionary = scene.pick(screen)
		await tap(screen)
		await wait_drop()
		var added := await read_gravel()
		var old_bytes: PackedByteArray = initial["state_%d" % initial.current_index]
		var new_bytes: PackedByteArray = added["state_%d" % added.current_index]
		check(key + "_adds_16_and_preserves_old", added.active_count == initial.active_count + 16 and old_bytes.slice(0, initial.active_count*16) == new_bytes.slice(0, initial.active_count*16))
		var localized := true
		for id in range(initial.active_count, added.active_count):
			var point := Vector2(new_bytes.decode_float(id*16), new_bytes.decode_float(id*16+8))
			localized = localized and point.distance_to(Vector2(hit.position.x, hit.position.z)) <= 0.451
		check(key + "_localized", localized)
		check(key + "_authority_unchanged", authority == await snapshot())
		check(key + "_visible_count", scene.gravel_layer.multimesh.visible_instance_count == added.active_count)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join(key + "_drop.png"))
		# Both dry and wet targets are valid; invalid input and capacity are no-ops.
		var dry := wet_pick(authority, false)
		check(key + "_dry_pick", dry.x >= 0)
		if dry.x >= 0:
			await tap(dry)
			await wait_drop()
			check(key + "_dry_adds", scene.gravel_field.active_count == added.active_count + 16)
		var save_path := output.path_join(key + ".sandcp")
		var error: StringName = await scene.save_gpu_checkpoint(save_path)
		check(key + "_save", error.is_empty(), error)
		var saved: Dictionary = Store.load(save_path).checkpoint
		var anchor := await read_gravel()
		check(key + "_versioned_count", saved.visual_extensions.gravel_v1.version == 2 and saved.visual_extensions.gravel_v1.active_count == anchor.active_count)
		if key == "main":
			while scene.gravel_field.active_count < 1024:
				var result: Dictionary = await scene.drop_gravel(Vector2(hit.position.x, hit.position.z), mini(128, 1024-scene.gravel_field.active_count))
				if not result.get("ok", false): check("fill_capacity", false, result); break
			var full := await read_gravel()
			var rejected: Dictionary = await scene.drop_gravel(Vector2(hit.position.x, hit.position.z), 1)
			check("capacity_rejects_without_replacing", rejected.get("error") == &"gravel_capacity_full" and full == await read_gravel())
			var invalid: Dictionary = await scene.drop_gravel(Vector2(INF, 0), 1)
			check("invalid_point_rejected", invalid.get("error") == &"out_of_domain")
			var tampered := saved.duplicate(true)
			tampered.visual_extensions.gravel_v1.active_count = 1025
			check("tampered_count_rejected", not (await scene.restore_gpu_checkpoint_data(tampered)).is_empty())
			error = await scene.restore_gpu_checkpoint_data(saved)
			check("restore_count_and_both_slots", error.is_empty() and anchor == await read_gravel() and scene.ui_tool == &"gravel_drop", error)
		var before_motion := await read_gravel()
		for step in 20:
			var tick: int = scene.completed_ticks
			scene._start_tick()
			deadline = Time.get_ticks_msec() + 30000
			while scene.completed_ticks == tick and scene.last_error.is_empty() and Time.get_ticks_msec() < deadline: await process_frame
		await _settled()
		var moved := await read_gravel()
		var a: PackedByteArray = before_motion["state_%d" % before_motion.current_index]
		var b: PackedByteArray = moved["state_%d" % moved.current_index]
		var moving := 0
		for id in range(initial.active_count, added.active_count):
			if absf(a.decode_float(id*16)-b.decode_float(id*16))+absf(a.decode_float(id*16+8)-b.decode_float(id*16+8)) > 0.00001: moving += 1
		# Main starts with near-still water at this picked point. Check forced-flow
		# displacement separately, without inventing movement below the speed gate.
		if key != "main": check(key + "_new_stones_follow_water", moving > 0, moving)
		saved_states[key] = moved
	for key in ["main", "test1_capture", "test1_backwash"]:
		await switch_to(key)
		check(key + "_switch_restores_dropped_stones", saved_states[key] == await read_gravel())
	await scene.shutdown()
	check("shutdown_releases_gravel", scene.gravel_field == null and scene.gpu_release_done)
	var passed := not checks.is_empty()
	for row in checks: passed = passed and row.pass
	FileAccess.open(output.path_join("result.json"), FileAccess.WRITE).store_string(JSON.stringify({"pass":passed,"checks":checks,"engine":Engine.get_version_info()}, "\t"))
	quit(0 if passed else 1)

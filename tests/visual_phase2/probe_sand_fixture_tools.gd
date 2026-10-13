extends SceneTree

const SCENE := preload("res://scenes/sand_visual_fixture.tscn")
const Store := preload("res://scripts/simulation/checkpoint_store.gd")

var preview: Node3D


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	preview = SCENE.instantiate()
	root.add_child(preview)
	var frames := 0
	while (not preview.ready_for_ticks or preview.completed_ticks < 300) and preview.last_error.is_empty() and frames < 18000:
		await process_frame
		frames += 1
	if not preview.last_error.is_empty() or preview.completed_ticks < 300:
		_fail("fixture failed to reach tick 300")
		return
	preview.playing = false
	while preview.tick_pending:
		await process_frame
	var loose_center := Vector3((176.5 * 0.125) - 16.0, 1.0,
		(128.5 * 0.125) - 16.0)
	var placement := Vector3(0.0, 0.20, 0.0)
	for command in [
		{"kind": &"remove_sand", "amount": 0.08, "position": loose_center},
		{"kind": &"place_sand", "amount": 0.04, "position": placement},
		{"kind": &"compact", "amount": 0.01, "position": placement},
	]:
		var error: StringName = preview._submit_brush(command.kind, command.amount,
			command.position, command.position, &"circle")
		if not error.is_empty():
			_fail("tool submit failed: " + String(error))
			return
		while (preview.tick_pending or not preview.command_queue.pending.is_empty()) and \
				preview.last_error.is_empty() and frames < 24000:
			await process_frame
			frames += 1
		if not preview.last_error.is_empty():
			_fail("tool apply failed: " + preview.last_error)
			return
	if preview.command_queue.applied_log.size() != 3 or \
			preview.command_queue.applied_log[0].kind != &"remove_sand" or \
			preview.command_queue.applied_log[1].kind != &"place_sand" or \
			preview.command_queue.applied_log[2].kind != &"compact":
		_fail("tool command log mismatch")
		return
	var save_path := "user://s02_tools_" + str(Time.get_ticks_usec()) + ".sandcp"
	var save_error: StringName = preview.request_checkpoint_save(save_path)
	if not save_error.is_empty():
		_fail("tool checkpoint refused: " + String(save_error))
		return
	while preview.last_save_path.is_empty() and preview.last_save_error.is_empty() and frames < 26000:
		await process_frame
		frames += 1
	if preview.last_save_path.is_empty():
		_fail("tool checkpoint failed: " + String(preview.last_save_error))
		return
	var loaded: Dictionary = Store.load(save_path)
	if not loaded.error.is_empty() or loaded.prefix_commands.size() != 3 or \
			loaded.checkpoint.fixture_id != &"sand_v1" or \
			not is_equal_approx(loaded.checkpoint.sand_cohesion_yield_height_m, 2.0):
		_fail("tool checkpoint payload mismatch: " + str(loaded.error))
		return
	var result := {"tick": preview.completed_ticks,
		"commands": loaded.prefix_commands.size(),
		"kinds": ["remove_sand", "place_sand", "compact"],
		"inventory_m3": preview.shadow_domain.tool_inventory_m3,
		"fixture_id": String(loaded.checkpoint.fixture_id),
		"cohesion_yield_height_m": loaded.checkpoint.sand_cohesion_yield_height_m,
		"collision_invalid_readbacks": preview.collision_proxy.invalid_readbacks}
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	if result.inventory_m3 <= 0.0 or result.collision_invalid_readbacks != 0:
		_fail("tool inventory or collision readback invalid")
		return
	var output := ProjectSettings.globalize_path(
		"res://test_output/sandcastle_visual_reconstruction_phase2/验收/S02_sand_fixture_tools.json")
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		_fail("cannot write tool evidence")
		return
	file.store_string(JSON.stringify(result, "  "))
	file.close()
	print("PASS: S02 sand fixture tools " + JSON.stringify(result))
	quit(0)


func _fail(message: String) -> void:
	push_error("FAIL: S02 sand fixture tools " + message)
	quit(1)

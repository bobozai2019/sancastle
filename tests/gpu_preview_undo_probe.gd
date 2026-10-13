extends SceneTree

var preview: Node3D
var started_ms := 0
var finished := false
var readback := PackedByteArray()
var phase := ""


func _init() -> void:
	call_deferred("_begin")


func _begin() -> void:
	var scene: PackedScene = load("res://scenes/gpu_water_preview.tscn")
	if scene == null:
		_fail("GPU undo scene unavailable")
		return
	preview = scene.instantiate()
	root.add_child(preview)
	started_ms = Time.get_ticks_msec()
	call_deferred("_watchdog")
	call_deferred("_run")


func _run() -> void:
	while preview.completed_ticks < 3:
		if not preview.last_error.is_empty():
			_fail(preview.last_error)
			return
		await process_frame
	preview.playing = false
	while preview.tick_pending:
		await process_frame
	var initial_sand: PackedFloat32Array = preview.shadow_domain.sand.duplicate()
	var initial_inventory: float = preview.shadow_domain.tool_inventory_m3
	var initial_tick: int = preview.completed_ticks
	var error: StringName = preview._submit_brush(&"remove_sand", 0.08,
		Vector3.ZERO, Vector3.ZERO, &"circle")
	if not error.is_empty():
		_fail("GPU undo edit rejected: " + String(error))
		return
	while preview.completed_patch_batches < 1 or preview.tick_pending:
		await process_frame
	var edited_sand: PackedFloat32Array = preview.shadow_domain.sand.duplicate()
	var edited_inventory: float = preview.shadow_domain.tool_inventory_m3
	if edited_inventory < 0.07 or initial_sand == edited_sand:
		_fail("GPU undo setup edit did not change sand/inventory")
		return
	var edited_cell := -1
	for i in edited_sand.size():
		if edited_sand[i] != initial_sand[i]:
			edited_cell = i
			break
	if edited_cell < 0:
		_fail("GPU undo edited cell unavailable")
		return
	if not await _verify_gpu_sand(edited_sand):
		return
	phase = "edit"
	if not await _verify_collision(edited_cell):
		return
	var undo_event := InputEventKey.new()
	undo_event.keycode = KEY_Z
	undo_event.pressed = true
	preview._unhandled_input(undo_event)
	while preview.completed_patch_batches < 2 or preview.tick_pending:
		await process_frame
	if preview.shadow_domain.sand != initial_sand or \
			absf(preview.shadow_domain.tool_inventory_m3 - initial_inventory) > 0.000001 or \
			preview.completed_ticks != initial_tick:
		_fail("GPU same-tick undo did not restore shadow state")
		return
	if not await _verify_gpu_sand(initial_sand):
		return
	phase = "undo"
	if not await _verify_collision(edited_cell):
		return
	# An accepted command can still be rejected when applied (insufficient
	# inventory). It must not erase the redo branch or touch GPU/collision.
	var rejected_patch_batches: int = preview.completed_patch_batches
	var rejected_revision: int = preview.solver.state_revision
	var rejected_error: StringName = preview._submit_brush(&"place_sand", 100.0,
		Vector3.ZERO, Vector3.ZERO, &"circle")
	if not rejected_error.is_empty() or not preview.command_queue.pending.is_empty() or \
			preview.command_queue.applied_log.size() != 0 or \
			preview.command_queue.redo_stack.size() != 1 or \
			preview.shadow_domain.sand != initial_sand or \
			absf(preview.shadow_domain.tool_inventory_m3 - initial_inventory) > 0.000001 or \
			preview.completed_patch_batches != rejected_patch_batches or \
			preview.solver.state_revision != rejected_revision:
		_fail("GPU rejected edit altered redo branch, state, or GPU revision")
		return
	if not await _verify_gpu_sand(initial_sand):
		return
	var redo_event := InputEventKey.new()
	redo_event.keycode = KEY_Y
	redo_event.pressed = true
	preview._unhandled_input(redo_event)
	while preview.completed_patch_batches < 3 or preview.tick_pending:
		await process_frame
	if preview.shadow_domain.sand != edited_sand or \
			absf(preview.shadow_domain.tool_inventory_m3 - edited_inventory) > 0.000001 or \
			preview.completed_ticks != initial_tick:
		_fail("GPU same-tick redo did not restore edit")
		return
	if not await _verify_gpu_sand(edited_sand):
		return
	phase = "redo"
	if not await _verify_collision(edited_cell):
		return
	preview.playing = true
	while preview.completed_ticks <= initial_tick:
		await process_frame
	preview.playing = false
	while preview.tick_pending:
		await process_frame
	if preview._undo_tool_command():
		_fail("GPU cross-tick undo falsely accepted without replay")
		return
	print("PASS: GPU paused same-tick Z/Y undo/redo sand+inventory+GPU texture+collision, insufficient-sand rejection preserves redo, cross-tick rejected tick=%d patch_batches=%d" % [
		preview.completed_ticks, preview.completed_patch_batches])
	finished = true
	preview.queue_free()
	quit(0)


func _verify_gpu_sand(expected: PackedFloat32Array) -> bool:
	readback = PackedByteArray()
	RenderingServer.call_on_render_thread(_render_read_sand)
	while readback.is_empty():
		if finished:
			return false
		await process_frame
	var actual := readback.to_float32_array()
	if actual.size() != expected.size():
		_fail("GPU undo readback size mismatch")
		return false
	var maximum := 0.0
	for i in actual.size():
		maximum = maxf(maximum, absf(actual[i] - expected[i]))
	if maximum > 0.000001:
		_fail("GPU undo texture mismatch: %.8f" % maximum)
		return false
	return true


func _verify_collision(cell_index: int) -> bool:
	var cell_x: int = cell_index % 256
	var cell_z: int = cell_index / 256
	var chunk_id: int = (cell_z / 32) * 8 + cell_x / 32
	var wait_started_ms := Time.get_ticks_msec()
	while int(preview.collision_proxy.applied_revisions.get(chunk_id, -1)) < \
			preview.solver.state_revision:
		if Time.get_ticks_msec() - wait_started_ms > 5000:
			_fail("GPU undo collision revision stalled phase=%s chunk=%d applied=%d target=%d pending=%s active=%d batches=%d invalid=%d" % [
				phase,
				chunk_id,
				int(preview.collision_proxy.applied_revisions.get(chunk_id, -1)),
				preview.solver.state_revision,
				str(preview.collision_proxy.pending_revisions),
				preview.collision_proxy.active_revision,
				preview.collision_proxy.completed_batches,
				preview.collision_proxy.invalid_readbacks])
			return false
		if preview.collision_proxy.invalid_readbacks > 0:
			_fail("GPU undo collision readback invalid")
			return false
		await process_frame
	await physics_frame
	await physics_frame
	var position := Vector3((float(cell_x) + 0.5) * 0.125 - 16.0, 0.0,
		(float(cell_z) + 0.5) * 0.125 - 16.0)
	var query := PhysicsRayQueryParameters3D.create(
		position + Vector3.UP * 10.0, position + Vector3.DOWN * 10.0)
	var hit: Dictionary = root.world_3d.direct_space_state.intersect_ray(query)
	if not hit.has("position"):
		_fail("GPU undo collision ray missed")
		return false
	var expected: float = preview.shadow_domain.bed_at(cell_index)
	if absf(hit.position.y - expected) > 0.125:
		_fail("GPU undo collision height mismatch: %.6f vs %.6f" % [
			hit.position.y, expected])
		return false
	return true


func _render_read_sand() -> void:
	var error: Error = preview.solver.request_data("sand", _on_sand)
	if error != OK:
		call_deferred("_fail", "GPU undo sand readback failed: %d" % error)


func _on_sand(data: PackedByteArray) -> void:
	call_deferred("_record_sand", data)


func _record_sand(data: PackedByteArray) -> void:
	if not finished:
		readback = data


func _watchdog() -> void:
	if finished:
		return
	if Time.get_ticks_msec() - started_ms > 90000:
		_fail("GPU undo probe timed out")
		return
	await process_frame
	call_deferred("_watchdog")


func _fail(message: String) -> void:
	if finished:
		return
	finished = true
	printerr("FAIL: " + message)
	if preview != null:
		preview.queue_free()
	quit(1)

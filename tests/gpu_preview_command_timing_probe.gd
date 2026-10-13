extends SceneTree

var preview: Node3D
var finished := false
var started_ms := 0


func _init() -> void:
	call_deferred("_begin")


func _begin() -> void:
	var scene: PackedScene = load("res://scenes/gpu_water_preview.tscn")
	if scene == null:
		_fail("preview scene unavailable")
		return
	preview = scene.instantiate()
	root.add_child(preview)
	started_ms = Time.get_ticks_msec()
	call_deferred("_watchdog")
	call_deferred("_check_ready")


func _check_ready() -> void:
	if finished:
		return
	if not preview.last_error.is_empty():
		_fail(preview.last_error)
		return
	if preview.completed_ticks < 3 or preview.tick_pending:
		await process_frame
		call_deferred("_check_ready")
		return
	preview.playing = false
	var tick: int = preview.completed_ticks
	if not _submit(Vector3.ZERO) or not preview.tick_pending:
		_fail("first paused patch was not dispatched")
		return
	if not _submit(Vector3(1.0, 0.0, 0.0)):
		_fail("second paused command rejected")
		return
	if preview.command_queue.pending.size() != 1 or \
			preview.command_queue.pending[0].sim_tick != tick:
		_fail("paused command received a future tick")
		return
	call_deferred("_check_paused_patches")


func _check_paused_patches() -> void:
	if finished:
		return
	if not preview.last_error.is_empty():
		_fail(preview.last_error)
		return
	if preview.completed_patch_batches < 2 or preview.tick_pending:
		await process_frame
		call_deferred("_check_paused_patches")
		return
	if preview.completed_ticks < 3 or preview.shadow_domain.tool_inventory_m3 < 0.035:
		_fail("paused patch queue did not drain")
		return
	preview.playing = true
	call_deferred("_check_water_tick")


func _check_water_tick() -> void:
	if finished:
		return
	if not preview.last_error.is_empty():
		_fail(preview.last_error)
		return
	if not preview.water_tick_in_flight:
		await process_frame
		call_deferred("_check_water_tick")
		return
	preview.playing = false
	var next_tick: int = preview.completed_ticks + 1
	if not _submit(Vector3(0.0, 0.0, 1.0)):
		_fail("in-flight water command rejected")
		return
	if preview.command_queue.pending.size() != 1 or \
			preview.command_queue.pending[0].sim_tick != next_tick:
		_fail("water tick command was not scheduled for next state")
		return
	call_deferred("_check_water_patch", next_tick)


func _check_water_patch(next_tick: int) -> void:
	if finished:
		return
	if not preview.last_error.is_empty():
		_fail(preview.last_error)
		return
	if preview.completed_ticks < next_tick or preview.completed_patch_batches < 3 or preview.tick_pending:
		await process_frame
		call_deferred("_check_water_patch", next_tick)
		return
	if not preview.command_queue.pending.is_empty() or \
			preview.shadow_domain.tool_inventory_m3 < 0.055:
		_fail("in-flight water command was not drained after completion")
		return
	print("PASS: GPU preview command timing paused_batches=%d water_tick=%d inventory=%.6f" % [
		preview.completed_patch_batches, next_tick, preview.shadow_domain.tool_inventory_m3])
	finished = true
	preview.queue_free()
	quit(0)


func _submit(position: Vector3) -> bool:
	return preview._submit_brush(&"remove_sand", 0.02,
		position, position, &"circle").is_empty()


func _watchdog() -> void:
	if finished:
		return
	if Time.get_ticks_msec() - started_ms > 90000:
		_fail("preview command timing timed out")
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

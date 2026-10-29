extends SceneTree

const TICKS_BEFORE_EDIT := 120
const TICKS_AFTER_EDIT := 30

var preview: Node3D
var finished := false
var started_ms := 0
var readbacks := {}
var stage := 0
var paused_patch_before := 0
var live_edit_submitted := false


func _init() -> void:
	call_deferred("_begin")


func _begin() -> void:
	var scene: PackedScene = load("res://scenes/gpu_water_preview.tscn")
	if scene == null:
		_fail("coupled preview scene unavailable")
		return
	preview = scene.instantiate()
	preview.enable_erosion = true
	preview.preset_index = 1
	preview.checkpoint_interval_ticks = 60
	root.add_child(preview)
	started_ms = Time.get_ticks_msec()
	call_deferred("_watchdog")
	call_deferred("_wait_initial_ticks")


func _wait_initial_ticks() -> void:
	if finished:
		return
	if not preview.last_error.is_empty():
		_fail(preview.last_error)
		return
	if not live_edit_submitted and preview.completed_ticks >= 70:
		var live_error: StringName = preview._submit_brush(&"remove_sand", 0.010,
			Vector3(1.0, 0.0, 0.0), Vector3(1.0, 0.0, 0.0), &"circle")
		if not live_error.is_empty():
			_fail("coupled live brush rejected: " + String(live_error))
			return
		live_edit_submitted = true
	if preview.completed_ticks < TICKS_BEFORE_EDIT:
		await process_frame
		call_deferred("_wait_initial_ticks")
		return
	preview.playing = false
	if preview.tick_pending or preview.audit_sand_revision < TICKS_BEFORE_EDIT or \
			preview.checkpoint_capture_pending or \
			preview.collision_proxy.pending_revisions.size() > 0 or \
			preview.collision_proxy.active_chunks.size() > 0:
		await process_frame
		call_deferred("_wait_initial_ticks")
		return
	if preview.shadow_revision != preview.solver.state_revision:
		if preview.debug_view != 14:
			preview._set_debug_view(14)
		await process_frame
		call_deferred("_wait_initial_ticks")
		return
	if preview.proxy_debug_shadow_stale:
		_fail("coupled collision debug stayed stale after shadow sync")
		return
	if preview.audit_sediment_m3 <= 0.001 or \
			preview.audit_sand_closure_m3 > 0.01 or \
			preview.audit_sand_negative_cells != 0 or preview.audit_sand_invalid_cells != 0 or \
			preview.shadow_domain.tool_inventory_m3 < 0.009 or \
			preview.dirty_summaries_checked < TICKS_BEFORE_EDIT or \
			preview.nonzero_dirty_summary_ticks < 1 or preview.max_gpu_dirty_um < 1:
		_fail("coupled preview sand account did not evolve/close")
		return
	preview._set_debug_view(14)
	stage = 1
	_request_state()


func _request_state() -> void:
	readbacks.clear()
	RenderingServer.call_on_render_thread(_render_request_state)


func _render_request_state() -> void:
	for field in ["sand", "sediment"]:
		var error: Error = preview.solver.request_data(field, _on_data.bind(field))
		if error != OK:
			call_deferred("_fail", "coupled preview readback failed: %s %d" % [field, error])
			return


func _on_data(data: PackedByteArray, field: String) -> void:
	call_deferred("_record_data", data, field)


func _record_data(data: PackedByteArray, field: String) -> void:
	if finished:
		return
	readbacks[field] = data.to_float32_array()
	if readbacks.size() == 2:
		_verify_state()


func _verify_state() -> void:
	var max_sand_error := 0.0
	var max_sediment_error := 0.0
	for i in 256 * 256:
		max_sand_error = maxf(max_sand_error,
			absf(readbacks["sand"][i] - preview.shadow_domain.sand[i]))
		max_sediment_error = maxf(max_sediment_error,
			absf(readbacks["sediment"][i] - preview.shadow_domain.sediment[i]))
	if max_sand_error > 0.0000001 or max_sediment_error > 0.0000001:
		_fail("GPU/CPU coupled shadow mismatch: %.9f/%.9f" % [
			max_sand_error, max_sediment_error])
		return
	if stage == 1:
		if preview.checkpoints.is_empty() or \
				preview.checkpoints.back().tick != preview.completed_ticks:
			_fail("coupled checkpoint did not capture completed tick")
			return
		var checkpoint: Dictionary = preview.checkpoints.back()
		if checkpoint.fields.size() != 3 or \
				checkpoint.shadow["sand"] != readbacks["sand"] or \
				checkpoint.shadow["sediment"] != readbacks["sediment"]:
			_fail("coupled checkpoint sand/sediment differ from GPU authority")
			return
		var max_collision_error := _collision_error()
		if max_collision_error > 0.003 or preview.collision_proxy.invalid_readbacks != 0:
			_fail("coupled collision proxy differs from bed: %.6f invalid=%d" % [
				max_collision_error, preview.collision_proxy.invalid_readbacks])
			return
		paused_patch_before = preview.completed_patch_batches
		var error: StringName = preview._submit_brush(&"place_sand", 0.005,
			Vector3.ZERO, Vector3.ZERO, &"circle")
		if not error.is_empty():
			_fail("coupled paused brush rejected: " + String(error))
			return
		call_deferred("_wait_paused_edit")
	elif stage == 2:
		preview.playing = true
		call_deferred("_wait_after_edit")
	else:
		if preview.audit_sand_closure_m3 > 0.01 or \
				preview.audit_sand_invalid_cells != 0 or preview.audit_sand_negative_cells != 0 or \
				_collision_error() > 0.003 or preview.full_shadow_syncs > 6 or \
				preview.dirty_summary_bytes != preview.completed_ticks * 256:
			_fail("coupled account failed after tool and resumed water")
			return
		print("PASS: GPU coupled preview 256-square ticks=%d suspended=%.6f sand_closure=%.9f shadow_errors=%.9f/%.9f collision_error=%.6f inventory=%.6f dirty_summaries=%d nonzero_ticks=%d max_dirty_um=%d full_syncs=%d full_bytes=%d sand_only_syncs=%d sand_only_bytes=%d dirty_bytes=%d" % [
			preview.completed_ticks, preview.audit_sediment_m3,
			preview.audit_sand_closure_m3, max_sand_error, max_sediment_error,
			_collision_error(), preview.shadow_domain.tool_inventory_m3,
			preview.dirty_summaries_checked,
			preview.nonzero_dirty_summary_ticks, preview.max_gpu_dirty_um,
			preview.full_shadow_syncs, preview.full_shadow_bytes,
			preview.sand_only_syncs, preview.sand_only_bytes,
			preview.dirty_summary_bytes])
		_finish(0)


func _collision_error() -> float:
	var max_error := 0.0
	for chunk_id in 64:
		var node: CollisionShape3D = preview.collision_proxy.shapes.get(chunk_id)
		if node == null or not (node.shape is HeightMapShape3D):
			return INF
		var values: PackedFloat32Array = node.shape.map_data
		for local_z in 33:
			for local_x in 33:
				var x: int = mini(chunk_id % 8 * 32 + local_x, 255)
				var z: int = mini(chunk_id / 8 * 32 + local_z, 255)
				var i: int = z * 256 + x
				max_error = maxf(max_error, absf(values[local_z * 33 + local_x] -
					preview.shadow_domain.rock[i] - preview.shadow_domain.sand[i]))
	return max_error


func _wait_paused_edit() -> void:
	if finished:
		return
	if not preview.last_error.is_empty():
		_fail(preview.last_error)
		return
	if preview.completed_patch_batches <= paused_patch_before or preview.tick_pending:
		await process_frame
		call_deferred("_wait_paused_edit")
		return
	stage = 2
	_request_state()


func _wait_after_edit() -> void:
	if finished:
		return
	if not preview.last_error.is_empty():
		_fail(preview.last_error)
		return
	if preview.completed_ticks < TICKS_BEFORE_EDIT + TICKS_AFTER_EDIT:
		await process_frame
		call_deferred("_wait_after_edit")
		return
	preview.playing = false
	if preview.tick_pending or preview.audit_sand_revision < TICKS_BEFORE_EDIT + TICKS_AFTER_EDIT or \
			preview.collision_proxy.pending_revisions.size() > 0 or \
			preview.collision_proxy.active_chunks.size() > 0:
		await process_frame
		call_deferred("_wait_after_edit")
		return
	if preview.shadow_revision != preview.solver.state_revision:
		await process_frame
		call_deferred("_wait_after_edit")
		return
	if preview.proxy_debug_shadow_stale:
		_fail("coupled collision debug stayed stale after resumed shadow sync")
		return
	stage = 3
	_request_state()


func _watchdog() -> void:
	if finished:
		return
	if Time.get_ticks_msec() - started_ms > 120000:
		_fail("coupled preview probe timed out at tick %d" % preview.completed_ticks)
		return
	await process_frame
	call_deferred("_watchdog")


func _fail(message: String) -> void:
	if finished:
		return
	printerr("FAIL: " + message)
	_finish(1)


func _finish(code: int) -> void:
	finished = true
	if preview != null:
		preview.queue_free()
	for frame in 3:
		await process_frame
	quit(code)

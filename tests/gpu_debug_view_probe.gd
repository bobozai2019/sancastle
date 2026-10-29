extends SceneTree

var preview: Node3D
var started_ms := 0
var finished := false
var baseline: Image
var mode := 0
var changed_counts := PackedInt32Array()
var flux_ready := false
var flux_positive_cells := 0
var flux_max := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var obstacle_ready := false
var obstacle_updated := false
var chunk_prepared := false
var collision_perturbed := false


func _init() -> void:
	call_deferred("_begin")


func _begin() -> void:
	var scene: PackedScene = load("res://scenes/gpu_water_preview.tscn")
	if scene == null:
		_fail("GPU debug scene unavailable")
		return
	preview = scene.instantiate()
	root.add_child(preview)
	started_ms = Time.get_ticks_msec()
	call_deferred("_watchdog")
	call_deferred("_wait_for_audit")


func _wait_for_audit() -> void:
	if finished:
		return
	if not preview.last_error.is_empty():
		_fail(preview.last_error)
		return
	if preview.completed_ticks < 31 or preview.tick_pending or preview.audit_revision < 30 or \
			preview.audit_sand_revision < 30:
		await process_frame
		call_deferred("_wait_for_audit")
		return
	preview.playing = false
	if preview.audit_invalid_cells != 0 or preview.audit_negative_cells != 0 or \
			not is_finite(preview.audit_water_m3) or preview.audit_water_m3 <= 0.0:
		_fail("GPU debug audit counters invalid")
		return
	if preview.audit_sand_invalid_cells != 0 or preview.audit_sand_negative_cells != 0 or \
			preview.audit_sand_m3 <= 0.0 or absf(preview.audit_sediment_m3) > 0.000001 or \
			preview.audit_sand_closure_m3 > 0.001:
		_fail("GPU sand audit counters invalid")
		return
	if preview.flux_texture.texture_rd_rid != preview.solver.current_texture("flux") or \
			preview.sediment_texture.texture_rd_rid != preview.solver.current_texture("sediment") or \
			preview.obstacle_texture.texture_rd_rid != preview.solver.current_texture("obstacle"):
		_fail("GPU debug textures are not current solver authority")
		return
	RenderingServer.call_on_render_thread(_request_flux)
	while not flux_ready:
		await process_frame
	if flux_positive_cells == 0:
		_fail("GPU flux debug source contains no moving-water sample")
		return
	for channel in 4:
		if flux_max[channel] <= 0.000001:
			_fail("GPU flux debug channel %d has no moving-water sample" % channel)
			return
	var obstacle_values: PackedFloat32Array = preview.shadow_domain.obstacle.duplicate()
	for z in range(96, 160):
		for x in range(96, 160):
			obstacle_values[z * 256 + x] = 1.0
	preview.shadow_domain.obstacle = obstacle_values
	RenderingServer.call_on_render_thread(_update_obstacle.bind(obstacle_values))
	while not obstacle_ready:
		await process_frame
	if not obstacle_updated:
		_fail("GPU debug obstacle update failed")
		return
	for frame in 3:
		await process_frame
	baseline = root.get_texture().get_image()
	if baseline == null or baseline.is_empty():
		_fail("GPU debug baseline screenshot unavailable")
		return
	mode = 1
	call_deferred("_next_mode")


func _request_flux() -> void:
	var error: Error = preview.solver.request_data("flux", _on_flux)
	if error != OK:
		call_deferred("_fail", "GPU debug flux readback request failed: %d" % error)


func _on_flux(data: PackedByteArray) -> void:
	call_deferred("_record_flux", data)


func _record_flux(data: PackedByteArray) -> void:
	if finished:
		return
	var values := data.to_float32_array()
	if values.size() != 256 * 256 * 4:
		_fail("GPU debug flux size mismatch")
		return
	for i in values.size():
		var value: float = values[i]
		if not is_finite(value) or value < -0.000001:
			_fail("GPU debug flux has invalid value")
			return
		flux_max[i % 4] = maxf(flux_max[i % 4], value)
		if value > 0.000001:
			flux_positive_cells += 1
	flux_ready = true


func _update_obstacle(values: PackedFloat32Array) -> void:
	var updated: bool = preview.solver.update_obstacles(values)
	call_deferred("_record_obstacle_update", updated)


func _record_obstacle_update(updated: bool) -> void:
	obstacle_updated = updated
	obstacle_ready = true


func _next_mode() -> void:
	if finished:
		return
	if mode > 14:
		print("PASS: GPU debug views 1..14 changed rendered terrain, positive_flux_samples=%d flux_max=%s obstacle_updated=%s dirty_chunks=%d collision_error=%.6f audit revision=%d water=%.6f sand_revision=%d sand_total=%.6f sand_closure=%.8f invalid=%d negative=%d changed_samples=%s" % [
			flux_positive_cells, str(flux_max), str(obstacle_updated),
			preview.last_dirty_chunks.size(), preview.proxy_debug_max_error_m,
			preview.audit_revision, preview.audit_water_m3,
			preview.audit_sand_revision, preview.audit_sand_total_m3,
			preview.audit_sand_closure_m3,
			preview.audit_invalid_cells, preview.audit_negative_cells,
			str(changed_counts)])
		finished = true
		preview.queue_free()
		quit(0)
		return
	if mode == 13 and not chunk_prepared:
		await _prepare_chunk_modes()
		if finished:
			return
	if mode == 14 and not collision_perturbed:
		var node: CollisionShape3D = preview.collision_proxy.shapes.get(27)
		if node == null:
			_fail("GPU collision debug target chunk missing")
			return
		var heights: PackedFloat32Array = node.shape.map_data
		for i in heights.size():
			heights[i] += 0.03
		node.shape.map_data = heights
		collision_perturbed = true
	var event := InputEventKey.new()
	event.keycode = KEY_V
	event.pressed = true
	preview._unhandled_input(event)
	if preview.debug_view != mode:
		_fail("GPU debug V key mode mismatch")
		return
	for frame in 3:
		await process_frame
	var actual := root.get_texture().get_image()
	var changed := 0
	for y in range(130, mini(baseline.get_height(), actual.get_height()), 8):
		for x in range(100, mini(baseline.get_width(), actual.get_width()), 8):
			var before := baseline.get_pixel(x, y)
			var after := actual.get_pixel(x, y)
			if absf(before.r - after.r) + absf(before.g - after.g) + \
					absf(before.b - after.b) > 0.06:
				changed += 1
	if changed < 50:
		_fail("GPU debug mode %d did not change terrain pixels: %d" % [mode, changed])
		return
	if mode == 8:
		var blocked_pixels := 0
		for y in range(200, mini(actual.get_height(), 560), 4):
			for x in range(380, mini(actual.get_width(), 900), 4):
				var pixel := actual.get_pixel(x, y)
				if pixel.r > 0.6 and pixel.r > pixel.g * 1.6 and pixel.r > pixel.b * 1.6:
					blocked_pixels += 1
		if blocked_pixels < 50:
			_fail("GPU obstacle debug mode did not show updated blocked cells: %d center=%s" % [
				blocked_pixels, str(actual.get_pixel(640, 360))])
			return
	if mode == 13 and preview.last_dirty_chunks.is_empty():
		_fail("GPU dirty-chunk view has no recent edited chunk")
		return
	if mode == 14 and (preview.proxy_debug_missing_chunks != 0 or \
			preview.proxy_debug_max_error_m < 0.02):
		_fail("GPU collision-difference view missed injected shape error")
		return
	changed_counts.append(changed)
	if mode in [2, 3, 8, 9, 10, 11, 12, 13, 14]:
		var path := "res://test_output/sandcastle_water_sand_coupling/验收/GPU_debug_mode_%d_20260928.png" % mode
		if actual.save_png(path) != OK:
			_fail("GPU debug screenshot save failed")
			return
	mode += 1
	call_deferred("_next_mode")


func _prepare_chunk_modes() -> void:
	while preview.collision_proxy.shapes.size() < 64 or \
			not preview.collision_proxy.pending_revisions.is_empty() or \
			not preview.collision_proxy.active_chunks.is_empty():
		await process_frame
	var prior_batches: int = preview.completed_patch_batches
	var prior_sand_revision: int = preview.audit_sand_revision
	var error: StringName = preview._submit_brush(&"debug_add_sand", 0.015,
		Vector3.ZERO, Vector3.ZERO, &"circle")
	if not error.is_empty():
		_fail("GPU dirty-chunk setup edit rejected: " + String(error))
		return
	var command_id: int = preview.command_id
	while preview.completed_patch_batches <= prior_batches or \
			not _collision_ready_for_tool(command_id) or \
			preview.audit_sand_revision <= prior_sand_revision or \
			not preview.collision_proxy.pending_revisions.is_empty() or \
			not preview.collision_proxy.active_chunks.is_empty():
		await process_frame
	if preview.shadow_domain.sand_source_m3 <= 0.0 or \
			preview.audit_sand_closure_m3 > 0.001 or \
			preview.audit_sand_negative_cells != 0 or preview.audit_sand_invalid_cells != 0:
		_fail("GPU sand audit did not close after paused tool edit")
		return
	chunk_prepared = true


func _collision_ready_for_tool(command_id: int) -> bool:
	if not preview.tool_revision_by_command_id.has(command_id):
		return false
	var revision: int = preview.tool_revision_by_command_id[command_id]
	if preview.last_dirty_chunks.is_empty():
		return false
	for chunk_id in preview.last_dirty_chunks:
		if int(preview.collision_proxy.applied_revisions.get(chunk_id, -1)) < revision:
			return false
	return true


func _watchdog() -> void:
	if finished:
		return
	if Time.get_ticks_msec() - started_ms > 90000:
		_fail("GPU debug probe timed out")
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

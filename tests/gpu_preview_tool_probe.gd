extends SceneTree

var preview: Node3D
var before_image: Image
var finished := false
var started_ms := 0
var edit_submitted_usec := 0
var collision_error := 0.0
var edit_to_apply_ms := 0.0
var edit_to_ray_ms := 0.0


func _init() -> void:
	call_deferred("_begin")


func _begin() -> void:
	var scene: PackedScene = load("res://scenes/gpu_water_preview.tscn")
	if scene == null:
		_fail("GPU preview scene unavailable")
		return
	preview = scene.instantiate()
	root.add_child(preview)
	started_ms = Time.get_ticks_msec()
	call_deferred("_watchdog")
	call_deferred("_wait_for_ticks")


func _wait_for_ticks() -> void:
	if finished:
		return
	if not preview.last_error.is_empty():
		_fail(preview.last_error)
		return
	if preview.completed_ticks < 3 or preview.tick_pending:
		await process_frame
		call_deferred("_wait_for_ticks")
		return
	preview.playing = false
	for frame in 3:
		await process_frame
	before_image = root.get_texture().get_image()
	if before_image == null or before_image.is_empty():
		_fail("GPU preview before image missing")
		return
	edit_submitted_usec = Time.get_ticks_usec()
	var error: StringName = preview._submit_brush(&"remove_sand", 0.08,
		Vector3.ZERO, Vector3.ZERO, &"circle")
	if not error.is_empty():
		_fail("GPU preview brush rejected: " + String(error))
		return
	call_deferred("_wait_for_patch")


func _wait_for_patch() -> void:
	if finished:
		return
	if not preview.last_error.is_empty():
		_fail(preview.last_error)
		return
	if preview.completed_patch_batches < 1 or preview.tick_pending:
		await process_frame
		call_deferred("_wait_for_patch")
		return
	if preview.shadow_domain.tool_inventory_m3 < 0.07 or preview.last_dirty_cells < 5:
		_fail("GPU preview brush did not remove expected sand")
		return
	call_deferred("_wait_for_collision")


func _render_read_sand() -> void:
	var error: Error = preview.solver.request_data("sand", _on_sand)
	if error != OK:
		call_deferred("_fail", "GPU preview sand readback failed: %d" % error)


func _on_sand(data: PackedByteArray) -> void:
	call_deferred("_verify_sand", data)


func _verify_sand(data: PackedByteArray) -> void:
	if finished:
		return
	var actual := data.to_float32_array()
	var domain: SandWaterDomain = preview.shadow_domain
	if actual.size() != domain.sand.size() or \
			preview.sand_texture.texture_rd_rid != preview.solver.current_texture("sand"):
		_fail("GPU preview sand state/version mismatch")
		return
	var max_error := 0.0
	for i in actual.size():
		max_error = maxf(max_error, absf(actual[i] - domain.sand[i]))
	if max_error > 0.000001:
		_fail("GPU preview sand differs from command queue: %.8f" % max_error)
		return
	for frame in 2:
		await process_frame
	var after_image := root.get_texture().get_image()
	var changed_pixels := 0
	for y in range(130, mini(before_image.get_height(), after_image.get_height()), 2):
		for x in range(100, mini(before_image.get_width(), after_image.get_width()), 2):
			var before := before_image.get_pixel(x, y)
			var after := after_image.get_pixel(x, y)
			if absf(before.r - after.r) + absf(before.g - after.g) + absf(before.b - after.b) > 0.03:
				changed_pixels += 1
	if changed_pixels < 5:
		_fail("GPU preview edit was not visible outside HUD: changed=%d" % changed_pixels)
		return
	var path := "res://test_output/sandcastle_water_sand_coupling/验收/GPU_tool_edit_20260928.png"
	if after_image.save_png(path) != OK:
		_fail("GPU preview tool screenshot save failed")
		return
	print("PASS: GPU preview paused tool edit dirty_cells=%d inventory=%.6f max_sand_error=%.8f changed_pixels=%d screenshot=%s" % [
		preview.last_dirty_cells, preview.shadow_domain.tool_inventory_m3,
		max_error, changed_pixels, path])
	print("PASS: GPU tool collision from CPU shadow chunk=36 height_error=%.6f seam_hit=true edit_to_apply_ms=%.3f edit_to_ray_ms=%.3f" % [
		collision_error, edit_to_apply_ms, edit_to_ray_ms])
	finished = true
	preview.queue_free()
	quit(0)


func _wait_for_collision() -> void:
	if finished:
		return
	if preview.collision_proxy.invalid_readbacks > 0:
		_fail("GPU collision proxy reported an invalid readback")
		return
	var chunk_id := 4 * 8 + 4
	if int(preview.collision_proxy.applied_revisions.get(chunk_id, -1)) < preview.solver.state_revision:
		await process_frame
		call_deferred("_wait_for_collision")
		return
	await physics_frame
	await physics_frame
	var position := Vector3(0.1875, 0.0, 0.1875)
	var query := PhysicsRayQueryParameters3D.create(
		position + Vector3.UP * 10.0, position + Vector3.DOWN * 10.0)
	var hit: Dictionary = root.world_3d.direct_space_state.intersect_ray(query)
	if not hit.has("position"):
		_fail("GPU collision proxy ray missed edited terrain")
		return
	var expected: float = preview.shadow_domain.bed_at(preview.shadow_domain.index(129, 129))
	collision_error = absf(hit.position.y - expected)
	var seam_query := PhysicsRayQueryParameters3D.create(
		Vector3(0.0, 10.0, 0.1875), Vector3(0.0, -10.0, 0.1875))
	var seam_hit: Dictionary = root.world_3d.direct_space_state.intersect_ray(seam_query)
	if not seam_hit.has("position"):
		_fail("GPU collision proxy has a gap at the 32-cell chunk seam")
		return
	if collision_error > 0.125:
		var node: CollisionShape3D = preview.collision_proxy.shapes[chunk_id]
		var values: PackedFloat32Array = node.shape.map_data
		_fail("GPU collision height differs from edited bed: error=%.6f hit=%.6f expected=%.6f node=%s samples=%.6f,%.6f,%.6f,%.6f" % [
			collision_error, hit.position.y, expected, str(node.position),
			values[1 + 1 * 33], values[2 + 1 * 33],
			values[1 + 2 * 33], values[2 + 2 * 33]])
		return
	edit_to_ray_ms = float(Time.get_ticks_usec() - edit_submitted_usec) / 1000.0
	edit_to_apply_ms = float(int(preview.collision_proxy.applied_usec[chunk_id]) -
		edit_submitted_usec) / 1000.0
	if edit_to_ray_ms > 100.0:
		_fail("GPU collision edited ray exceeded 100 ms: %.3f" % edit_to_ray_ms)
		return
	RenderingServer.call_on_render_thread(_render_read_sand)


func _watchdog() -> void:
	if finished:
		return
	if Time.get_ticks_msec() - started_ms > 90000:
		_fail("GPU preview tool probe timed out")
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

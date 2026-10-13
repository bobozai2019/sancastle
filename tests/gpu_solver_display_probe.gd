extends SceneTree

var preview: Node3D
var finished := false
var watchdog_started_ms := 0


func _init() -> void:
	call_deferred("_begin")


func _begin() -> void:
	var scene: PackedScene = load("res://scenes/gpu_water_preview.tscn")
	if scene == null:
		_fail("GPU preview scene missing")
		return
	preview = scene.instantiate()
	root.add_child(preview)
	watchdog_started_ms = Time.get_ticks_msec()
	call_deferred("_watchdog")
	call_deferred("_wait_for_ticks")


func _wait_for_ticks() -> void:
	if finished:
		return
	if not preview.last_error.is_empty():
		_fail("GPU preview error: " + preview.last_error)
		return
	if preview.completed_ticks < 3 or preview.tick_pending:
		await process_frame
		call_deferred("_wait_for_ticks")
		return
	preview.playing = false
	for frame in 6:
		await process_frame
	if finished:
		return
	if not preview.rock_texture.texture_rd_rid.is_valid() or \
			preview.sand_texture.texture_rd_rid != preview.solver.current_texture("sand") or \
			preview.wetness_texture.texture_rd_rid != preview.solver.current_texture("wetness") or \
			preview.water_texture.texture_rd_rid != preview.solver.current_texture("water"):
		_fail("GPU preview material texture version differs from completed solver state")
		return
	var screenshot := root.get_texture().get_image()
	if screenshot == null or screenshot.is_empty():
		_fail("GPU preview screenshot unavailable")
		return
	var sand_pixels := 0
	var water_pixels := 0
	for y in range(0, screenshot.get_height(), 4):
		for x in range(0, screenshot.get_width(), 4):
			var color := screenshot.get_pixel(x, y)
			if color.r > 0.25 and color.r > color.b * 1.3 and color.g > 0.20:
				sand_pixels += 1
			if color.b > color.r * 1.3 and color.g > color.r * 1.4 and color.b < 0.85:
				water_pixels += 1
	if sand_pixels < 100 or water_pixels < 100:
		_fail("GPU preview missed terrain or water pixels: sand=%d water=%d" % [
			sand_pixels, water_pixels])
		return
	var path := "res://test_output/sandcastle_water_sand_coupling/验收/GPU_solver_display_20260928.png"
	if screenshot.save_png(path) != OK:
		_fail("GPU preview screenshot save failed")
		return
	print("PASS: GPU solver Texture2DRD terrain/water display ticks=%d sand_pixels=%d water_pixels=%d screenshot=%s" % [
		preview.completed_ticks, sand_pixels, water_pixels, path])
	finished = true
	preview.queue_free()
	quit(0)


func _watchdog() -> void:
	if finished:
		return
	if Time.get_ticks_msec() - watchdog_started_ms > 90000:
		_fail("GPU preview scene timed out")
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

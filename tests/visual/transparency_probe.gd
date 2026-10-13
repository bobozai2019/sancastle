extends SceneTree

## T07 G04 (part): low-angle water transparency regression.
##
## The water surface is a full-domain displaced mesh drawn with `blend_mix` and
## `depth_draw_never`, and its alpha now varies with depth (0.55 shallow to 0.94
## deep). That combination can leave gaps at a grazing angle, where the surface is
## nearly edge-on and the bed shows through as a bare-sand patch - the
## acceptance's "露沙蓝片 / 低视角分离".
##
## The check renders the same low camera three times:
##   * the depth debug view, which draws the terrain coloured by depth and so
##     yields a per-pixel map of where water is
##   * the normal view with the water mesh on
##   * the normal view with the water mesh hidden
##
## Any pixel that the depth view says is under meaningful water, but where the two
## normal renders are identical, is a place the water failed to cover. It counts
## those, and also counts sand-coloured pixels that survived inside the wet mask.

const STILL_DIR := "res://test_output/sandcastle_water_sand_coupling/验收/"
## Grazing view along the channel, roughly a player's eye height at the waterline.
const CAMERA_POSITION := Vector3(-13.5, 0.95, 0.8)
const CAMERA_TARGET := Vector3(7.0, 0.15, 0.1)
const DEPTH_MASK_M := 0.05
const DIFFERENCE_EPSILON := 0.02
const PIXEL_STEP := 2

var preview: Node3D
var finished := false
var started_ms := 0
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_begin")


func _begin() -> void:
	started_ms = Time.get_ticks_msec()
	var scene: PackedScene = load("res://scenes/gpu_water_preview.tscn")
	if scene == null:
		_fail("preview scene unavailable")
		return
	preview = scene.instantiate()
	preview.preset_index = 1
	preview.enable_erosion = true
	preview.hide_hud = true
	preview.use_player_camera = true
	preview.player_camera_position = CAMERA_POSITION
	preview.player_camera_target = CAMERA_TARGET
	root.add_child(preview)
	call_deferred("_watchdog")
	call_deferred("_wait_ready")


func _wait_ready() -> void:
	while not finished:
		if not preview.last_error.is_empty():
			_fail(preview.last_error)
			return
		if preview.ready_for_ticks and preview.completed_ticks >= 300:
			break
		await process_frame
	if finished:
		return
	preview.playing = false
	var waited := 0
	while not finished and preview.tick_pending and waited < 600:
		await process_frame
		waited += 1
	await _verify()


func _verify() -> void:
	## 1. Depth view: the terrain is drawn coloured by depth, giving the wet mask.
	preview._set_debug_view(2)
	var depth_image := await _capture()
	## 2. Normal view with the water surface drawn.
	preview._set_debug_view(0)
	var with_water := await _capture()
	## 3. Normal view with the water surface hidden.
	var water_mesh: MeshInstance3D = preview.get_node_or_null("GpuWaterSurface")
	if water_mesh == null:
		_fail("water surface node missing")
		return
	water_mesh.visible = false
	var without_water := await _capture()
	water_mesh.visible = true
	if depth_image.is_empty() or with_water.is_empty() or without_water.is_empty():
		return

	## Classify by the depth view's own palette. It runs dark (0.12,0.12,0.12)
	## where dry to blue (0.05,0.62,0.95) at depth, and the sky is a pale blue
	## (0.73,0.86,0.93) that is also blue-dominant - so the mask also has to
	## reject the sky, which the low red channel does.
	var masked := 0
	var uncovered := 0
	var sand_inside := 0
	for y in range(0, depth_image.get_height(), PIXEL_STEP):
		for x in range(0, depth_image.get_width(), PIXEL_STEP):
			var depth_color := depth_image.get_pixel(x, y)
			if depth_color.r > 0.45 or depth_color.b <= depth_color.r + 0.12:
				continue
			masked += 1
			var normal_color := with_water.get_pixel(x, y)
			var bare_color := without_water.get_pixel(x, y)
			var difference := absf(normal_color.r - bare_color.r) + \
				absf(normal_color.g - bare_color.g) + \
				absf(normal_color.b - bare_color.b)
			if difference <= DIFFERENCE_EPSILON:
				uncovered += 1
			## Sand reads warm (red over blue); water never does.
			elif normal_color.r > normal_color.b + 0.10:
				sand_inside += 1
	var uncovered_fraction := float(uncovered) / maxf(float(masked), 1.0)
	var sand_fraction := float(sand_inside) / maxf(float(masked), 1.0)
	await _save(with_water, "T07_lowangle_water_20260929.png")
	await _save(depth_image, "T07_lowangle_depthmask_20260929.png")
	if masked < 1000:
		failures.append("wet mask too small to judge: %d pixels" % masked)
	elif uncovered_fraction > 0.02:
		failures.append("%.3f%% of wet pixels show no water at a grazing angle (%d of %d)" % [
			100.0 * uncovered_fraction, uncovered, masked])
	elif sand_fraction > 0.02:
		failures.append("%.3f%% of wet pixels read as bare sand (%d of %d)" % [
			100.0 * sand_fraction, sand_inside, masked])
	else:
		print("PASS: T07 low-angle transparency wet_px=%d uncovered_px=%d uncovered=%.5f%% " % [
			masked, uncovered, 100.0 * uncovered_fraction] +
			"sand_px=%d sand=%.5f%% depth_mask_m=%.2f" % [
				sand_inside, 100.0 * sand_fraction, DEPTH_MASK_M])
	_finish(0 if failures.is_empty() else 1)


func _capture() -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	if finished:
		return Image.new()
	return root.get_texture().get_image()


func _save(image: Image, name: String) -> void:
	if image.is_empty():
		return
	var error: Error = image.save_png(STILL_DIR + name)
	if error != OK:
		_fail("still save failed for %s: %d" % [name, error])


func _watchdog() -> void:
	while not finished:
		if Time.get_ticks_msec() - started_ms > 600000:
			_fail("transparency probe timed out")
			return
		await process_frame


func _fail(message: String) -> void:
	if finished:
		return
	printerr("FAIL: " + message)
	_finish(1)


func _finish(code: int) -> void:
	if not failures.is_empty():
		for failure in failures:
			printerr("FAIL: " + failure)
	finished = true
	if preview != null:
		preview.queue_free()
	for _frame in 3:
		await process_frame
	quit(code)

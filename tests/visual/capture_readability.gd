extends SceneTree

## T07 G01/G03 evidence. Runs the 256² coupled main entry to a chosen tick and
## captures the normal view (debug colouring off) from the player camera and from
## the fixed overview camera.
##
## The player-camera still is deliberately the same camera, preset and tick as
## `验收/T05_material_0_20260929.png`, which was captured with the pre-T07
## shaders, so the pair is a fixed-camera before/after comparison.
##
## Usage:
##   godot --path <proj> --rendering-driver d3d12 --resolution 1280x720 \
##     --script <this> -- [--tick N]

const STILL_DIR := "res://test_output/sandcastle_water_sand_coupling/验收/"
const CAMERA_POSITION := Vector3(1.0, 5.5, 8.5)
const CAMERA_TARGET := Vector3(3.0, 0.05, -1.0)

var main: Node3D
var finished := false
var started_ms := 0
var capture_tick := 600
var stills: Array[String] = []


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		if args[i] == "--tick":
			capture_tick = int(args[i + 1])
			i += 2
		else:
			i += 1
	call_deferred("_watchdog")
	call_deferred("_begin")


func _scene() -> Node3D:
	return main.active_scene if main != null else null


func _begin() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	if scene == null:
		_fail("main scene unavailable")
		return
	main = scene.instantiate()
	main.selected_preset = 1
	main.enable_gpu_erosion = true
	main.hide_hud = true
	main.show_brush_indicator = false
	main.use_player_camera = true
	main.player_camera_position = CAMERA_POSITION
	main.player_camera_target = CAMERA_TARGET
	root.add_child(main)
	started_ms = Time.get_ticks_msec()

	while not finished:
		var preview := _scene()
		if preview != null and not preview.last_error.is_empty():
			_fail(preview.last_error)
			return
		if preview != null and preview.ready_for_ticks and \
				preview.completed_ticks >= capture_tick:
			break
		await process_frame
	if finished:
		return
	var preview := _scene()
	preview.playing = false
	var waited := 0
	while not finished and preview.tick_pending and waited < 600:
		await process_frame
		waited += 1
	preview._set_debug_view(0)
	_report_flow(preview)
	if not await _still("T07_readability_player_20260929.png"):
		return
	preview.set_player_camera(false)
	if not await _still("T07_readability_overview_20260929.png"):
		return
	print("PASS: T07 readability stills tick=%d files=%s" % [
		preview.completed_ticks, ",".join(stills)])
	_finish(0)


## Prints the depth and depth-averaged speed distribution so the water shader's
## depth cue and foam thresholds can be set from measurements, not guesses.
func _report_flow(preview: Node3D) -> void:
	var depth := _read(preview, "water")
	var qx := _read(preview, "momentum_x")
	var qz := _read(preview, "momentum_z")
	if depth.is_empty() or qx.is_empty() or qz.is_empty():
		return
	var speeds: Array[float] = []
	var max_depth := 0.0
	var wet := 0
	for i in depth.size():
		if depth[i] <= 0.001:
			continue
		wet += 1
		max_depth = maxf(max_depth, depth[i])
		speeds.append(Vector2(qx[i], qz[i]).length() / maxf(depth[i], 0.001))
	speeds.sort()
	if speeds.is_empty():
		print("FLOW wet=0")
		return
	print("FLOW wet_cells=%d max_depth_m=%.4f speed_p50=%.4f speed_p90=%.4f speed_p99=%.4f speed_max=%.4f" % [
		wet, max_depth, speeds[speeds.size() / 2], speeds[speeds.size() * 9 / 10],
		speeds[mini(speeds.size() * 99 / 100, speeds.size() - 1)], speeds[-1]])


func _read(preview: Node3D, field: String) -> PackedFloat32Array:
	var rid: RID = preview.solver.current_texture(field)
	if not rid.is_valid():
		return PackedFloat32Array()
	var data: PackedByteArray = RenderingServer.get_rendering_device().texture_get_data(rid, 0)
	if data.size() != 256 * 256 * 4:
		return PackedFloat32Array()
	return data.to_float32_array()


func _still(name: String) -> bool:
	await process_frame
	await RenderingServer.frame_post_draw
	if finished:
		return false
	var error: Error = root.get_texture().get_image().save_png(STILL_DIR + name)
	if error != OK:
		_fail("still save failed for %s: %d" % [name, error])
		return false
	stills.append(name)
	return true


func _watchdog() -> void:
	while not finished:
		if Time.get_ticks_msec() - started_ms > 600000:
			_fail("readability capture timed out")
			return
		await process_frame


func _fail(message: String) -> void:
	if finished:
		return
	printerr("FAIL: " + message)
	_finish(1)


func _finish(code: int) -> void:
	finished = true
	if main != null:
		main.queue_free()
	for _frame in 3:
		await process_frame
	quit(code)

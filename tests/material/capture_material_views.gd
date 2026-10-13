extends SceneTree

## T05 visual evidence. Runs the 256² coupled main entry to a chosen tick and
## captures one still per view: the normal player view, wetness, compaction and
## sand thickness. The wetness stills are the ones that show the intertidal band
## the material pass wets and dries.
##
## Usage:
##   godot --path <proj> --rendering-driver d3d12 --resolution 1280x720 \
##     --script <this> -- [--tick N] [--tag suffix]

const VIEWS := [
	{"index": 0, "name": "画面"},
	{"index": 4, "name": "湿度"},
	{"index": 5, "name": "压实度"},
	{"index": 6, "name": "沙厚"}]

const STILL_DIR := "res://test_output/sandcastle_water_sand_coupling/验收/"
const CAMERA_POSITION := Vector3(1.0, 5.5, 8.5)
const CAMERA_TARGET := Vector3(3.0, 0.05, -1.0)

var main: Node3D
var finished := false
var started_ms := 0
var capture_tick := 600
var tag := ""
var stills: Array[String] = []


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		match args[i]:
			"--tick":
				capture_tick = int(args[i + 1])
				i += 2
			"--tag":
				tag = args[i + 1]
				i += 2
			_:
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
	for view in VIEWS:
		preview._set_debug_view(view.index)
		await process_frame
		await RenderingServer.frame_post_draw
		var name := "T05_material_%s%s_20260929.png" % [view.index, tag]
		var error: Error = root.get_texture().get_image().save_png(STILL_DIR + name)
		if error != OK:
			_fail("still save failed for view %d: %d" % [view.index, error])
			return
		stills.append("%d:%s" % [view.index, view.name])
	print("PASS: T05 material views tick=%d views=%s" % [
		preview.completed_ticks, ",".join(stills)])
	_finish(0)


func _watchdog() -> void:
	while not finished:
		if Time.get_ticks_msec() - started_ms > 600000:
			_fail("material capture timed out")
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

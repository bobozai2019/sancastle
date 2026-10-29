extends SceneTree

## Throwaway composition aid: loads the main entry with the player camera and
## saves one still so a viewpoint can be chosen before recording.
## Usage: --script <this> -- --pos x,y,z --target x,y,z --tick N --out name.png

var preview: Node3D
var finished := false
var started_ms := 0
var position_m := Vector3(-4.0, 3.0, 8.0)
var target_m := Vector3(2.0, 0.1, -1.0)
var wait_ticks := 60
var output_name := "T04_scout_player_view.png"
var debug_view := 0
var captured := false


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		match args[i]:
			"--pos":
				position_m = _parse_vec(args[i + 1])
				i += 2
			"--target":
				target_m = _parse_vec(args[i + 1])
				i += 2
			"--tick":
				wait_ticks = int(args[i + 1])
				i += 2
			"--out":
				output_name = args[i + 1]
				i += 2
			"--view":
				debug_view = int(args[i + 1])
				i += 2
			_:
				i += 1
	call_deferred("_watchdog")
	call_deferred("_begin")


func _parse_vec(text: String) -> Vector3:
	var parts := text.split(",")
	if parts.size() != 3:
		return Vector3.ZERO
	return Vector3(float(parts[0]), float(parts[1]), float(parts[2]))


func _begin() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	preview = scene.instantiate()
	preview.selected_preset = 1
	preview.enable_gpu_erosion = true
	preview.hide_hud = true
	preview.use_player_camera = true
	preview.player_camera_position = position_m
	preview.player_camera_target = target_m
	root.add_child(preview)
	started_ms = Time.get_ticks_msec()
	call_deferred("_wait")


func _wait() -> void:
	if finished:
		return
	if preview.active_scene == null:
		await process_frame
		call_deferred("_wait")
		return
	if not preview.active_scene.last_error.is_empty():
		_fail(preview.active_scene.last_error)
		return
	if not preview.active_scene.ready_for_ticks or \
			preview.active_scene.completed_ticks < wait_ticks:
		await process_frame
		call_deferred("_wait")
		return
	if not captured:
		captured = true
		preview.active_scene._set_debug_view(debug_view)
		await process_frame
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		var path := "res://test_output/sandcastle_water_sand_coupling/验收/" + output_name
		var error := image.save_png(path)
		if error != OK:
			_fail("scout save failed: %d" % error)
			return
		print("PASS: scout %s pos=%s target=%s tick=%d" % [
			output_name, position_m, target_m, preview.active_scene.completed_ticks])
		_finish(0)
		return
	await process_frame
	call_deferred("_wait")


func _watchdog() -> void:
	if finished:
		return
	if Time.get_ticks_msec() - started_ms > 120000:
		_fail("scout timed out")
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

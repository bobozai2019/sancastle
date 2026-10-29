extends SceneTree

var preview: Node3D
var output := ""
var finished := false

func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			output = arg.trim_prefix("--output=")
	call_deferred("_run")

func _run() -> void:
	if output.is_empty():
		quit(1)
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	root.size = Vector2i(1920, 1080)
	preview = load("res://tests/edit_validation/edit_baseline_trace.tscn").instantiate()
	preview.trace_output = output
	preview.playing = false
	preview.hide_hud = true
	preview.show_brush_indicator = false
	root.add_child(preview)
	var deadline := Time.get_ticks_usec() + 120000000
	while not preview.ready_for_ticks or preview.tick_pending:
		if not preview.last_error.is_empty() or Time.get_ticks_usec() > deadline:
			_finish({"error": "init: " + preview.last_error})
			return
		await process_frame
	# Settle renderer startup before the paired image baseline.
	for i in 10:
		await process_frame
		await RenderingServer.frame_post_draw
	var before := root.get_texture().get_image()
	before.save_png(output.path_join("before.png"))
	var point := Vector3(4.0, 0.0, 1.0)
	var cell: int = int(floor((point.z + 16.0) / 0.125)) * 256 + int(floor((point.x + 16.0) / 0.125))
	point.y = preview.shadow_domain.bed_at(cell)
	var screen: Vector2 = preview.overview_camera.unproject_position(point)
	var camera_view_size: Vector2 = preview.get_viewport().get_visible_rect().size
	screen *= Vector2(before.get_width(), before.get_height()) / camera_view_size
	await process_frame
	await RenderingServer.frame_post_draw
	var control := root.get_texture().get_image()
	control.save_png(output.path_join("no_edit_control.png"))
	var control_changed := _changed_pixels(before, control, screen)
	var submit := Time.get_ticks_usec()
	var error: StringName = preview._submit_brush(&"remove_sand", 0.05, point, point, &"circle")
	var id: int = preview.command_id
	var first_changed_us := -1
	var changed := 0
	var image: Image
	for i in 120:
		await process_frame
		await RenderingServer.frame_post_draw
		image = root.get_texture().get_image()
		changed = _changed_pixels(before, image, screen)
		if changed > 20 and preview.tool_revision_by_command_id.has(id):
			first_changed_us = Time.get_ticks_usec()
			break
	image.save_png(output.path_join("after.png"))
	_finish({"error": String(error), "command_id": id, "screen": [screen.x, screen.y],
		"world": [point.x, point.y, point.z], "changed_pixels": changed,
		"first_observed_changed_us": first_changed_us, "submit_us": submit,
		"latency_upper_bound_ms": (first_changed_us-submit)/1000.0 if first_changed_us >= 0 else null,
		"completed_ticks": preview.completed_ticks, "playing": preview.playing,
		"camera_view_size": [camera_view_size.x, camera_view_size.y], "image_size": [before.get_width(), before.get_height()],
		"no_edit_control_changed_pixels": control_changed,
		"criterion": "paused paired images; RGB difference >2/255 in 96x96 ROI; >20 pixels",
		"pass": error.is_empty() and first_changed_us >= 0 and control_changed == 0})

func _changed_pixels(before: Image, after: Image, screen: Vector2) -> int:
	var changed := 0
	for y in range(maxi(0, int(screen.y) - 48), mini(after.get_height(), int(screen.y) + 48)):
		for x in range(maxi(0, int(screen.x) - 48), mini(after.get_width(), int(screen.x) + 48)):
			var a := before.get_pixel(x, y)
			var b := after.get_pixel(x, y)
			if maxf(absf(a.r-b.r), maxf(absf(a.g-b.g), absf(a.b-b.b))) > 2.0 / 255.0:
				changed += 1
	return changed

func _finish(result: Dictionary) -> void:
	if finished:
		return
	finished = true
	var file := FileAccess.open(output.path_join("visibility.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	file = FileAccess.open(output.path_join("trace.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(preview.take_events(), "\t"))
	preview.queue_free()
	for i in 4:
		await process_frame
	print("VISIBILITY_COMPLETE " + JSON.stringify(result))
	quit(0 if result.get("pass", false) else 1)

extends SceneTree

var preview: Node3D
var started_ms := 0
var finished := false


func _init() -> void:
	call_deferred("_begin")


func _begin() -> void:
	var scene: PackedScene = load("res://scenes/gpu_water_preview.tscn")
	if scene == null:
		_fail("GPU visibility scene missing")
		return
	preview = scene.instantiate()
	root.add_child(preview)
	started_ms = Time.get_ticks_msec()
	call_deferred("_watchdog")
	call_deferred("_run")


func _run() -> void:
	while preview.completed_ticks < 3:
		if not preview.last_error.is_empty():
			_fail(preview.last_error)
			return
		await process_frame
	preview.playing = false
	while preview.tick_pending:
		await process_frame
	for frame in 3:
		await RenderingServer.frame_post_draw
	var baseline := root.get_texture().get_image()
	if baseline == null or baseline.is_empty():
		_fail("GPU visibility baseline image missing")
		return
	var baseline_frame := Engine.get_frames_drawn()
	var submitted_usec := Time.get_ticks_usec()
	var error: StringName = preview._submit_brush(&"remove_sand", 0.12,
		Vector3.ZERO, Vector3.ZERO, &"circle")
	if not error.is_empty():
		_fail("GPU visibility brush rejected: " + String(error))
		return
	var rows := PackedStringArray(["frame_offset,elapsed_ms,changed_samples,patch_batches"])
	var first_visible := -1
	var first_elapsed_ms := 0.0
	for sample in 5:
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		var offset := Engine.get_frames_drawn() - baseline_frame
		var changed := _changed_samples(baseline, image)
		var elapsed_ms := float(Time.get_ticks_usec() - submitted_usec) / 1000.0
		rows.append("%d,%.3f,%d,%d" % [offset, elapsed_ms, changed,
			preview.completed_patch_batches])
		if first_visible < 0 and changed >= 4:
			first_visible = offset
			first_elapsed_ms = elapsed_ms
	var path := "res://test_output/sandcastle_water_sand_coupling/验收/T03_gpu_tool_visibility.csv"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_fail("GPU visibility CSV unavailable")
		return
	file.store_string("\n".join(rows) + "\n")
	file.close()
	if first_visible < 0 or first_visible > 1 or preview.completed_patch_batches < 1:
		_fail("GPU tool was not visible by next rendered frame: offset=%d batches=%d CSV=%s" % [
			first_visible, preview.completed_patch_batches, path])
		return
	while preview.tick_pending:
		await process_frame
	for frame in 3:
		await RenderingServer.frame_post_draw
	var checkpoint_baseline := root.get_texture().get_image()
	var checkpoint_frame := Engine.get_frames_drawn()
	preview._start_checkpoint_capture()
	var checkpoint_error: StringName = preview._submit_brush(&"place_sand", 0.08,
		Vector3.ZERO, Vector3.ZERO, &"circle")
	if not checkpoint_error.is_empty():
		_fail("GPU checkpoint-overlap edit rejected: " + String(checkpoint_error))
		return
	var checkpoint_visible := -1
	for sample in 5:
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		if checkpoint_visible < 0 and _changed_samples(checkpoint_baseline, image) >= 4:
			checkpoint_visible = Engine.get_frames_drawn() - checkpoint_frame
	if checkpoint_visible > 1 or checkpoint_visible < 0:
		_fail("GPU checkpoint-overlap tool missed next frame: offset=%d capture=%s pending=%d batches=%d error=%s" % [
			checkpoint_visible, str(preview.checkpoint_capture_pending),
			preview.command_queue.pending.size(), preview.completed_patch_batches,
			preview.last_error])
		return
	print("PASS: GPU tool same/next-frame visibility offset=%d checkpoint_offset=%d elapsed_ms=%.3f CSV=%s" % [
		first_visible, checkpoint_visible, first_elapsed_ms, path])
	finished = true
	preview.queue_free()
	quit(0)


func _changed_samples(before: Image, after: Image) -> int:
	var changed := 0
	for y in range(250, mini(520, after.get_height()), 2):
		for x in range(350, mini(900, after.get_width()), 2):
			var a := before.get_pixel(x, y)
			var b := after.get_pixel(x, y)
			if absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > 0.03:
				changed += 1
	return changed


func _watchdog() -> void:
	if finished:
		return
	if Time.get_ticks_msec() - started_ms > 30000:
		_fail("GPU tool visibility probe timed out")
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

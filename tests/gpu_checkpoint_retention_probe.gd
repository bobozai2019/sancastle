extends SceneTree

var preview: Node3D
var started_ms := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	started_ms = Time.get_ticks_msec()
	var scene: PackedScene = load("res://scenes/gpu_water_preview.tscn")
	if scene == null:
		_fail("checkpoint retention scene unavailable")
		return
	preview = scene.instantiate()
	preview.checkpoint_interval_ticks = 60
	root.add_child(preview)
	while not preview.ready_for_ticks:
		if not preview.last_error.is_empty() or Time.get_ticks_msec() - started_ms > 10000:
			_fail("checkpoint retention startup stalled: " + preview.last_error)
			return
		await process_frame
	preview.playing = false
	while preview.tick_pending:
		await process_frame
	for edit in 50:
		var kind: StringName = &"remove_sand" if edit % 2 == 0 else &"place_sand"
		var error: StringName = preview._submit_brush(kind, 0.002,
			Vector3.ZERO, Vector3.ZERO, &"circle")
		if not error.is_empty():
			_fail("checkpoint retention history edit rejected: " + String(error))
			return
		while preview.tick_pending:
			await process_frame
	if preview.command_queue.applied_log.size() != 50:
		_fail("checkpoint retention history setup incomplete")
		return
	preview.playing = true
	var static_samples := PackedInt64Array()
	var video_samples := PackedInt64Array()
	for target_tick in [480, 540, 600]:
		while preview.completed_ticks < target_tick or preview.checkpoint_capture_pending:
			if not preview.last_error.is_empty() or Time.get_ticks_msec() - started_ms > 45000:
				_fail("checkpoint retention stalled: " + preview.last_error)
				return
			await process_frame
		if preview.checkpoints.size() != 8 or \
				preview.checkpoints[0].tick != target_tick - 420 or \
				preview.checkpoints[7].tick != target_tick or \
				preview.checkpoints[7].command_ids.size() != 50:
			_fail("checkpoint ring did not retain latest eight at tick %d" % target_tick)
			return
		static_samples.append(int(Performance.get_monitor(Performance.MEMORY_STATIC)))
		video_samples.append(int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)))
	var static_growth := static_samples[-1] - static_samples[0]
	var video_growth := video_samples[-1] - video_samples[0]
	if static_growth > 4 * 1024 * 1024 or video_growth > 1024 * 1024:
		_fail("checkpoint ring memory grew after full: static=%d video=%d" % [
			static_growth, video_growth])
		return
	print("PASS: GPU checkpoint ring 8/8 with 50-command prefix through 600 ticks, post-fill static_growth=%d video_growth=%d samples=%s" % [
		static_growth, video_growth, str(static_samples)])
	preview.queue_free()
	quit(0)


func _fail(message: String) -> void:
	printerr("FAIL: " + message)
	if preview != null:
		preview.queue_free()
	quit(1)

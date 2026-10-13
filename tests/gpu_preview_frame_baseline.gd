extends SceneTree

const OUTPUT_DIR := "res://test_output/sandcastle_water_sand_coupling/验收/"
const WARMUP_FRAMES := 90
const SAMPLE_FRAMES := 600


func _init() -> void:
	call_deferred("_measure")


func _measure() -> void:
	var sample_seconds := int(OS.get_environment("SANDCASTLE_FRAME_SECONDS"))
	var coupled := OS.get_environment("SANDCASTLE_COUPLED_FRAME") == "1"
	var output := OUTPUT_DIR + ("T04_1080p_gpu_coupled_frames.csv" if coupled else \
		("T03_1080p_gpu_preview_frames_5min.csv" if sample_seconds > 0 else \
		"T03_1080p_gpu_preview_frames.csv"))
	if root.size != Vector2i(1920, 1080) or \
			DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED:
		printerr("FAIL: GPU frame baseline requires actual 1920x1080 VSync-off viewport")
		quit(1)
		return
	var scene: PackedScene = load("res://scenes/gpu_water_preview.tscn")
	if scene == null:
		printerr("FAIL: GPU preview scene unavailable")
		quit(1)
		return
	var preview: Node3D = scene.instantiate()
	preview.enable_erosion = coupled
	root.add_child(preview)
	var viewport_rid := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(viewport_rid, true)
	for warmup in WARMUP_FRAMES:
		await process_frame
	if not preview.last_error.is_empty() or not preview.ready_for_ticks:
		printerr("FAIL: GPU preview was not ready: " + preview.last_error)
		quit(1)
		return
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		printerr("FAIL: GPU frame CSV open error %d" % FileAccess.get_open_error())
		quit(1)
		return
	file.store_csv_line(["frame", "wall_ms", "process_ms", "render_cpu_ms",
		"render_gpu_ms", "video_mem_bytes", "sim_tick", "substeps", "tick_pending"])
	var before_us := Time.get_ticks_usec()
	var sample_start_us := before_us
	var start_tick: int = preview.completed_ticks
	var wall_values := PackedFloat32Array()
	var frame := 0
	while frame < SAMPLE_FRAMES or (sample_seconds > 0 and Time.get_ticks_usec() - sample_start_us < sample_seconds * 1000000):
		await process_frame
		if not preview.last_error.is_empty():
			printerr("FAIL: GPU preview failed during frame sample: " + preview.last_error)
			file.close()
			quit(1)
			return
		var now_us := Time.get_ticks_usec()
		var wall_ms := float(now_us - before_us) / 1000.0
		wall_values.append(wall_ms)
		file.store_csv_line([
			str(frame), "%.6f" % wall_ms,
			"%.6f" % (float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0),
			"%.6f" % RenderingServer.viewport_get_measured_render_time_cpu(viewport_rid),
			"%.6f" % RenderingServer.viewport_get_measured_render_time_gpu(viewport_rid),
			str(int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED))),
			str(preview.completed_ticks), str(preview.last_substeps), str(preview.tick_pending)])
		before_us = now_us
		frame += 1
	file.flush()
	file.close()
	wall_values.sort()
	var sample_count := wall_values.size()
	var p50: float = wall_values[int((sample_count - 1) * 0.50)]
	var p95: float = wall_values[int((sample_count - 1) * 0.95)]
	var p99: float = wall_values[int((sample_count - 1) * 0.99)]
	print("GPU_FRAME_1080P coupled=%s frames=%d ticks=%d wall_p50=%.3f wall_p95=%.3f wall_p99=%.3f full_shadow_syncs=%d dirty_bytes=%d" % [
		str(coupled), sample_count, preview.completed_ticks - start_tick, p50, p95,
		p99, preview.full_shadow_syncs, preview.dirty_summary_bytes])
	RenderingServer.viewport_set_measure_render_time(viewport_rid, false)
	preview.queue_free()
	print("PASS: 1080p GPU preview frame baseline written; CSV=%s" % output)
	quit(0)

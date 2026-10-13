extends SceneTree

const OUTPUT := "res://test_output/sandcastle_water_sand_coupling/验收/T00_1080p_cpu_reference_frames.csv"
const WARMUP_FRAMES := 15
const SAMPLE_FRAMES := 60


func _init() -> void:
	call_deferred("_measure")


func _measure() -> void:
	if root.size != Vector2i(1920, 1080) or DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED:
		printerr("FAIL: frame baseline requires actual 1920x1080 VSync-off viewport")
		quit(1)
		return
	var scene: PackedScene = load("res://scenes/cpu_reference.tscn")
	if scene == null:
		printerr("FAIL: standard scene missing")
		quit(1)
		return
	var demo: Node3D = scene.instantiate()
	root.add_child(demo)
	var viewport_rid := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(viewport_rid, true)
	var file := FileAccess.open(OUTPUT, FileAccess.WRITE)
	if file == null:
		printerr("FAIL: baseline CSV open error %d" % FileAccess.get_open_error())
		quit(1)
		return
	file.store_csv_line(["preset", "frame", "wall_ms", "process_ms", "render_cpu_ms", "render_gpu_ms", "video_mem_bytes", "sim_tick"])
	for preset in 3:
		demo._reset_domain(preset)
		demo.playing = true
		for warmup in WARMUP_FRAMES:
			await process_frame
		var before_us := Time.get_ticks_usec()
		for frame in SAMPLE_FRAMES:
			await process_frame
			var now_us := Time.get_ticks_usec()
			file.store_csv_line([
				str(preset + 1), str(frame),
				"%.6f" % (float(now_us - before_us) / 1000.0),
				"%.6f" % (float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0),
				"%.6f" % RenderingServer.viewport_get_measured_render_time_cpu(viewport_rid),
				"%.6f" % RenderingServer.viewport_get_measured_render_time_gpu(viewport_rid),
				str(int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED))),
				str(demo.domain.sim_tick),
			])
			before_us = now_us
		print("PRESET %d: %d sampled frames, tick=%d" % [preset + 1, SAMPLE_FRAMES, demo.domain.sim_tick])
	file.flush()
	file.close()
	RenderingServer.viewport_set_measure_render_time(viewport_rid, false)
	print("PASS: 1080p CPU reference frame baseline written")
	quit(0)

extends SceneTree

const SCENE := preload("res://scenes/water_visual_fixture.tscn")
const OUT := "res://test_output/sandcastle_visual_reconstruction_phase2/验收/"

var mode := "frame"
var sample_seconds := 300
var warmup_seconds := 30
var preview: Node3D


func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--mode="):
			mode = arg.trim_prefix("--mode=")
		if arg.begins_with("--seconds="):
			sample_seconds = int(arg.trim_prefix("--seconds="))
		if arg.begins_with("--warmup="):
			warmup_seconds = int(arg.trim_prefix("--warmup="))
	call_deferred("_run")


func _run() -> void:
	if mode not in ["frame", "soak"] or sample_seconds < 1:
		_fail("invalid acceptance mode or duration")
		return
	if mode == "frame" and (root.size != Vector2i(1920, 1080) or \
			DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED):
		_fail("frame gate requires actual 1920x1080 VSync-off viewport")
		return
	preview = SCENE.instantiate()
	root.add_child(preview)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	var started_us := Time.get_ticks_usec()
	while not preview.ready_for_ticks and Time.get_ticks_usec() - started_us < 30000000:
		await process_frame
	if not preview.ready_for_ticks or not preview.last_error.is_empty():
		_fail("fixture initialization: " + preview.last_error)
		return
	var initial_rock_hash: int = hash(preview.shadow_domain.rock)
	var initial_sand_hash: int = hash(preview.shadow_domain.sand)
	var wave_sent := false
	var warm_start_us := Time.get_ticks_usec()
	while Time.get_ticks_usec() - warm_start_us < warmup_seconds * 1000000:
		await process_frame
		if not _healthy():
			return
		if preview.completed_ticks >= 60 and not wave_sent:
			if not _send_wave():
				return
			wave_sent = true
	if not wave_sent:
		if not _send_wave():
			return
		wave_sent = true
	var csv_path := OUT + ("W06_1080p_frames.csv" if mode == "frame" else "W06_water_soak.csv")
	var csv := FileAccess.open(csv_path, FileAccess.WRITE)
	if csv == null:
		_fail("acceptance CSV open failed")
		return
	if mode == "frame":
		csv.store_csv_line(["frame", "wall_ms", "process_ms", "render_cpu_ms",
			"render_gpu_ms", "static_bytes", "video_bytes", "tick", "substeps"])
	else:
		csv.store_csv_line(["elapsed_s", "tick", "audit_water_m3", "source_m3",
			"sink_m3", "min_depth_m", "invalid_cells", "negative_cells",
			"static_bytes", "video_bytes", "render_cpu_ms", "render_gpu_ms"])
	var sample_start_us := Time.get_ticks_usec()
	var before_us := sample_start_us
	var start_tick: int = preview.completed_ticks
	var wall_values := PackedFloat32Array()
	var sample_rows := 0
	var last_soak_second := -30
	while Time.get_ticks_usec() - sample_start_us < sample_seconds * 1000000:
		await process_frame
		if not _healthy():
			csv.close()
			return
		var now_us := Time.get_ticks_usec()
		var elapsed_s := int((now_us - sample_start_us) / 1000000)
		if mode == "frame":
			var wall_ms := float(now_us - before_us) / 1000.0
			wall_values.append(wall_ms)
			csv.store_csv_line([str(sample_rows), "%.6f" % wall_ms,
				"%.6f" % (float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0),
				"%.6f" % RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()),
				"%.6f" % RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()),
				str(int(Performance.get_monitor(Performance.MEMORY_STATIC))),
				str(int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED))),
				str(preview.completed_ticks), str(preview.last_substeps)])
			sample_rows += 1
		else:
			if elapsed_s >= last_soak_second + 30:
				csv.store_csv_line([str(elapsed_s), str(preview.completed_ticks),
					"%.9f" % preview.audit_water_m3,
					"%.9f" % preview.solver.water_source_m3,
					"%.9f" % preview.solver.water_sink_m3,
					"%.9f" % preview.audit_min_depth_m,
					str(preview.audit_invalid_cells), str(preview.audit_negative_cells),
					str(int(Performance.get_monitor(Performance.MEMORY_STATIC))),
					str(int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED))),
					"%.6f" % RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()),
					"%.6f" % RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid())])
				csv.flush()
				last_soak_second = elapsed_s
				sample_rows += 1
				print("W06_SOAK elapsed=%d/%d tick=%d audit_invalid=%d static=%d video=%d" % [
					elapsed_s, sample_seconds, preview.completed_ticks,
					preview.audit_invalid_cells,
					int(Performance.get_monitor(Performance.MEMORY_STATIC)),
					int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED))])
		before_us = now_us
	csv.flush()
	csv.close()
	preview.playing = false
	while preview.tick_pending:
		await process_frame
	var elapsed_total_s := float(Time.get_ticks_usec() - sample_start_us) / 1000000.0
	var tick_rate := float(preview.completed_ticks - start_tick) / elapsed_total_s
	var summary := {"mode": mode, "sample_seconds": elapsed_total_s,
		"warmup_seconds": warmup_seconds, "frames_or_rows": sample_rows,
		"tick_start": start_tick, "tick_end": preview.completed_ticks,
		"tick_rate": tick_rate, "viewport_px": [root.size.x, root.size.y],
		"tick_rate_quantization_hz": 1.0 / elapsed_total_s,
		"vsync_mode": DisplayServer.window_get_vsync_mode(),
		"adapter": RenderingServer.get_video_adapter_name(),
		"max_substeps": preview.solver.max_substeps_used,
		"overload_events": preview.solver.overload_events,
		"nan_events": preview.solver.nan_events,
		"invalid_cells": preview.audit_invalid_cells,
		"negative_cells": preview.audit_negative_cells,
		"min_depth_m": preview.audit_min_depth_m,
		"rock_hash_unchanged": hash(preview.shadow_domain.rock) == initial_rock_hash,
		"sand_hash_unchanged": hash(preview.shadow_domain.sand) == initial_sand_hash,
		"wave_sent": wave_sent, "csv": csv_path.get_file()}
	if mode == "frame" and not wall_values.is_empty():
		wall_values.sort()
		summary["wall_p50_ms"] = wall_values[int((wall_values.size() - 1) * 0.50)]
		summary["wall_p95_ms"] = wall_values[int((wall_values.size() - 1) * 0.95)]
		summary["wall_p99_ms"] = wall_values[int((wall_values.size() - 1) * 0.99)]
	var summary_path := OUT + ("W06_1080p_summary.json" if mode == "frame" else "W06_water_soak_summary.json")
	var output := FileAccess.open(summary_path, FileAccess.WRITE)
	if output == null:
		_fail("acceptance summary open failed")
		return
	output.store_string(JSON.stringify(summary, "\t"))
	output.close()
	var passes: bool = tick_rate + 1.0 / elapsed_total_s >= 30.0 and \
			preview.solver.overload_events == 0 and \
			preview.solver.nan_events == 0 and preview.audit_invalid_cells == 0 and \
			preview.audit_negative_cells == 0 and summary.rock_hash_unchanged and \
			summary.sand_hash_unchanged and wave_sent
	if mode == "frame":
		passes = passes and float(summary.get("wall_p99_ms", INF)) <= 33.3
	print(("PASS" if passes else "FAIL") + ": W06 water " + JSON.stringify(summary))
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), false)
	quit(0 if passes else 1)


func _healthy() -> bool:
	if not preview.last_error.is_empty() or preview.audit_invalid_cells > 0 or \
			preview.audit_negative_cells > 0 or preview.solver.nan_events > 0 or \
			preview.solver.overload_events > 0:
		_fail("acceptance runtime error: " + preview.last_error)
		return false
	return true


func _send_wave() -> bool:
	var accepted: Dictionary = preview.request_wave({
		"domain_id": preview.shadow_domain.domain_id,
		"generation": preview.generation, "request_id": 1,
		"start_tick": preview.completed_ticks + 8,
		"profile_id": &"test_packet", "amplitude_m": 0.18,
		"duration_s": 6.0, "seed": 31})
	if not accepted.ok:
		_fail("acceptance wave request rejected: " + str(accepted))
		return false
	return true


func _fail(message: String) -> void:
	printerr("FAIL: W06 water " + message)
	quit(1)

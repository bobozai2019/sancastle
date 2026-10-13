extends SceneTree

const COUPLED_SCENE := preload("res://scenes/sand_coupled_fixture.tscn")
const STANDARD_SCENE := preload("res://scenes/gpu_water_preview.tscn")
const OUT := "res://test_output/sandcastle_visual_reconstruction_phase2/验收/"

var case_id := "coupled"
var mode := "frame"
var seconds := 300
var warmup_seconds := 30
var preview: Node3D


func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--case="):
			case_id = arg.trim_prefix("--case=")
		if arg.begins_with("--mode="):
			mode = arg.trim_prefix("--mode=")
		if arg.begins_with("--seconds="):
			seconds = int(arg.trim_prefix("--seconds="))
		if arg.begins_with("--warmup="):
			warmup_seconds = int(arg.trim_prefix("--warmup="))
	call_deferred("_run")


func _run() -> void:
	if case_id not in ["coupled", "preset0", "preset1", "preset2"] or \
			mode not in ["frame", "soak"] or seconds < 1 or warmup_seconds < 0:
		_fail("invalid arguments")
		return
	if mode == "frame" and (root.size != Vector2i(1920, 1080) or \
			DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED):
		_fail("requires actual 1920x1080 VSync-off viewport")
		return
	preview = COUPLED_SCENE.instantiate() if case_id == "coupled" else STANDARD_SCENE.instantiate()
	if case_id != "coupled":
		preview.preset_index = int(case_id.trim_prefix("preset"))
		preview.enable_erosion = true
		preview.enable_structures = true
		preview.use_player_camera = true
		preview.hide_hud = true
		preview.show_brush_indicator = false
	root.add_child(preview)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	var init_us := Time.get_ticks_usec()
	while not preview.ready_for_ticks and Time.get_ticks_usec() - init_us < 30000000:
		await process_frame
	if not preview.ready_for_ticks:
		_fail("initialization: " + preview.last_error)
		return
	var warm_us := Time.get_ticks_usec()
	while Time.get_ticks_usec() - warm_us < warmup_seconds * 1000000:
		await process_frame
		if not _healthy():
			return
	var wave_sent := false
	if case_id == "coupled":
		var accepted: Dictionary = preview.request_wave({
			"domain_id": preview.shadow_domain.domain_id,
			"generation": preview.generation, "request_id": 1,
			"start_tick": preview.completed_ticks + 8,
			"profile_id": &"test_packet", "amplitude_m": 0.20,
			"duration_s": 5.0, "seed": 53021})
		if not accepted.ok:
			_fail("wave: " + str(accepted))
			return
		wave_sent = true
	var stem := "S06_%s_%s" % [case_id, mode]
	var csv := FileAccess.open(OUT + stem + ".csv", FileAccess.WRITE)
	if csv == null:
		_fail("CSV open")
		return
	if mode == "frame":
		csv.store_csv_line(["frame", "wall_ms", "process_ms", "render_cpu_ms",
			"render_gpu_ms", "static_bytes", "video_bytes", "tick", "substeps"])
	else:
		csv.store_csv_line(["elapsed_s", "tick", "water_m3", "sand_m3",
			"sediment_m3", "sand_closure_m3", "invalid_water_cells",
			"negative_water_cells", "invalid_sand_cells", "negative_sand_cells",
			"static_bytes", "video_bytes", "render_cpu_ms", "render_gpu_ms",
			"support_events"])
	var start_us := Time.get_ticks_usec()
	var before_us := start_us
	var start_tick: int = preview.completed_ticks
	var frames := 0
	var rows := 0
	var next_second := 0
	var wall_values := PackedFloat32Array()
	var static_min := 9223372036854775807
	var static_max := 0
	var video_min := 9223372036854775807
	var video_max := 0
	while Time.get_ticks_usec() - start_us < seconds * 1000000:
		await process_frame
		if not _healthy():
			csv.close()
			return
		var now_us := Time.get_ticks_usec()
		var static_bytes := int(Performance.get_monitor(Performance.MEMORY_STATIC))
		var video_bytes := int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED))
		static_min = mini(static_min, static_bytes)
		static_max = maxi(static_max, static_bytes)
		video_min = mini(video_min, video_bytes)
		video_max = maxi(video_max, video_bytes)
		if mode == "frame":
			var wall_ms := float(now_us - before_us) / 1000.0
			wall_values.append(wall_ms)
			csv.store_csv_line([str(frames), "%.6f" % wall_ms,
				"%.6f" % (float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0),
				"%.6f" % RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()),
				"%.6f" % RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()),
				str(static_bytes), str(video_bytes), str(preview.completed_ticks),
				str(preview.last_substeps)])
			frames += 1
		else:
			var elapsed_s := int((now_us - start_us) / 1000000)
			if elapsed_s >= next_second:
				csv.store_csv_line([str(elapsed_s), str(preview.completed_ticks),
					str(preview.audit_water_m3), str(preview.audit_sand_m3),
					str(preview.audit_sediment_m3), str(preview.audit_sand_closure_m3),
					str(preview.audit_invalid_cells), str(preview.audit_negative_cells),
					str(preview.audit_sand_invalid_cells), str(preview.audit_sand_negative_cells),
					str(static_bytes), str(video_bytes),
					"%.6f" % RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()),
					"%.6f" % RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()),
					str(preview.support_loss_events.size())])
				csv.flush()
				rows += 1
				next_second += 30
				print("S06_SOAK case=%s elapsed=%d/%d tick=%d invalid=%d sand_invalid=%d static=%d video=%d" % [
					case_id, elapsed_s, seconds, preview.completed_ticks,
					preview.audit_invalid_cells, preview.audit_sand_invalid_cells,
					static_bytes, video_bytes])
		before_us = now_us
	csv.close()
	preview.playing = false
	while preview.tick_pending:
		await process_frame
	var elapsed_total_s := float(Time.get_ticks_usec() - start_us) / 1000000.0
	var tick_rate := float(preview.completed_ticks - start_tick) / elapsed_total_s
	var summary := {"case": case_id, "mode": mode,
		"sample_seconds": elapsed_total_s, "warmup_seconds": warmup_seconds,
		"frames_or_rows": frames if mode == "frame" else rows,
		"tick_start": start_tick, "tick_end": preview.completed_ticks,
		"tick_rate": tick_rate, "viewport_px": [root.size.x, root.size.y],
		"vsync_mode": DisplayServer.window_get_vsync_mode(),
		"adapter": RenderingServer.get_video_adapter_name(),
		"max_substeps": preview.solver.max_substeps_used,
		"overload_events": preview.solver.overload_events,
		"nan_events": preview.solver.nan_events,
		"invalid_water_cells": preview.audit_invalid_cells,
		"negative_water_cells": preview.audit_negative_cells,
		"invalid_sand_cells": preview.audit_sand_invalid_cells,
		"negative_sand_cells": preview.audit_sand_negative_cells,
		"sand_closure_m3": preview.audit_sand_closure_m3,
		"static_memory_range_bytes": static_max - static_min,
		"video_memory_range_bytes": video_max - video_min,
		"wave_sent": wave_sent,
		"support_events": preview.support_loss_events.duplicate(true),
		"csv": stem + ".csv"}
	if mode == "frame" and not wall_values.is_empty():
		wall_values.sort()
		summary["wall_p50_ms"] = wall_values[int((wall_values.size() - 1) * 0.50)]
		summary["wall_p95_ms"] = wall_values[int((wall_values.size() - 1) * 0.95)]
		summary["wall_p99_ms"] = wall_values[int((wall_values.size() - 1) * 0.99)]
	var file := FileAccess.open(OUT + stem + "_summary.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(summary, "  "))
	file.close()
	var passes: bool = tick_rate + 1.0 / elapsed_total_s >= 30.0 and \
			preview.solver.overload_events == 0 and preview.solver.nan_events == 0 and \
			preview.audit_invalid_cells == 0 and preview.audit_negative_cells == 0 and \
			preview.audit_sand_invalid_cells == 0 and preview.audit_sand_negative_cells == 0
	if case_id == "coupled":
		passes = passes and wave_sent and preview.support_loss_events.size() == 1
	if mode == "frame":
		passes = passes and float(summary.get("wall_p99_ms", INF)) <= 33.3
	print(("PASS" if passes else "FAIL") + ": S06 acceptance " + JSON.stringify(summary))
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), false)
	quit(0 if passes else 1)


func _healthy() -> bool:
	if not preview.last_error.is_empty() or preview.solver.nan_events > 0 or \
			preview.solver.overload_events > 0 or preview.audit_invalid_cells > 0 or \
			preview.audit_negative_cells > 0 or preview.audit_sand_invalid_cells > 0 or \
			preview.audit_sand_negative_cells > 0:
		_fail("runtime: " + preview.last_error)
		return false
	return true


func _fail(message: String) -> void:
	printerr("FAIL: S06 acceptance " + message)
	quit(1)

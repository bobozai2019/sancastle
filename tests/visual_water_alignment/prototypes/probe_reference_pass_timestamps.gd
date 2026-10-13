extends SceneTree

const SCENE := preload("res://tests/visual_water_alignment/prototypes/reference_coupled.tscn")

var output_dir := ""
var run_id := ""
var warmup_s := 30
var sample_s := 60
var wave_load := "continuous"
var preview: Node3D
var rd: RenderingDevice
var rows: Array[Dictionary] = []
var requests: Array[Dictionary] = []
var last_frame := -1
var finished := false
var start_ms := 0
var sample_tick_start := 0
var sample_tick_end := 0
var sample_wall_s := 0.0


func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			output_dir = arg.trim_prefix("--output=")
		elif arg.begins_with("--run-id="):
			run_id = arg.trim_prefix("--run-id=")
		elif arg.begins_with("--warmup="):
			warmup_s = int(arg.trim_prefix("--warmup="))
		elif arg.begins_with("--seconds="):
			sample_s = int(arg.trim_prefix("--seconds="))
		elif arg.begins_with("--wave-load="):
			wave_load = arg.trim_prefix("--wave-load=")
	call_deferred("_run")


func _run() -> void:
	if output_dir.is_empty() or run_id.is_empty() or warmup_s < 0 or \
			sample_s < 1 or wave_load not in ["continuous", "none"] or \
			not DirAccess.dir_exists_absolute(output_dir):
		_fail("invalid arguments")
		return
	if root.size != Vector2i(1920, 1080) or \
			DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED:
		_fail("requires visible 1920x1080 VSync-off viewport")
		return
	preview = SCENE.instantiate()
	root.add_child(preview)
	start_ms = Time.get_ticks_msec()
	call_deferred("_watchdog")
	while not preview.ready_for_ticks and preview.last_error.is_empty() and \
			Time.get_ticks_msec() - start_ms < 30000:
		await process_frame
	if not preview.ready_for_ticks or not preview.last_error.is_empty():
		_fail("fixture initialization: " + preview.last_error)
		return
	preview.set_fixture_camera(&"oblique")
	preview.set_visual_time(-1.0)
	preview.water_material.set_shader_parameter("prototype_eta_normals", true)
	preview.water_material.set_shader_parameter("prototype_crest_height_m", 0.16)
	preview.water_material.set_shader_parameter("prototype_irregular_foam", true)
	preview.water_material.set_shader_parameter("prototype_screen_optics", false)
	if wave_load == "continuous":
		for request_id in range(1, 81):
			var request := {"domain_id": preview.shadow_domain.domain_id,
				"generation": preview.generation, "request_id": request_id,
				"start_tick": preview.completed_ticks + 8 + (request_id - 1) * 180,
				"profile_id": &"test_packet", "amplitude_m": 0.18,
				"duration_s": 6.0, "seed": 31 + request_id * 17}
			var admitted: Dictionary = preview.request_wave(request)
			if not admitted.ok:
				_fail("wave rejected: " + String(admitted.code))
				return
			requests.append(request)
	var warmup_start := Time.get_ticks_usec()
	while Time.get_ticks_usec() - warmup_start < warmup_s * 1000000:
		await process_frame
		if not preview.last_error.is_empty():
			_fail(preview.last_error)
			return
	RenderingServer.call_on_render_thread(_enable_profile)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	sample_tick_start = preview.completed_ticks
	var sample_start := Time.get_ticks_usec()
	while Time.get_ticks_usec() - sample_start < sample_s * 1000000:
		await process_frame
		if not preview.last_error.is_empty():
			_fail(preview.last_error)
			return
		RenderingServer.call_on_render_thread(_collect_render)
	sample_wall_s = float(Time.get_ticks_usec() - sample_start) / 1000000.0
	sample_tick_end = preview.completed_ticks
	RenderingServer.call_on_render_thread(_disable_profile)
	for _i in 12:
		await process_frame
		RenderingServer.call_on_render_thread(_collect_render)
	call_deferred("_write_result")


func _enable_profile() -> void:
	rd = RenderingServer.get_rendering_device()
	preview.solver.profile_passes = true
	preview.collision_proxy.profile_passes = true


func _disable_profile() -> void:
	preview.solver.profile_passes = false
	preview.collision_proxy.profile_passes = false


func _collect_render() -> void:
	if rd == null:
		return
	var frame := rd.get_captured_timestamps_frame()
	if frame < 0 or frame == last_frame:
		return
	last_frame = frame
	var starts := {}
	var captured: Array[Dictionary] = []
	for i in rd.get_captured_timestamps_count():
		var name := rd.get_captured_timestamp_name(i)
		if not name.begins_with("sandcastle_"):
			continue
		var gpu_ns := rd.get_captured_timestamp_gpu_time(i)
		var cpu_us := rd.get_captured_timestamp_cpu_time(i)
		if name.ends_with("_start"):
			starts[name.trim_suffix("_start")] = [gpu_ns, cpu_us]
		elif name.ends_with("_end"):
			var key := name.trim_suffix("_end")
			if not starts.has(key):
				continue
			var begin: Array = starts[key]
			var gpu_delta: int = gpu_ns - int(begin[0])
			var cpu_delta: int = cpu_us - int(begin[1])
			if gpu_delta >= 0 and cpu_delta >= 0:
				captured.append({"frame": frame, "pass": key,
					"gpu_ns": gpu_delta, "cpu_us": cpu_delta})
			starts.erase(key)
	if not captured.is_empty():
		call_deferred("_record", captured)


func _record(captured: Array[Dictionary]) -> void:
	if not finished:
		rows.append_array(captured)


func _write_result() -> void:
	if finished:
		return
	if rows.is_empty():
		_fail("no paired pass timestamps")
		return
	var names := {}
	var positive := 0
	var csv_path := output_dir.path_join(run_id + "_pass_timestamps.csv")
	var csv := FileAccess.open(csv_path, FileAccess.WRITE)
	if csv == null:
		_fail("CSV open failed")
		return
	csv.store_csv_line(["frame", "pass", "gpu_ns", "cpu_us"])
	for row in rows:
		csv.store_csv_line([str(row.frame), row.pass, str(row.gpu_ns), str(row.cpu_us)])
		names[row.pass] = true
		positive += int(row.gpu_ns > 0)
	csv.close()
	if positive < 1 or not names.has("sandcastle_cfl") or \
			not names.has("sandcastle_sediment") or not names.has("sandcastle_material"):
		_fail("missing nonzero water/sand pass timestamps")
		return
	var manifest := {"role": "w07_pass_diagnostic", "run_id": run_id,
		"wave_load": wave_load, "warmup_s": warmup_s,
		"sample_requested_s": sample_s, "sample_wall_s": sample_wall_s,
		"sample_tick_start": sample_tick_start, "sample_tick_end": sample_tick_end,
		"rows": rows.size(), "positive_gpu_rows": positive,
		"passes": names.keys(), "wave_requests": requests,
		"viewport_px": [root.size.x, root.size.y],
		"hardware": RenderingServer.get_video_adapter_name(),
		"rendering_driver": "d3d12", "csv": csv_path}
	var manifest_path := output_dir.path_join(run_id + "_manifest.json")
	var file := FileAccess.open(manifest_path, FileAccess.WRITE)
	if file == null:
		_fail("manifest open failed")
		return
	file.store_string(JSON.stringify(manifest, "\t"))
	file.close()
	print("PASS: W07 pass timestamps rows=%d positive=%d ticks=%d CSV=%s" % [
		rows.size(), positive, sample_tick_end - sample_tick_start, csv_path])
	finished = true
	preview.queue_free()
	quit(0)


func _watchdog() -> void:
	if finished:
		return
	if Time.get_ticks_msec() - start_ms > (warmup_s + sample_s + 65) * 1000:
		_fail("timestamp probe timed out")
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

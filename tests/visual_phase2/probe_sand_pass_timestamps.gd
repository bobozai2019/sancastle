extends SceneTree

const OUTPUT := "res://test_output/sandcastle_visual_reconstruction_phase2/验收/S06_coupled_pass_timestamps.csv"
const SAMPLE_FRAMES := 360

var preview: Node3D
var rd: RenderingDevice
var last_frame := -1
var rows: Array[Dictionary] = []
var finished := false
var started_ms := 0


func _init() -> void:
	call_deferred("_begin")


func _begin() -> void:
	var scene: PackedScene = load("res://scenes/sand_coupled_fixture.tscn")
	if scene == null:
		_fail("GPU preview scene unavailable")
		return
	preview = scene.instantiate()
	root.add_child(preview)
	started_ms = Time.get_ticks_msec()
	call_deferred("_watchdog")
	call_deferred("_wait_ready")


func _wait_ready() -> void:
	if finished:
		return
	if not preview.last_error.is_empty():
		_fail(preview.last_error)
		return
	if not preview.ready_for_ticks:
		await process_frame
		call_deferred("_wait_ready")
		return
	RenderingServer.call_on_render_thread(_enable_profile)
	call_deferred("_sample")


func _enable_profile() -> void:
	rd = RenderingServer.get_rendering_device()
	preview.solver.profile_passes = true
	preview.collision_proxy.profile_passes = true


func _sample() -> void:
	for frame in SAMPLE_FRAMES:
		if finished:
			return
		if not preview.last_error.is_empty():
			_fail(preview.last_error)
			return
		await process_frame
		RenderingServer.call_on_render_thread(_collect_render)
	RenderingServer.call_on_render_thread(_disable_profile)
	for frame in 12:
		await process_frame
		RenderingServer.call_on_render_thread(_collect_render)
	call_deferred("_write_result")


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
		# Godot 4.7.2 D3D12 converts query ticks to nanoseconds even though
		# the class reference currently describes this value as microseconds.
		var gpu_ns := rd.get_captured_timestamp_gpu_time(i)
		var cpu_us := rd.get_captured_timestamp_cpu_time(i)
		if name.ends_with("_start"):
			starts[name.trim_suffix("_start")] = [gpu_ns, cpu_us]
		elif name.ends_with("_end"):
			var key := name.trim_suffix("_end")
			if not starts.has(key):
				continue
			var start: Array = starts[key]
			var gpu_delta: int = gpu_ns - int(start[0])
			var cpu_delta: int = cpu_us - int(start[1])
			if gpu_delta >= 0 and cpu_delta >= 0:
				captured.append({"frame": frame, "pass": key,
					"gpu_ns": gpu_delta, "cpu_us": cpu_delta})
			starts.erase(key)
	if not captured.is_empty():
		call_deferred("_record", captured)


func _record(captured: Array[Dictionary]) -> void:
	if finished:
		return
	rows.append_array(captured)


func _write_result() -> void:
	if finished:
		return
	if rows.is_empty():
		_fail("RenderingDevice returned no paired GPU pass timestamps")
		return
	var file := FileAccess.open(OUTPUT, FileAccess.WRITE)
	if file == null:
		_fail("timestamp CSV unavailable")
		return
	file.store_csv_line(["frame", "pass", "gpu_ns", "cpu_us"])
	var names := {}
	var positive_gpu := 0
	for row in rows:
		file.store_csv_line([str(row.frame), row.pass,
			str(row.gpu_ns), str(row.cpu_us)])
		names[row.pass] = true
		if row.gpu_ns > 0:
			positive_gpu += 1
	file.close()
	if positive_gpu < 1:
		_fail("GPU timestamp pairs were all zero")
		return
	if not names.has("sandcastle_sand_audit"):
		_fail("GPU sand audit pass timestamp missing")
		return
	print("PASS: GPU pass timestamps pairs=%d nonzero_gpu=%d passes=%s ticks=%d CSV=%s" % [
		rows.size(), positive_gpu, str(names.keys()), preview.completed_ticks, OUTPUT])
	finished = true
	preview.queue_free()
	quit(0)


func _watchdog() -> void:
	if finished:
		return
	if Time.get_ticks_msec() - started_ms > 120000:
		_fail("GPU pass timestamp probe timed out")
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

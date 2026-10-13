extends SceneTree

## T08 G05: long-run stability on the 256² coupled main entry.
##
## Runs the real-time loop (not a fixed-fps movie) so the frame pacing, the
## shadow sync and the collision proxy are all exercised the way the product
## would be. At a fixed tick interval it reads the authoritative fields back and
## records one CSV row, and it fails the moment it sees a NaN, a negative depth,
## a negative sand cell or a sand ledger that stops closing.
##
## It also tracks static memory so a per-tick leak shows up as a slope rather
## than only as a crash, and it writes a per-tick memory trace to a side file so a
## one-off step can be pinned to the exact tick instead of the sample interval.
##
## Usage:
##   godot --path <proj> --rendering-driver d3d12 --resolution 1280x720 \
##     --script <this> -- --preset 1 --ticks 54000 --sample 300 --out name.csv

const STILL_DIR := "res://test_output/sandcastle_water_sand_coupling/验收/"

var preview: Node3D
var finished := false
var started_ms := 0
var tick_target := 54000
var sample_interval := 300
var preset := 1
var output_name := "T08_stability_20260929.csv"
var failures: Array[String] = []
var rows: Array[String] = []
var next_sample := 0
var baseline_sand := NAN
var first_memory_kb := 0
var max_memory_kb := 0
var readbacks := {}
var readback_pending := false
## Samples are appended here as they happen, so a long run can be watched rather
## than only read once it exits.
var progress_path := ""
var memory_path := ""
var last_report_ms := 0
var enable_structures := false
var require_1080p := false
## Per-tick memory trace, appended as the run goes.
var memory_trace: FileAccess
## Frame wall times across the whole run, so the same pass also yields the p50 /
## p95 / p99 the performance gate asks for instead of a separate short sample.
var frame_usec: PackedInt64Array = PackedInt64Array()
var last_frame_usec := 0
var previous_memory_kb := 0
var memory_steps: Array[String] = []


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		match args[i]:
			"--preset":
				preset = int(args[i + 1])
				i += 2
			"--ticks":
				tick_target = int(args[i + 1])
				i += 2
			"--sample":
				sample_interval = int(args[i + 1])
				i += 2
			"--out":
				output_name = args[i + 1]
				progress_path = args[i + 1] + ".progress"
				memory_path = args[i + 1] + ".memory"
				i += 2
			"--structures":
				enable_structures = args[i + 1] == "1"
				i += 2
			"--highres":
				require_1080p = args[i + 1] == "1"
				i += 2
			_:
				i += 1
	call_deferred("_watchdog")
	call_deferred("_begin")


func _begin() -> void:
	started_ms = Time.get_ticks_msec()
	var scene: PackedScene = load("res://scenes/gpu_water_preview.tscn")
	if scene == null:
		_fail("preview scene unavailable")
		return
	preview = scene.instantiate()
	preview.preset_index = preset
	preview.enable_erosion = true
	preview.enable_structures = enable_structures
	preview.hide_hud = true
	preview.use_player_camera = true
	if require_1080p and (root.size != Vector2i(1920, 1080) or
			DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED):
		_fail("1080p run requires an actual 1920x1080 VSync-off viewport")
		return
	root.add_child(preview)
	## The trace is opened once and appended to, so a crash still leaves the series
	## up to that point on disk.
	memory_trace = FileAccess.open(STILL_DIR + memory_path, FileAccess.WRITE)
	if memory_trace != null:
		memory_trace.store_line("tick,memory_kb,delta_kb")
	call_deferred("_loop")


func _loop() -> void:
	while not finished:
		if not preview.last_error.is_empty():
			_fail(preview.last_error)
			return
		if not preview.ready_for_ticks:
			await process_frame
			continue
		_trace_frame()
		var tick: int = preview.completed_ticks
		_trace_memory(tick)
		if tick >= tick_target:
			break
		if tick >= next_sample and not readback_pending and not preview.tick_pending:
			next_sample = tick + sample_interval
			_sample(tick)
			continue
		await process_frame
	if finished:
		return
	_finish_run()


## Reads the authoritative fields back and records a row. Runs on the main thread
## between ticks, so it does not disturb the render-thread dispatch order.
func _sample(tick: int) -> void:
	readbacks.clear()
	readback_pending = true
	RenderingServer.call_on_render_thread(_render_sample.bind(tick))


func _render_sample(tick: int) -> void:
	for field in ["water", "sand", "sediment", "wetness", "compaction"]:
		var error: Error = preview.solver.request_data(field,
			_on_field.bind(field, tick))
		if error != OK:
			call_deferred("_fail", "readback request failed for " + field)
			return


func _on_field(data: PackedByteArray, field: String, tick: int) -> void:
	call_deferred("_record", data, field, tick)


func _record(data: PackedByteArray, field: String, tick: int) -> void:
	if finished:
		return
	var values := PackedFloat32Array()
	if data.size() == 256 * 256 * 4:
		values = data.to_float32_array()
	elif data.size() == 256 * 256 * 2:
		values.resize(256 * 256)
		for i in 256 * 256:
			values[i] = data.decode_half(i * 2)
	else:
		_fail("unexpected readback size for %s: %d" % [field, data.size()])
		return
	readbacks[field] = values
	if readbacks.size() < 5:
		return
	readback_pending = false
	_tally(tick)


func _tally(tick: int) -> void:
	var area := 0.125 * 0.125
	var water_m3 := 0.0
	var min_depth := INF
	var sand_m3 := 0.0
	var sediment_m3 := 0.0
	var negative_sand := 0
	var nonfinite := 0
	for i in 256 * 256:
		var depth: float = readbacks["water"][i]
		var sand: float = readbacks["sand"][i]
		var sediment: float = readbacks["sediment"][i]
		var wetness: float = readbacks["wetness"][i]
		var compaction: float = readbacks["compaction"][i]
		if not is_finite(depth) or not is_finite(sand) or not is_finite(sediment) or \
				not is_finite(wetness) or not is_finite(compaction):
			nonfinite += 1
			continue
		if depth < -0.000001 or sand < -0.000001 or sediment < -0.000001:
			negative_sand += 1
		min_depth = minf(min_depth, depth)
		water_m3 += depth * area
		sand_m3 += sand * area
		sediment_m3 += sediment * area
	if is_nan(baseline_sand):
		baseline_sand = sand_m3 + sediment_m3
	var ledger: float = sand_m3 + sediment_m3 + preview.shadow_domain.tool_inventory_m3
	var closure := absf(ledger - baseline_sand - preview.shadow_domain.sand_source_m3 +
		preview.shadow_domain.sand_sink_m3)
	var memory_kb := OS.get_static_memory_usage() / 1024
	if first_memory_kb == 0:
		first_memory_kb = memory_kb
	max_memory_kb = maxi(max_memory_kb, memory_kb)
	rows.append("%d,%.4f,%.9f,%.9f,%.9f,%.9f,%.9f,%d,%d,%d" % [
		tick, float(tick) / 30.0, water_m3, min_depth, sand_m3, sediment_m3,
		closure, negative_sand, nonfinite, memory_kb])
	if nonfinite > 0:
		_fail("tick %d has %d non-finite cells" % [tick, nonfinite])
		return
	if negative_sand > 0:
		_fail("tick %d has %d negative water/sand cells" % [tick, negative_sand])
		return
	if closure > 0.05:
		_fail("tick %d sand ledger drifted by %.6f m3" % [tick, closure])
		return
	## Append, so the file is a usable series while the run is still going.
	## Godot has no append mode: open read-write (creating if needed) and seek end.
	var progress := FileAccess.open(STILL_DIR + progress_path, FileAccess.READ_WRITE)
	if progress == null:
		progress = FileAccess.open(STILL_DIR + progress_path, FileAccess.WRITE)
	if progress != null:
		progress.seek_end()
		progress.store_line("%d,%.4f,%.9f,%d" % [tick, water_m3, closure, memory_kb])
		progress.close()
	var now := Time.get_ticks_msec()
	if rows.size() == 1 or now - last_report_ms >= 60000:
		last_report_ms = now
		print("SAMPLE tick=%d water_m3=%.4f sediment_m3=%.6f closure_m3=%.9f mem_kb=%d elapsed_s=%.1f" % [
			tick, water_m3, sediment_m3, closure, memory_kb,
			float(now - started_ms) / 1000.0])


## One wall-time sample per rendered frame.
func _trace_frame() -> void:
	var now := Time.get_ticks_usec()
	if last_frame_usec > 0:
		frame_usec.append(now - last_frame_usec)
	last_frame_usec = now


## p50 / p95 / p99 / max of the frame times, in milliseconds.
func _frame_percentiles() -> Dictionary:
	if frame_usec.is_empty():
		return {"count": 0}
	var sorted := frame_usec.duplicate()
	sorted.sort()
	var count := sorted.size()
	var pick := func(q: float) -> float:
		return float(sorted[mini(int(float(count) * q), count - 1)]) / 1000.0
	return {"count": count, "p50": pick.call(0.50), "p95": pick.call(0.95),
		"p99": pick.call(0.99), "max": float(sorted[count - 1]) / 1000.0}


## Records static memory every tick and keeps any step large enough to be worth
## explaining, so the next long run pins the event instead of bracketing it.
func _trace_memory(tick: int) -> void:
	var memory_kb := OS.get_static_memory_usage() / 1024
	if memory_trace != null:
		memory_trace.store_line("%d,%d,%d" % [tick, memory_kb,
			memory_kb - previous_memory_kb])
	var delta := memory_kb - previous_memory_kb
	if previous_memory_kb > 0 and absi(delta) >= 512:
		memory_steps.append("tick=%d delta_kb=%d to_kb=%d" % [tick, delta, memory_kb])
	previous_memory_kb = memory_kb


func _finish_run() -> void:
	if rows.is_empty():
		_fail("no samples were taken")
		return
	var header := "tick,sim_time_s,water_m3,min_depth_m,sand_m3,sediment_m3," + \
		"sand_closure_m3,negative_cells,nonfinite_cells,memory_kb"
	var file := FileAccess.open(STILL_DIR + output_name, FileAccess.WRITE)
	if file == null:
		_fail("cannot open " + output_name)
		return
	file.store_line(header)
	for row in rows:
		file.store_line(row)
	file.close()
	if memory_trace != null:
		memory_trace.close()
		memory_trace = null
	if not memory_steps.is_empty():
		print("MEMORY_STEPS " + " | ".join(memory_steps))
	var frames := _frame_percentiles()
	if frames.get("count", 0) > 0:
		print("FRAMES count=%d p50=%.3f p95=%.3f p99=%.3f max=%.3f ms" % [
			frames["count"], frames["p50"], frames["p95"], frames["p99"], frames["max"]])
	print("PASS: T08 stability preset=%d ticks=%d samples=%d memory_first_kb=%d " % [
		preset, preview.completed_ticks, rows.size(), first_memory_kb] +
		"memory_max_kb=%d growth_kb=%d CSV=%s" % [
			max_memory_kb, max_memory_kb - first_memory_kb, output_name])
	_finish(0)


func _watchdog() -> void:
	while not finished:
		if Time.get_ticks_msec() - started_ms > 7200000:
			_fail("stability run exceeded its wall-clock budget at tick %d" % (
				preview.completed_ticks if preview != null else -1))
			return
		await process_frame


func _fail(message: String) -> void:
	if finished:
		return
	printerr("FAIL: " + message)
	_finish(1)


func _finish(code: int) -> void:
	if code != 0 and not rows.is_empty():
		## Keep the partial trend even when the run fails, so the failure has data.
		var file := FileAccess.open(STILL_DIR + output_name, FileAccess.WRITE)
		if file != null:
			file.store_line("tick,sim_time_s,water_m3,min_depth_m,sand_m3,sediment_m3," +
				"sand_closure_m3,negative_cells,nonfinite_cells,memory_kb")
			for row in rows:
				file.store_line(row)
			file.close()
	finished = true
	if preview != null:
		preview.queue_free()
	for _frame in 3:
		await process_frame
	quit(code)

extends SceneTree

const DEFAULT_CYCLES := 30
const CSV_PATH_FORMAT := "res://test_output/sandcastle_water_sand_coupling/验收/T03_gpu_preview_lifecycle_%d.csv"

var scene: PackedScene
var preview: Node3D
var cycle := 0
var target_cycles := DEFAULT_CYCLES
var finished := false
var started_ms := 0
var rows := PackedStringArray(["cycle,static_bytes,video_bytes"])
var video_samples := PackedInt64Array()
var static_samples := PackedInt64Array()


func _init() -> void:
	call_deferred("_begin")


func _begin() -> void:
	var requested := int(OS.get_environment("SANDCASTLE_PREVIEW_LIFECYCLE_CYCLES"))
	if requested > 0:
		target_cycles = requested
	scene = load("res://scenes/gpu_water_preview.tscn")
	if scene == null:
		_fail("GPU preview scene missing")
		return
	started_ms = Time.get_ticks_msec()
	call_deferred("_watchdog")
	call_deferred("_start_cycle")


func _start_cycle() -> void:
	if finished:
		return
	preview = scene.instantiate()
	root.add_child(preview)
	call_deferred("_wait_ready")


func _wait_ready() -> void:
	if finished:
		return
	if not preview.last_error.is_empty():
		_fail("preview cycle %d: %s" % [cycle, preview.last_error])
		return
	if not preview.ready_for_ticks:
		await process_frame
		call_deferred("_wait_ready")
		return
	preview.playing = false
	var error: StringName = preview._submit_brush(&"remove_sand", 0.015,
		Vector3.ZERO, Vector3.ZERO, &"circle")
	if not error.is_empty():
		_fail("preview cycle %d command rejected: %s" % [cycle, error])
		return
	# Destroy while the initial collision batches and/or edit callback may still be live.
	preview.queue_free()
	preview = null
	call_deferred("_after_destroy")


func _after_destroy() -> void:
	for frame in 8:
		await process_frame
	cycle += 1
	var static_bytes := int(Performance.get_monitor(Performance.MEMORY_STATIC))
	var video_bytes := int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED))
	static_samples.append(static_bytes)
	video_samples.append(video_bytes)
	rows.append("%d,%d,%d" % [cycle, static_bytes, video_bytes])
	if cycle % 5 == 0:
		print("PREVIEW_LIFECYCLE cycle=%d/%d static=%d video=%d" % [
			cycle, target_cycles, static_bytes, video_bytes])
	if cycle == target_cycles:
		var path := CSV_PATH_FORMAT % target_cycles
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			_fail("preview lifecycle CSV unavailable")
			return
		file.store_string("\n".join(rows) + "\n")
		file.close()
		var warm_index := mini(4, target_cycles - 1)
		var video_growth := video_samples[target_cycles - 1] - video_samples[warm_index]
		var static_growth := static_samples[target_cycles - 1] - static_samples[warm_index]
		print("PREVIEW_LIFECYCLE warm_to_final_static=%d warm_to_final_video=%d" % [
			static_growth, video_growth])
		if static_growth > 4 * 1024 * 1024 or video_growth > 4 * 1024 * 1024:
			_fail("preview resources grew after warmup static=%d video=%d" % [
				static_growth, video_growth])
			return
		finished = true
		print("PASS: GPU preview %d create/edit/destroy cycles; CSV=%s" % [
			target_cycles, path])
		quit(0)
		return
	call_deferred("_start_cycle")


func _watchdog() -> void:
	if finished:
		return
	if Time.get_ticks_msec() - started_ms > 180000:
		_fail("GPU preview lifecycle timed out at cycle %d" % cycle)
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

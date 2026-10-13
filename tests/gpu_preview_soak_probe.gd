extends SceneTree

const DEFAULT_SECONDS := 600
const CSV_PATH := "res://test_output/sandcastle_water_sand_coupling/验收/T03_gpu_preview_soak.csv"

var preview: Node3D
var duration_seconds := DEFAULT_SECONDS
var started_ms := 0
var last_sample_second := -30
var last_edit_second := 0
var edit_count := 0
var finished := false
var rows := PackedStringArray([
	"elapsed_s,ticks,edits,undo_snapshots,collision_chunks,invalid_readbacks,static_bytes,video_bytes,render_cpu_ms,render_gpu_ms"])
var warm_static := -1
var warm_video := -1


func _init() -> void:
	call_deferred("_begin")


func _begin() -> void:
	var requested := int(OS.get_environment("SANDCASTLE_PREVIEW_SOAK_SECONDS"))
	if requested > 0:
		duration_seconds = requested
	var scene: PackedScene = load("res://scenes/gpu_water_preview.tscn")
	if scene == null:
		_fail("GPU preview scene unavailable")
		return
	preview = scene.instantiate()
	root.add_child(preview)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	started_ms = Time.get_ticks_msec()
	call_deferred("_monitor")


func _monitor() -> void:
	if finished:
		return
	if not preview.last_error.is_empty() or preview.collision_proxy.invalid_readbacks > 0:
		_fail("preview error: %s collision_invalid=%d" % [
			preview.last_error, preview.collision_proxy.invalid_readbacks])
		return
	var elapsed := int((Time.get_ticks_msec() - started_ms) / 1000)
	if elapsed >= last_edit_second + 10 and preview.ready_for_ticks:
		var kind: StringName = &"remove_sand" if edit_count % 2 == 0 else &"place_sand"
		var error: StringName = preview._submit_brush(kind, 0.005,
			Vector3.ZERO, Vector3.ZERO, &"circle")
		if not error.is_empty():
			_fail("soak edit %d rejected: %s" % [edit_count, error])
			return
		edit_count += 1
		last_edit_second = elapsed
	if elapsed >= last_sample_second + 30:
		var static_bytes := int(Performance.get_monitor(Performance.MEMORY_STATIC))
		var video_bytes := int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED))
		var render_cpu_ms := RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid())
		var render_gpu_ms := RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid())
		rows.append("%d,%d,%d,%d,%d,%d,%d,%d,%.6f,%.6f" % [
			elapsed, preview.completed_ticks, edit_count,
			preview.command_queue.undo_stack.size(),
			preview.collision_proxy.shapes.size(),
			preview.collision_proxy.invalid_readbacks,
			static_bytes, video_bytes, render_cpu_ms, render_gpu_ms])
		print("SOAK elapsed=%d/%d ticks=%d edits=%d undo=%d chunks=%d static=%d video=%d" % [
			elapsed, duration_seconds, preview.completed_ticks, edit_count,
			preview.command_queue.undo_stack.size(),
			preview.collision_proxy.shapes.size(), static_bytes, video_bytes])
		if warm_static < 0 and (preview.command_queue.undo_stack.size() >=
				preview.command_queue.MAX_UNDO or duration_seconds < 600 and elapsed >= 30):
			warm_static = static_bytes
			warm_video = video_bytes
		last_sample_second = elapsed
	if elapsed >= duration_seconds:
		_finish()
		return
	await process_frame
	call_deferred("_monitor")


func _finish() -> void:
	var static_bytes := int(Performance.get_monitor(Performance.MEMORY_STATIC))
	var video_bytes := int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED))
	var file := FileAccess.open(CSV_PATH, FileAccess.WRITE)
	if file == null:
		_fail("soak CSV unavailable")
		return
	file.store_string("\n".join(rows) + "\n")
	file.close()
	if preview.completed_ticks < 30 or preview.collision_proxy.shapes.size() != 64:
		_fail("soak did not run an initialized preview")
		return
	if duration_seconds >= 600 and edit_count < 50:
		_fail("10-minute soak did not exercise enough edits")
		return
	if duration_seconds >= 600 and warm_static < 0:
		_fail("10-minute soak did not fill the bounded undo history")
		return
	if warm_static >= 0 and (static_bytes - warm_static > 4 * 1024 * 1024 or
			video_bytes - warm_video > 4 * 1024 * 1024):
		_fail("soak memory grew after warmup static=%d video=%d" % [
			static_bytes - warm_static, video_bytes - warm_video])
		return
	print("SOAK bounded_history_to_final_static=%d bounded_history_to_final_video=%d" % [
		static_bytes - warm_static, video_bytes - warm_video])
	finished = true
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), false)
	preview.queue_free()
	print("PASS: GPU preview %d-second edit soak ticks=%d edits=%d CSV=%s" % [
		duration_seconds, preview.completed_ticks, edit_count, CSV_PATH])
	quit(0)


func _fail(message: String) -> void:
	if finished:
		return
	finished = true
	printerr("FAIL: " + message)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), false)
	if preview != null:
		preview.queue_free()
	quit(1)

extends SceneTree

## T08 G02: generation / async callback safety.
##
## Every async path in the preview is bound to a generation token and bails out
## when `token != generation`. The dangerous case is a scene being replaced while
## readbacks are still in flight: the callback lands on an old generation, or on a
## freed node, and must do nothing.
##
## This probe starts a full shadow sync on one preview - which leaves several
## async readbacks outstanding - and destroys that preview immediately, then
## brings up a fresh one and runs it. Passing means the stale callbacks neither
## crashed the process nor disturbed the replacement scene.

const SETTLE_FRAMES := 30
const RUN_TICKS := 90

var finished := false
var started_ms := 0
var failures: Array[String] = []
var results: Array[String] = []
var first: Node3D
var second: Node3D


func _init() -> void:
	call_deferred("_watchdog")
	call_deferred("_begin")


func _begin() -> void:
	started_ms = Time.get_ticks_msec()
	first = _spawn()
	if first == null:
		return
	call_deferred("_wait_first_ready")


func _spawn() -> Node3D:
	var scene: PackedScene = load("res://scenes/gpu_water_preview.tscn")
	if scene == null:
		_fail("preview scene unavailable")
		return null
	var preview: Node3D = scene.instantiate()
	preview.preset_index = 1
	preview.enable_erosion = true
	preview.hide_hud = true
	root.add_child(preview)
	return preview


func _wait_first_ready() -> void:
	while not finished:
		if not first.last_error.is_empty():
			_fail(first.last_error)
			return
		if first.ready_for_ticks and first.completed_ticks >= 60:
			break
		await process_frame
	if finished:
		return
	_replace_mid_flight()


## Leaves async readbacks outstanding on `first`, then replaces it.
func _replace_mid_flight() -> void:
	var revision_before: int = first.solver.state_revision
	first.playing = false
	var waited := 0
	while not finished and first.tick_pending and waited < 600:
		await process_frame
		waited += 1
	if finished:
		return
	if first.shadow_revision != revision_before and \
			first.shadow_sync_reason.is_empty():
		first._request_shadow_sync("debug")
	## `_request_shadow_sync` sets tick_pending and dispatches several
	## texture_get_data_async calls bound to this scene's generation.
	var dispatched_mid_flight: bool = first.tick_pending
	if not dispatched_mid_flight:
		failures.append("could not leave a readback in flight to test against")
		_finish_run()
		return
	## Destroy it on the very next frame, while the callbacks are outstanding.
	await process_frame
	root.remove_child(first)
	first.queue_free()
	first = null
	second = _spawn()
	if second == null:
		return
	call_deferred("_wait_second_ready", dispatched_mid_flight)


func _wait_second_ready(dispatched_mid_flight: bool) -> void:
	while not finished:
		if not second.last_error.is_empty():
			_fail("replacement scene reported: " + second.last_error)
			return
		if second.ready_for_ticks and second.completed_ticks >= RUN_TICKS:
			break
		await process_frame
	if finished:
		return
	_check_second(dispatched_mid_flight)


## The replacement must run normally, and its state must be clean.
func _check_second(dispatched_mid_flight: bool) -> void:
	for _frame in SETTLE_FRAMES:
		await process_frame
	if not second.last_error.is_empty():
		_fail("replacement scene errored after the swap: " + second.last_error)
		return
	RenderingServer.call_on_render_thread(_render_read.bind(dispatched_mid_flight))


func _render_read(dispatched_mid_flight: bool) -> void:
	for field in ["water", "sand"]:
		if second.solver.request_data(field,
				_on_field.bind(field, dispatched_mid_flight)) != OK:
			call_deferred("_fail", "replacement readback request failed: " + field)
			return


func _on_field(data: PackedByteArray, field: String,
		dispatched_mid_flight: bool) -> void:
	call_deferred("_record", data, field, dispatched_mid_flight)


var _readbacks := {}


func _record(data: PackedByteArray, field: String,
		dispatched_mid_flight: bool) -> void:
	if finished:
		return
	_readbacks[field] = data.to_float32_array()
	if _readbacks.size() < 2:
		return
	var nonfinite := 0
	var negative := 0
	var water_m3 := 0.0
	for i in 256 * 256:
		var depth: float = _readbacks["water"][i]
		var sand: float = _readbacks["sand"][i]
		if not is_finite(depth) or not is_finite(sand):
			nonfinite += 1
			continue
		if depth < -0.000001 or sand < -0.000001:
			negative += 1
		water_m3 += depth * 0.125 * 0.125
	if nonfinite > 0 or negative > 0:
		failures.append("replacement state invalid: nonfinite=%d negative=%d" % [
			nonfinite, negative])
	else:
		results.append("SWAP_OK in_flight_readbacks=%s" % str(dispatched_mid_flight))
		results.append("REPLACEMENT_OK ticks=%d generation=%d" % [
			second.completed_ticks, second.generation])
		results.append("STATE_OK water_m3=%.6f negative=0 nonfinite=0" % water_m3)
	_finish_run()


func _watchdog() -> void:
	while not finished:
		if Time.get_ticks_msec() - started_ms > 600000:
			_fail("generation safety probe timed out")
			return
		await process_frame


func _fail(message: String) -> void:
	if finished:
		return
	printerr("FAIL: " + message)
	_finish_run(1)


func _finish_run(code := 0) -> void:
	if finished:
		return
	finished = true
	if not failures.is_empty():
		for failure in failures:
			printerr("FAIL: " + failure)
		code = 1
	else:
		for line in results:
			print(line)
		print("PASS: T08 generation safety stale_callbacks_dropped=true")
	if second != null and is_instance_valid(second):
		second.queue_free()
	for _frame in 3:
		await process_frame
	quit(code)

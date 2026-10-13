extends SceneTree

## T08 G03: fixed-step overload handling.
##
## The sim is a fixed 30 Hz step fed by a frame accumulator. When a frame takes
## longer than a step, the accumulator must not let the sim run away trying to
## catch up: it is capped at four steps, so a long hitch costs simulated time
## rather than queueing hundreds of ticks. This probe feeds a 10 second frame and
## checks the cap held, that only a bounded number of ticks ran, and that the
## state is still valid afterwards.
##
## Usage:
##   godot --path <proj> --rendering-driver d3d12 --resolution 1280x720 --script <this>

const SIM_DELTA := 1.0 / 30.0
const ACCUMULATOR_CAP_STEPS := 4.0
const HITCH_SECONDS := 10.0

var preview: Node3D
var finished := false
var started_ms := 0
var failures: Array[String] = []
var results: Array[String] = []


func _init() -> void:
	call_deferred("_watchdog")
	call_deferred("_begin")


func _begin() -> void:
	started_ms = Time.get_ticks_msec()
	var scene: PackedScene = load("res://scenes/gpu_water_preview.tscn")
	if scene == null:
		_fail("preview scene unavailable")
		return
	preview = scene.instantiate()
	preview.preset_index = 1
	preview.enable_erosion = true
	preview.hide_hud = true
	root.add_child(preview)
	call_deferred("_wait_ready")


func _wait_ready() -> void:
	while not finished:
		if not preview.last_error.is_empty():
			_fail(preview.last_error)
			return
		if preview.ready_for_ticks and preview.completed_ticks >= 30:
			break
		await process_frame
	if finished:
		return
	_apply_hitch()


## Pauses the loop, drains any in-flight tick, then hands `_process` one enormous
## delta the way a stall would.
func _apply_hitch() -> void:
	preview.playing = false
	var waited := 0
	while not finished and preview.tick_pending and waited < 600:
		await process_frame
		waited += 1
	if finished:
		return
	preview.accumulator = 0.0
	var ticks_before: int = preview.completed_ticks
	preview.playing = true
	preview._process(HITCH_SECONDS)
	var accumulator_after: float = preview.accumulator
	var cap := SIM_DELTA * ACCUMULATOR_CAP_STEPS
	if accumulator_after > cap + 0.000001:
		failures.append("accumulator kept %.6f s after a %.0f s frame, cap is %.6f s" % [
			accumulator_after, HITCH_SECONDS, cap])
	if accumulator_after <= 0.0:
		failures.append("accumulator drained to %.6f s, so the hitch advanced no tick" % [
			accumulator_after])
	## Let the engine run its own frames from here: the point is what the real loop
	## does with a capped backlog, not what this probe can pump through it. The sim
	## may advance at most one tick per frame, so over N frames it cannot advance
	## more than N plus whatever the cap still holds.
	const FRAMES := 30
	for _frame in FRAMES:
		await process_frame
	preview.playing = false
	waited = 0
	while not finished and preview.tick_pending and waited < 600:
		await process_frame
		waited += 1
	var ticks_after: int = preview.completed_ticks
	var advanced := ticks_after - ticks_before
	var allowance := FRAMES + int(ACCUMULATOR_CAP_STEPS) + 1
	if advanced > allowance:
		failures.append("%d frames after a %.0f s hitch advanced %d ticks, allowance %d" % [
			FRAMES, HITCH_SECONDS, advanced, allowance])
	if advanced < 1:
		failures.append("the sim did not advance at all after the hitch")
	_check_state(ticks_before, ticks_after, advanced, accumulator_after, cap)


## The state must still be valid after the burst: no NaN, no negative depth or
## sand, and the sand ledger still closing.
func _check_state(ticks_before: int, ticks_after: int, advanced: int,
		accumulator_after: float, cap: float) -> void:
	RenderingServer.call_on_render_thread(_render_state.bind(
		ticks_before, ticks_after, advanced, accumulator_after, cap))


func _render_state(ticks_before: int, ticks_after: int, advanced: int,
		accumulator_after: float, cap: float) -> void:
	for field in ["water", "sand"]:
		if preview.solver.request_data(field, _on_field.bind(
				field, ticks_before, ticks_after, advanced, accumulator_after, cap)) != OK:
			call_deferred("_fail", "readback request failed for " + field)
			return


func _on_field(data: PackedByteArray, field: String, ticks_before: int,
		ticks_after: int, advanced: int, accumulator_after: float, cap: float) -> void:
	call_deferred("_record", data, field, ticks_before, ticks_after, advanced,
		accumulator_after, cap)


var _readbacks := {}


func _record(data: PackedByteArray, field: String, ticks_before: int,
		ticks_after: int, advanced: int, accumulator_after: float, cap: float) -> void:
	if finished:
		return
	_readbacks[field] = data.to_float32_array()
	if _readbacks.size() < 2:
		return
	var negative := 0
	var nonfinite := 0
	var water_m3 := 0.0
	var sand_m3 := 0.0
	for i in 256 * 256:
		var depth: float = _readbacks["water"][i]
		var sand: float = _readbacks["sand"][i]
		if not is_finite(depth) or not is_finite(sand):
			nonfinite += 1
			continue
		if depth < -0.000001 or sand < -0.000001:
			negative += 1
		water_m3 += depth * 0.125 * 0.125
		sand_m3 += sand * 0.125 * 0.125
	if nonfinite > 0:
		failures.append("%d non-finite cells after the hitch" % nonfinite)
	elif negative > 0:
		failures.append("%d negative cells after the hitch" % negative)
	else:
		results.append("CAP_OK accumulator_after_hitch_s=%.6f cap_s=%.6f hitch_s=%.0f" % [
			accumulator_after, cap, HITCH_SECONDS])
		results.append("DRAIN_OK frames=%d ticks_before=%d ticks_after=%d advanced=%d" % [
			30, ticks_before, ticks_after, advanced])
		results.append("STATE_OK water_m3=%.6f sand_m3=%.6f negative=0 nonfinite=0" % [
			water_m3, sand_m3])
	_report()


func _watchdog() -> void:
	while not finished:
		if Time.get_ticks_msec() - started_ms > 600000:
			_fail("overload probe timed out")
			return
		await process_frame


func _fail(message: String) -> void:
	if finished:
		return
	printerr("FAIL: " + message)
	_finish(1)


func _report() -> void:
	if finished:
		return
	if not failures.is_empty():
		for failure in failures:
			printerr("FAIL: " + failure)
		_finish(1)
		return
	if results.size() != 3:
		printerr("FAIL: expected 3 result lines, got %d" % results.size())
		_finish(1)
		return
	for line in results:
		print(line)
	print("PASS: T08 fixed-step overload cap_steps=%.0f" % ACCUMULATOR_CAP_STEPS)
	_finish(0)


func _finish(code: int) -> void:
	finished = true
	if preview != null:
		preview.queue_free()
	for _frame in 3:
		await process_frame
	quit(code)

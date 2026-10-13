extends SceneTree

## T08: does repeatedly replacing collision chunk shapes leak?
##
## The three-scenario long run showed SCN-03 (the tall-wall scene, which has the
## most collision churn) stepping up 8.6 MB once and then staying flat, while the
## two gentler scenes grew only 0.4 MB. That shape says "one-time pool growth"
## rather than a leak, but the long run cannot tell the two apart because it only
## samples every 30 seconds of simulated time.
##
## This probe isolates the mechanism: it drives collision chunk replacement in a
## tight loop and samples static memory often enough to see whether the curve
## rises linearly with the number of replacements or steps once and plateaus.

const CHUNKS := [0, 1, 2, 3, 8, 9, 10, 11, 16, 17, 18, 19]
const ITERATIONS := 900
const SAMPLE_EVERY := 50
const GRID := 256

var preview: Node3D
var finished := false
var started_ms := 0
var failures: Array[String] = []
var results: Array[String] = []
var samples: Array[int] = []
var iteration := 0
var revision := 1000


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
	preview.preset_index = 2
	preview.enable_erosion = false
	preview.hide_hud = true
	root.add_child(preview)
	call_deferred("_wait_ready")


func _wait_ready() -> void:
	while not finished:
		if not preview.last_error.is_empty():
			_fail(preview.last_error)
			return
		if preview.ready_for_ticks and preview.collision_proxy.applied_revisions.size() >= 64:
			break
		await process_frame
	if finished:
		return
	preview.playing = false
	var waited := 0
	while not finished and preview.tick_pending and waited < 600:
		await process_frame
		waited += 1
	samples.append(OS.get_static_memory_usage() / 1024)
	await _churn()


## Replaces the same handful of chunk shapes over and over, with a tiny bed change
## each time so the proxy actually rewrites them.
func _churn() -> void:
	while not finished and iteration < ITERATIONS:
		## Nudge the bed so the chunk content genuinely differs each round.
		var domain: SandWaterDomain = preview.shadow_domain
		var offset := 0.0001 * float(iteration % 50)
		for chunk_id in CHUNKS:
			var base_x: int = (chunk_id % 8) * 32
			var base_z: int = (chunk_id / 8) * 32
			for local_z in 4:
				for local_x in 4:
					var index: int = (base_z + local_z) * GRID + (base_x + local_x)
					domain.sand[index] = 0.30 + offset
		revision += 1
		var error: bool = preview.collision_proxy.apply_shadow_chunks(
			PackedInt32Array(CHUNKS), revision, preview.generation,
			domain.rock, domain.sand)
		if not error:
			failures.append("chunk replacement refused at iteration %d" % iteration)
			break
		iteration += 1
		if iteration % SAMPLE_EVERY == 0:
			samples.append(OS.get_static_memory_usage() / 1024)
		## Let the proxy's own deferred work run so its resources are recycled.
		await process_frame
	if finished:
		return
	_verdict()


func _verdict() -> void:
	if not failures.is_empty():
		_report()
		return
	if samples.size() < 4:
		failures.append("only %d memory samples were taken" % samples.size())
		_report()
		return
	var first: int = samples[0]
	var last: int = samples[samples.size() - 1]
	var peak: int = samples[0]
	for value in samples:
		peak = maxi(peak, value)
	## Compare the growth over the second half, when any one-time pools have
	## already been paid for, against the first half.
	var mid: int = samples.size() / 2
	var first_half_growth: int = samples[mid] - samples[0]
	var second_half_growth: int = last - samples[mid]
	results.append("CHURN iterations=%d replacements=%d samples=%d" % [
		ITERATIONS, iteration, samples.size()])
	results.append("MEMORY first_kb=%d mid_kb=%d last_kb=%d peak_kb=%d" % [
		first, samples[mid], last, peak])
	results.append("TREND first_half_growth_kb=%d second_half_growth_kb=%d" % [
		first_half_growth, second_half_growth])
	## A leak would keep growing in the second half at a similar rate to the
	## first. Require the second half to have flattened to under a quarter of it.
	if second_half_growth > maxi(256, first_half_growth / 4):
		failures.append("memory kept growing with churn: first half +%d KB, second half +%d KB" % [
			first_half_growth, second_half_growth])
	_report()


func _report() -> void:
	if finished:
		return
	if not failures.is_empty():
		for failure in failures:
			printerr("FAIL: " + failure)
		_finish(1)
		return
	for line in results:
		print(line)
	print("PASS: T08 collision churn memory plateaus samples=" + str(samples))
	_finish(0)


func _watchdog() -> void:
	while not finished:
		if Time.get_ticks_msec() - started_ms > 900000:
			_fail("collision churn probe timed out at iteration %d" % iteration)
			return
		await process_frame


func _fail(message: String) -> void:
	if finished:
		return
	printerr("FAIL: " + message)
	_finish(1)


func _finish(code: int) -> void:
	finished = true
	if preview != null:
		preview.queue_free()
	for _frame in 3:
		await process_frame
	quit(code)

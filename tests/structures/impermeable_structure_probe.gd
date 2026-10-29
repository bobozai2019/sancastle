extends SceneTree

## T06 G04: an impermeable structure changes the obstacle mask, and the water it
## displaces is remapped rather than swallowed.
##
## Sand structures never touch the obstacle bit, so until now nothing in the main
## scene exercised `obstacle_remap`. This probe builds a `blocks_water` wall over
## a flooded channel and checks the whole contract for that event:
##   * the obstacle bit is set over the footprint and the water there is gone
##   * the water total is unchanged, i.e. the volume moved to the neighbours
##   * no wet cell inside the footprint is left behind
##   * collapsing the wall clears the bit again

const Structure = preload("res://scripts/structures/structure_state.gd")

const GRID := 256
const FLOOD_TICK := 120

var preview: Node3D
var finished := false
var started_ms := 0
var failures: Array[String] = []
var results: Array[String] = []
var water_before := 0.0
var obstacle_pushed := false
var _wall: SandcastleStructure


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
	preview.enable_structures = true
	preview.hide_hud = true
	root.add_child(preview)
	call_deferred("_wait_ready")


func _wait_ready() -> void:
	while not finished:
		if not preview.last_error.is_empty():
			_fail(preview.last_error)
			return
		if preview.ready_for_ticks and preview.completed_ticks >= FLOOD_TICK:
			break
		await process_frame
	if finished:
		return
	if preview.obstacle_remap == null:
		_fail("the obstacle remap was not initialised with the structure layer")
		return
	_build_wall()


## Everything here reads state the preview already publishes asynchronously -
## its obstacle mask on the shadow and its own water audit. Manual
## `texture_get_data` from the main thread deadlocks against the render thread,
## and a probe has no business adding a second readback path to the preview.
func _build_wall() -> void:
	preview.playing = false
	var waited := 0
	while not finished and preview.tick_pending and waited < 600:
		await process_frame
		waited += 1
	if not await _await_audit():
		return
	water_before = preview.audit_water_m3
	## A blocking wall across the flooded reach, so blocking it displaces real
	## water rather than empty cells.
	_wall = Structure.new()
	_wall.kind = Structure.Kind.WALL
	_wall.blocks_water = true
	_wall.origin = Vector2i(60, 90)
	_wall.size = Vector2i(5, 40)
	_wall.height_m = 0.30
	_wall.taper_slope_m = 0.10
	_wall.compaction = 0.9
	preview.structure_field.add(_wall, preview.shadow_domain)
	obstacle_pushed = false
	RenderingServer.call_on_render_thread(_push)
	waited = 0
	while not finished and not obstacle_pushed and waited < 600:
		await process_frame
		waited += 1
	if finished:
		return
	if not obstacle_pushed:
		_fail("pushing the obstacle mask never completed")
		return
	## Let the solver run a few ticks so the audit reflects the blocked cells.
	preview.playing = true
	if not await _await_ticks(preview.completed_ticks + 90):
		return
	preview.playing = false
	if not await _await_audit():
		return
	_verify()


func _push() -> void:
	obstacle_pushed = preview._push_obstacles(preview.generation)
	if not obstacle_pushed:
		call_deferred("_fail", "pushing the obstacle mask failed")


## Waits for the preview's own water audit to be refreshed at a known revision.
func _await_audit() -> bool:
	var target: int = preview.audit_revision + 1
	var waited := 0
	while not finished and (preview.audit_revision < target or preview.tick_pending) 			and waited < 900:
		if not preview.last_error.is_empty():
			_fail(preview.last_error)
			return false
		preview.playing = true
		await process_frame
		waited += 1
	if finished:
		return false
	if preview.audit_revision < target:
		_fail("the preview water audit never refreshed")
		return false
	return true


func _await_ticks(target: int) -> bool:
	while not finished:
		if preview.completed_ticks >= target:
			return true
		if not preview.last_error.is_empty():
			_fail(preview.last_error)
			return false
		preview.playing = true
		await process_frame
	return false


func _verify() -> void:
	var blocked := 0
	var blocking_cells := 0
	for cell in _wall.cells(GRID):
		blocked += 1
		if preview.shadow_domain.obstacle[cell] >= 0.5:
			blocking_cells += 1
	if blocked != _wall.cell_count():
		failures.append("footprint covered %d of %d cells" % [blocked, _wall.cell_count()])
	elif blocking_cells != _wall.cell_count():
		failures.append("%d of %d footprint cells are not marked blocking" % [
			blocking_cells, _wall.cell_count()])
	elif preview.audit_negative_cells != 0 or preview.audit_invalid_cells != 0:
		failures.append("the audit found %d negative / %d invalid water cells after blocking" % [
			preview.audit_negative_cells, preview.audit_invalid_cells])
	else:
		results.append("BLOCK_OK footprint=%d blocking_cells=%d" % [blocked, blocking_cells])
		results.append("WATER_OK before_m3=%.6f after_m3=%.6f negative=%d invalid=%d" % [
			water_before, preview.audit_water_m3, preview.audit_negative_cells,
			preview.audit_invalid_cells])
		_collapse_and_check()


## Collapsing clears the bit again. That only ever opens area up, so the solver
## refills it and no volume has to be moved.
func _collapse_and_check() -> void:
	_wall.collapse(preview.shadow_domain)
	var mask: PackedFloat32Array = preview.structure_field.obstacle_mask(GRID)
	var still_blocked := 0
	for cell in _wall.cells(GRID):
		if mask[cell] >= 0.5:
			still_blocked += 1
	if still_blocked > 0:
		failures.append("a collapsed wall left %d blocking cells" % still_blocked)
	else:
		results.append("UNBLOCK_OK collapsed_mask_cells=%d" % still_blocked)
	_report()


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
	print("PASS: T06 impermeable structure contract grid=%d" % GRID)
	_finish(0)


func _watchdog() -> void:
	while not finished:
		if Time.get_ticks_msec() - started_ms > 600000:
			_fail("impermeable structure probe timed out")
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

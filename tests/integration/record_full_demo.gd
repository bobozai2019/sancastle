extends SceneTree

## T08 G06: the uncut end-to-end demo.
##
## One continuous take on the 256² coupled main entry, no cuts and no overlays
## removed mid-shot, walking the whole acceptance chain the细则 lists:
## dig a channel -> build a wall from the spoil -> let the tide rise -> erosion ->
## the wall is undermined and collapses -> downstream deposition.
##
## Every edit goes through the production paths: `_submit_brush` for sand and
## `place_structure_at_world` for the wall, which spends the tool bucket.
##
## Usage:
##   godot --path <proj> --rendering-driver d3d12 --fixed-fps 30 \
##     --write-movie <staging>.avi --script <this> [-- --stills-only]

const Structure = preload("res://scripts/structures/structure_state.gd")

const STILL_DIR := "res://test_output/sandcastle_water_sand_coupling/验收/"
const CAMERA_POSITION := Vector3(2.5, 5.2, 8.0)
const CAMERA_TARGET := Vector3(4.0, 0.05, -0.5)

## Timeline in 30 Hz ticks.
const DIG_TICK := 240
const BUILD_TICK := 420
const UNDERMINE_TICK := 600
const FINAL_TICK := 1800

var main: Node3D
var preview: Node3D
var finished := false
var started_ms := 0
var stills: Array[String] = []
var dug_m3 := 0.0
var wall_booked := 0.0
var wall_collapsed := false


func _init() -> void:
	call_deferred("_watchdog")
	call_deferred("_begin")


func _scene() -> Node3D:
	return main.active_scene if main != null else null


func _begin() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	if scene == null:
		_fail("main scene unavailable")
		return
	main = scene.instantiate()
	main.selected_preset = 1
	main.enable_gpu_erosion = true
	main.enable_structures = true
	main.hide_hud = false
	main.show_brush_indicator = false
	main.use_player_camera = true
	main.player_camera_position = CAMERA_POSITION
	main.player_camera_target = CAMERA_TARGET
	root.add_child(main)
	started_ms = Time.get_ticks_msec()
	call_deferred("_run")


func _run() -> void:
	while not finished:
		var scene := _scene()
		if scene != null and not scene.last_error.is_empty():
			_fail(scene.last_error)
			return
		if scene != null and scene.ready_for_ticks and scene.completed_ticks >= DIG_TICK:
			break
		await process_frame
	if finished:
		return
	preview = _scene()
	## Beat 1: the player digs a channel and keeps the spoil, until the bucket
	## can actually pay for the wall. Placing is funded by the bucket, so digging
	## is not decoration here - it is the only source of building material.
	_brush_drag(&"remove_sand", 0.06, Vector3(0.5, 0.0, -3.2), Vector3(3.5, 0.0, -0.2), 5)
	var borrows: Array[Vector3] = [Vector3(5.6, 0.0, 5.4), Vector3(6.4, 0.0, 6.0),
		Vector3(7.2, 0.0, 5.6), Vector3(8.0, 0.0, 6.2), Vector3(8.8, 0.0, 5.6),
		Vector3(9.6, 0.0, 6.0), Vector3(10.4, 0.0, 5.4), Vector3(11.2, 0.0, 5.9)]
	var dig_index := 0
	while not finished and preview.shadow_domain.tool_inventory_m3 < 0.75 and 			dig_index < borrows.size():
		_brush_circle(&"remove_sand", 0.08, borrows[dig_index])
		dig_index += 1
		if not await _await_tick(preview.completed_ticks + 8):
			return
	dug_m3 = preview.shadow_domain.tool_inventory_m3
	if not await _still("dig"):
		return
	if dug_m3 < 0.75:
		_fail("could not dig enough spoil to fund the wall: %.4f m3" % dug_m3)
		return

	## Beat 2: build a wall from the spoil. `request_build_structure` refuses
	## while a tick is in flight, so wait for a quiet boundary and retry.
	if not await _await_tick(BUILD_TICK):
		return
	if not await _place_wall():
		return
	wall_booked = preview.last_structure_booked_m3
	if not await _still("wall"):
		return

	## Beat 3: undermine the wall's flank with the brush.
	if not await _await_tick(UNDERMINE_TICK):
		return
	_brush_drag(&"remove_sand", 0.06, Vector3(4.55, 0.0, -1.2), Vector3(4.55, 0.0, 2.6), 5)
	_brush_drag(&"remove_sand", 0.06, Vector3(5.85, 0.0, -1.2), Vector3(5.85, 0.0, 2.6), 5)
	if not await _still("undermined"):
		return

	## Beat 4: run the tide out and watch erosion, collapse and deposition.
	if not await _await_tick(FINAL_TICK):
		return
	wall_collapsed = _any_collapsed()
	print("DEMO wall_structures=%d collapsed=%d" % [
		preview.structure_field.structures.size(), preview.structures_collapsed])
	if not await _still("final"):
		return
	_report()


func _await_tick(target: int) -> bool:
	while not finished:
		var scene := _scene()
		if scene == null:
			_fail("active scene disappeared before tick %d" % target)
			return false
		if not scene.last_error.is_empty():
			_fail(scene.last_error)
			return false
		if scene.completed_ticks >= target:
			return true
		await process_frame
	return false


## Places the wall on a tick boundary, retrying until the preview accepts it.
func _place_wall() -> bool:
	var attempts := 0
	while not finished and attempts < 60:
		if not preview.last_error.is_empty():
			_fail(preview.last_error)
			return false
		if preview.tick_pending or not preview.ready_for_ticks:
			await process_frame
			continue
		attempts += 1
		if preview.place_structure_at_world(Structure.Kind.WALL, Vector3(5.2, 0.0, 0.6)):
			return await _await_build()
		await process_frame
	_fail("could not get the wall placement accepted")
	return false


func _await_build() -> bool:
	var waited := 0
	while not finished and preview.last_structure_booked_m3 <= 0.0 and waited < 900:
		if not preview.last_error.is_empty():
			_fail(preview.last_error)
			return false
		await process_frame
		waited += 1
	if finished:
		return false
	if preview.last_structure_booked_m3 <= 0.0:
		_fail("the wall build never completed: " + preview.last_structure_error)
		return false
	return true


func _brush_circle(kind: StringName, amount: float, at: Vector3) -> void:
	var error: StringName = preview._submit_brush(kind, amount, at, at, &"circle")
	if not error.is_empty():
		_fail("demo brush rejected (%s): %s" % [kind, error])


func _brush_drag(kind: StringName, amount: float, from: Vector3, to: Vector3,
		passes: int) -> void:
	for _pass_index in passes:
		var error: StringName = preview._submit_brush(kind, amount, from, to,
			&"swept_segment")
		if not error.is_empty():
			_fail("demo brush rejected (%s): %s" % [kind, error])


## True when any structure in the field has collapsed.
func _any_collapsed() -> bool:
	if preview.structure_field == null:
		return false
	for structure in preview.structure_field.structures:
		if structure.collapsed:
			return true
	return false


func _still(stage: String) -> bool:
	await RenderingServer.frame_post_draw
	if finished:
		return false
	var name := "T08_demo_%s_20260929.png" % stage
	var error: Error = root.get_texture().get_image().save_png(STILL_DIR + name)
	if error != OK:
		_fail("still save failed for %s: %d" % [stage, error])
		return false
	stills.append(name)
	return true


func _report() -> void:
	var scene := _scene()
	scene.playing = false
	var waited := 0
	while not finished and (scene.tick_pending or
			scene.collision_proxy.pending_revisions.size() > 0) and waited < 900:
		await process_frame
		waited += 1
	print("PASS: T08 demo ticks=%d dug_m3=%.6f wall_booked_m3=%.6f collapsed=%s stills=%s" % [
		scene.completed_ticks, dug_m3, wall_booked, str(wall_collapsed), ",".join(stills)])
	_finish(0)


func _watchdog() -> void:
	while not finished:
		if Time.get_ticks_msec() - started_ms > 1800000:
			_fail("demo recording timed out")
			return
		await process_frame


func _fail(message: String) -> void:
	if finished:
		return
	printerr("FAIL: " + message)
	_finish(1)


func _finish(code: int) -> void:
	finished = true
	if main != null:
		main.queue_free()
	for _frame in 3:
		await process_frame
	quit(code)

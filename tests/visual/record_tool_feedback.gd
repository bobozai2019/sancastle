extends SceneTree

## T07 G04: 30 second tool-interaction recording.
##
## Drives the real cursor with `Input.warp_mouse` so the brush ring follows it the
## way it does for a player, and issues the same `_submit_brush` calls the mouse
## handler makes. The clip covers hovering with the ring visible, digging a
## trench, dumping the spoil back, and building a wall from the bucket.
##
## Usage:
##   godot --path <proj> --rendering-driver d3d12 --fixed-fps 30 \
##     --write-movie <staging>.avi --script <this> [-- --stills-only]

const Structure = preload("res://scripts/structures/structure_state.gd")

const STILL_DIR := "res://test_output/sandcastle_water_sand_coupling/验收/"
const CAMERA_POSITION := Vector3(1.0, 6.2, 8.0)
const CAMERA_TARGET := Vector3(2.0, 0.05, -1.0)
## Timeline in 30 Hz ticks. Four dig and four place steps of 60 ticks each follow
## the hover, then the wall goes up, and the clip ends at 900 ticks = the 30
## seconds the细则 asks for.
const HOVER_TICKS := 180
const STEP_TICKS := 60
const STEPS := 4
const BUILD_TICK := 720
const FINAL_TICK := 900

var preview: Node3D
var finished := false
var started_ms := 0
var stills_only := false
var stills: Array[String] = []


func _init() -> void:
	stills_only = "--stills-only" in OS.get_cmdline_user_args()
	call_deferred("_watchdog")
	call_deferred("_begin")


func _begin() -> void:
	var scene: PackedScene = load("res://scenes/gpu_water_preview.tscn")
	if scene == null:
		_fail("preview scene unavailable")
		return
	preview = scene.instantiate()
	preview.preset_index = 1
	preview.enable_erosion = true
	preview.enable_structures = true
	preview.hide_hud = true
	preview.use_player_camera = true
	preview.player_camera_position = CAMERA_POSITION
	preview.player_camera_target = CAMERA_TARGET
	root.add_child(preview)
	started_ms = Time.get_ticks_msec()
	call_deferred("_run")


func _run() -> void:
	while not finished:
		if not preview.last_error.is_empty():
			_fail(preview.last_error)
			return
		if preview.ready_for_ticks and preview.completed_ticks >= HOVER_TICKS:
			break
		await process_frame
	if finished:
		return
	if not await _still("T07_tool_feedback_hover_20260929.png"):
		return
	await _dig()
	if finished:
		return
	if not await _still("T07_tool_feedback_dig_20260929.png"):
		return
	await _place()
	if finished:
		return
	preview.active_brush_kind = &""
	await _build_wall()
	if finished:
		return
	if not await _still("T07_tool_feedback_wall_20260929.png"):
		return
	preview.active_brush_kind = &""
	while not finished and preview.completed_ticks < FINAL_TICK:
		await process_frame
	if finished:
		return
	print("PASS: T07 tool feedback ticks=%d stills=%s" % [
		preview.completed_ticks, ",".join(stills)])
	_finish(0)


func _screens() -> Array[Vector2]:
	return [Vector2(700.0, 430.0), Vector2(640.0, 470.0), Vector2(560.0, 520.0),
		Vector2(480.0, 560.0)]


## Sweeps the cursor down the beach so the ring is clearly visible before any
## edit happens.
func _dig() -> void:
	var points := _screens()
	for step in STEPS:
		Input.warp_mouse(points[step])
		preview.active_brush_kind = &"remove_sand"
		var hit = preview._brush_hit()
		if hit != null:
			preview._submit_brush(&"remove_sand", 0.02, hit, hit, &"circle")
		await _wait_ticks(HOVER_TICKS + (step + 1) * STEP_TICKS)


func _place() -> void:
	var points := _screens()
	for step in STEPS:
		Input.warp_mouse(points[3 - step])
		preview.active_brush_kind = &"place_sand"
		var hit = preview._brush_hit()
		if hit != null:
			preview._submit_brush(&"place_sand", 0.015, hit, hit, &"circle")
		await _wait_ticks(HOVER_TICKS + (STEPS + step + 1) * STEP_TICKS)


## Builds a wall at the cursor through the player placement path.
func _build_wall() -> void:
	Input.warp_mouse(Vector2(520.0, 470.0))
	var hit = preview._brush_hit()
	if hit == null:
		return
	preview.place_structure_at_world(Structure.Kind.WALL, hit)
	await _wait_ticks(BUILD_TICK + STEP_TICKS)


func _wait_ticks(target: int) -> void:
	while not finished and preview.completed_ticks < target:
		if not preview.last_error.is_empty():
			_fail(preview.last_error)
			return
		var hit = preview._brush_hit()
		if hit != null:
			## Keep the ring on the current cursor while the sim runs.
			preview._update_brush_indicator()
		await process_frame


func _still(name: String) -> bool:
	await process_frame
	await RenderingServer.frame_post_draw
	if finished:
		return false
	var error: Error = root.get_texture().get_image().save_png(STILL_DIR + name)
	if error != OK:
		_fail("still save failed for %s: %d" % [name, error])
		return false
	stills.append(name)
	return true


func _watchdog() -> void:
	while not finished:
		if Time.get_ticks_msec() - started_ms > 900000:
			_fail("tool feedback recording timed out")
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

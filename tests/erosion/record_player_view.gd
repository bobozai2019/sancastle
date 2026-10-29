extends SceneTree

## Player-view T04 recording. Drives the main entry (256² GPU coupled) through a
## scripted dig -> guide -> dam sequence using the same `_submit_brush` entry the
## mouse handler uses, captures stills at each beat, and (unless --stills-only)
## leaves the movie writer to produce an unobstructed 30 s clip.
##
## Usage:
##   godot --path <proj> --rendering-driver d3d12 --fixed-fps 30 \
##     --write-movie <staging>.avi --script <this> -- [--stills-only]

const PRESET := 1
const BASELINE_TICK := 200
const DIG_END_TICK := 300
const BORROW_END_TICK := 370
const DAM_END_TICK := 500
const FINAL_TICK := 900

const CAMERA_POSITION := Vector3(1.0, 5.5, 8.5)
const CAMERA_TARGET := Vector3(3.0, 0.05, -1.0)

const STILL_DIR := "res://test_output/sandcastle_water_sand_coupling/验收/"

var main: Node3D
var preview: Node3D
var finished := false
var started_ms := 0
var stills_only := false
var baseline_sand: PackedFloat32Array = PackedFloat32Array()
var post_edit_sand: PackedFloat32Array = PackedFloat32Array()
var stills: Array[String] = []
var dig_commands := 0
var borrow_commands := 0
var dam_commands := 0
var dam_placed_m3 := 0.0
var dug_m3 := 0.0


func _init() -> void:
	stills_only = "--stills-only" in OS.get_cmdline_user_args()
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
	main.selected_preset = PRESET
	main.enable_gpu_erosion = true
	main.hide_hud = true
	main.show_brush_indicator = false
	main.use_player_camera = true
	main.player_camera_position = CAMERA_POSITION
	main.player_camera_target = CAMERA_TARGET
	root.add_child(main)
	started_ms = Time.get_ticks_msec()

	if not await _await_ready():
		return
	preview = _scene()
	if not await _sync_shadow():
		return
	baseline_sand = preview.shadow_domain.sand.duplicate()

	if not await _await_tick(BASELINE_TICK):
		return
	if not await _still("baseline"):
		return

	## Beat 1: the player deepens the dry channel ahead of the water front.
	if not await _await_tick(DIG_END_TICK):
		return
	_dig_guide_trench()
	print("AFTER DIG inventory=%.6f dug=%.4f" % [
		preview.shadow_domain.tool_inventory_m3, dug_m3])
	if not await _still("dig"):
		return

	## Beat 2: borrow sand from the dry upper beach for the dam.
	if not await _await_tick(BORROW_END_TICK):
		return
	_dig_borrow_pit()
	print("AFTER BORROW inventory=%.6f dug=%.4f" % [
		preview.shadow_domain.tool_inventory_m3, dug_m3])
	if not await _still("borrow"):
		return

	## Beat 3: pile a dam across the channel downstream of the cut.
	if not await _await_tick(DAM_END_TICK):
		return
	_build_dam()
	print("AFTER DAM inventory=%.6f placed=%.4f" % [
		preview.shadow_domain.tool_inventory_m3, dam_placed_m3])
	if not await _sync_shadow():
		return
	post_edit_sand = preview.shadow_domain.sand.duplicate()
	if not await _still("dam"):
		return

	if not await _await_tick(FINAL_TICK):
		return
	if not await _sync_shadow():
		return
	if not await _still("final"):
		return
	await _report()


func _await_ready() -> bool:
	while not finished:
		var scene := _scene()
		if scene != null and not scene.last_error.is_empty():
			_fail(scene.last_error)
			return false
		if scene != null and scene.ready_for_ticks and \
				scene.collision_proxy.applied_revisions.size() >= 64:
			return true
		await process_frame
	return false


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


func _still(stage: String) -> bool:
	await RenderingServer.frame_post_draw
	if finished:
		return false
	var name := "T04_player_view_%s_20260928.png" % stage
	var error: Error = root.get_texture().get_image().save_png(STILL_DIR + name)
	if error != OK:
		_fail("still save failed for %s: %d" % [stage, error])
		return false
	stills.append(name)
	print("STILL: %s at tick %d" % [name, _scene().completed_ticks])
	return true


## Pauses the tick loop and pulls the authoritative GPU sand/sediment back into
## the CPU shadow so shadow-based deltas are not read from a stale revision.
func _sync_shadow() -> bool:
	var scene := _scene()
	scene.playing = false
	var waited := 0
	while not finished and (scene.tick_pending or
			scene.collision_proxy.pending_revisions.size() > 0) and waited < 900:
		await process_frame
		waited += 1
	if waited >= 900:
		_fail("shadow sync never went idle")
		return false
	if scene.shadow_revision != scene.solver.state_revision and \
			scene.shadow_sync_reason.is_empty():
		scene._request_shadow_sync("debug")
	waited = 0
	while not finished and (scene.tick_pending or
			scene.shadow_revision != scene.solver.state_revision) and waited < 900:
		await process_frame
		waited += 1
	if waited >= 900 or scene.shadow_revision != scene.solver.state_revision:
		_fail("shadow sync did not reach the GPU revision")
		return false
	scene.playing = true
	return true


func _brush(kind: StringName, amount_m3: float, start: Vector3, end: Vector3,
		shape: StringName) -> bool:
	var error: StringName = preview._submit_brush(kind, amount_m3, start, end, shape)
	if not error.is_empty():
		_fail("player brush rejected (%s): %s" % [kind, error])
		return false
	return true


## Drops the south bank of the channel by ~0.16 m so the cut turns from light
## bank sand to the grey exposed colour and can carry spill water.
func _dig_guide_trench() -> void:
	var points: Array[Vector3] = [
		Vector3(1.2, 0.0, -2.4), Vector3(1.4, 0.0, -0.6), Vector3(1.6, 0.0, 1.2),
		Vector3(1.8, 0.0, 3.0)]
	for _pass_index in 4:
		for i in points.size() - 1:
			if _brush(&"remove_sand", 0.060, points[i], points[i + 1], &"swept_segment"):
				dig_commands += 1
				dug_m3 += 0.060


## Borrow pit on the dry upper beach, in front of the camera.
func _dig_borrow_pit() -> void:
	var pit: Array[Vector3] = [
		Vector3(5.0, 0.0, 6.2), Vector3(6.2, 0.0, 6.6), Vector3(7.4, 0.0, 6.0)]
	for _pass_index in 5:
		for i in pit.size() - 1:
			if _brush(&"remove_sand", 0.060, pit[i], pit[i + 1], &"swept_segment"):
				borrow_commands += 1
				dug_m3 += 0.060


## Dam spanning the full channel width downstream of the cut.
func _build_dam() -> void:
	var start := Vector3(7.6, 0.0, -1.4)
	var end := Vector3(7.6, 0.0, 5.4)
	for _pass_index in 11:
		if _brush(&"place_sand", 0.120, start, end, &"swept_segment"):
			dam_commands += 1
			dam_placed_m3 += 0.120


func _report() -> void:
	var scene := _scene()
	scene.playing = false
	var waited := 0
	while not finished and (scene.tick_pending or
			scene.collision_proxy.pending_revisions.size() > 0 or
			scene.collision_proxy.active_chunks.size() > 0) and waited < 900:
		await process_frame
		waited += 1
	var cut_depth := _max_drop(baseline_sand, post_edit_sand)
	var erosion_depth := _max_drop(post_edit_sand, scene.shadow_domain.sand)
	var downstream_deposit := _downstream_deposit(scene)
	var net_after_edit := _net_change(post_edit_sand, scene.shadow_domain.sand)
	var passes: bool = scene.audit_sand_closure_m3 <= 0.01 and \
		scene.audit_sand_negative_cells == 0 and scene.audit_sand_invalid_cells == 0 and \
		scene.audit_negative_cells == 0 and scene.audit_invalid_cells == 0 and \
		dig_commands > 0 and dam_commands > 0 and \
		absf(scene.shadow_domain.tool_inventory_m3) < 0.001 and \
		scene.audit_sediment_m3 > 0.0 and downstream_deposit > 0.0
	print(("PASS" if passes else "FAIL") +
		": T04 player view ticks=%d stills=%s dig_cmds=%d borrow_cmds=%d dam_cmds=%d" % [
			scene.completed_ticks, ",".join(stills), dig_commands, borrow_commands,
			dam_commands] +
		" dug_m3=%.4f dam_m3=%.4f inventory_m3=%.6f suspended_m3=%.6f" % [
			dug_m3, dam_placed_m3, scene.shadow_domain.tool_inventory_m3,
			scene.audit_sediment_m3] +
		" cut_depth_m=%.4f erosion_depth_m=%.4f net_after_edit_m3=%.6f downstream_deposit_m3=%.6f" % [
			cut_depth, erosion_depth, net_after_edit, downstream_deposit] +
		" sand_closure_m3=%.9f water_m3=%.6f negative_sand=%d invalid_sand=%d" % [
			scene.audit_sand_closure_m3, scene.audit_water_m3,
			scene.audit_sand_negative_cells, scene.audit_sand_invalid_cells] +
		" negative_water=%d invalid_water=%d min_depth_m=%.6f water_source_m3=%.4f" % [
			scene.audit_negative_cells, scene.audit_invalid_cells,
			scene.audit_min_depth_m, scene.solver.water_source_m3])
	_finish(0 if passes else 1)


## Net sand gained in the downstream reach (nx > 0.7) after the player's edits.
func _downstream_deposit(scene: Node3D) -> float:
	var total := 0.0
	var first_x := int(256 * 0.7)
	for z in 256:
		for x in range(first_x, 256):
			var i := z * 256 + x
			total += scene.shadow_domain.sand[i] - post_edit_sand[i]
	return total * 0.125 * 0.125


func _net_change(before: PackedFloat32Array, after: PackedFloat32Array) -> float:
	var total := 0.0
	for i in 256 * 256:
		total += after[i] - before[i]
	return total * 0.125 * 0.125


## Deepest sand drop between two shadow snapshots.
func _max_drop(before: PackedFloat32Array, after: PackedFloat32Array) -> float:
	var worst := 0.0
	for i in 256 * 256:
		worst = maxf(worst, before[i] - after[i])
	return worst


func _watchdog() -> void:
	while not finished:
		if Time.get_ticks_msec() - started_ms > 900000:
			var scene := _scene()
			_fail("player view recording timed out at tick %d" % (
				scene.completed_ticks if scene != null else -1))
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

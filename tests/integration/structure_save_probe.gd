extends SceneTree

## T08/T06: the structure layer survives a checkpoint round trip.
##
## The `structures` array is part of the frozen save schema, but until now the
## checkpoint carried only the heightfield - so a loaded wall came back as inert
## sand with no support graph and could never collapse. This probe builds a wall,
## lets it take damage, saves, and loads the file into a *new* preview instance.

const Store = preload("res://scripts/simulation/checkpoint_store.gd")
const Structure = preload("res://scripts/structures/structure_state.gd")
const SAVE_PATH := "user://t08_structure_save.scp"

var preview: Node3D
var restored: Node3D
var finished := false
var started_ms := 0
var failures: Array[String] = []
var results: Array[String] = []
var saved := {}


func _init() -> void:
	call_deferred("_watchdog")
	call_deferred("_begin")


func _begin() -> void:
	started_ms = Time.get_ticks_msec()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	preview = _spawn()
	if preview == null:
		return
	call_deferred("_wait_ready")


## `checkpoint` must be set *before* the node enters the tree: the scene reads it
## in `_ready`, which is exactly the ordering the router uses for a real load.
func _spawn(checkpoint := {}, prefix: Array[Dictionary] = []) -> Node3D:
	var scene: PackedScene = load("res://scenes/gpu_water_preview.tscn")
	if scene == null:
		_fail("preview scene unavailable")
		return null
	var node: Node3D = scene.instantiate()
	node.preset_index = 1
	node.enable_erosion = true
	node.hide_hud = true
	if checkpoint.is_empty():
		node.enable_structures = true
	else:
		node.replay_checkpoint = checkpoint
		node.replay_prefix_commands = prefix
		node.replay_target_tick = checkpoint.tick
		node.replay_highwater_id = checkpoint.highwater_id
	root.add_child(node)
	return node


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
	_build_and_save()


func _build_and_save() -> void:
	preview.playing = false
	var waited := 0
	while not finished and preview.tick_pending and waited < 600:
		await process_frame
		waited += 1
	## A wall with enough sand in the bucket to pay for it, built as external
	## scenery so the probe does not depend on the player dig loop.
	var wall := Structure.new()
	wall.kind = Structure.Kind.WALL
	wall.origin = Vector2i(120, 128)
	wall.size = Vector2i(7, 30)
	wall.height_m = 0.34
	wall.taper_slope_m = 0.11
	wall.compaction = 0.8
	preview.structure_field.add(wall, preview.shadow_domain)
	## Damage it a little so the saved layer carries a non-zero value.
	wall.damage = 0.375
	saved = wall.to_dict()
	var save_error: StringName = preview.request_checkpoint_save(SAVE_PATH)
	if not save_error.is_empty():
		_fail("checkpoint save refused: " + String(save_error))
		return
	waited = 0
	while not finished and preview.last_save_path.is_empty() and \
			preview.last_save_error.is_empty() and waited < 900:
		await process_frame
		waited += 1
	if not preview.last_save_error.is_empty():
		_fail("checkpoint save failed: " + String(preview.last_save_error))
		return
	if preview.last_save_path.is_empty():
		_fail("checkpoint save never completed")
		return
	_load_back()


func _load_back() -> void:
	var loaded: Dictionary = Store.load(SAVE_PATH)
	if not loaded.get("error", &"invalid").is_empty():
		_fail("saved checkpoint did not load: " + String(loaded.error))
		return
	var checkpoint: Dictionary = loaded.checkpoint
	if typeof(checkpoint.get("structures", {})) != TYPE_DICTIONARY or 			checkpoint.structures.is_empty():
		failures.append("checkpoint carries no structure layer")
		_report()
		return
	preview.queue_free()
	preview = null
	restored = _spawn(checkpoint, loaded.prefix_commands)
	call_deferred("_wait_restored_ready")


func _wait_restored_ready() -> void:
	while not finished:
		if not restored.last_error.is_empty():
			_fail("restored scene reported: " + restored.last_error)
			return
		if restored.ready_for_ticks:
			break
		await process_frame
	if finished:
		return
	_compare()


func _compare() -> void:
	var field: SandcastleStructureField = restored.structure_field
	if field == null:
		failures.append("restored scene has no structure layer")
		_report()
		return
	if field.structures.size() != 1:
		failures.append("restored %d structures, expected 1" % field.structures.size())
		_report()
		return
	var wall := field.structures[0]
	var mismatches: Array[String] = []
	if wall.kind != saved.kind:
		mismatches.append("kind")
	if wall.origin != saved.origin or wall.size != saved.size:
		mismatches.append("footprint")
	if absf(wall.height_m - saved.height_m) > 0.000001:
		mismatches.append("height")
	if absf(wall.taper_slope_m - saved.taper_slope_m) > 0.000001:
		mismatches.append("taper")
	if absf(wall.damage - saved.damage) > 0.000001:
		mismatches.append("damage")
	if absf(wall.compaction - saved.compaction) > 0.000001:
		mismatches.append("compaction")
	if wall.collapsed != saved.collapsed:
		mismatches.append("collapsed")
	if not mismatches.is_empty():
		failures.append("restored wall differs on: " + ", ".join(mismatches))
	elif not restored.enable_structures:
		failures.append("restore did not turn the structure layer on")
	else:
		results.append("RESTORE_OK structures=%d kind=%d footprint=%s height=%.4f" % [
			field.structures.size(), wall.kind, str(wall.size), wall.height_m])
		results.append("DAMAGE_OK damage=%.6f compaction=%.6f collapsed=%s" % [
			wall.damage, wall.compaction, str(wall.collapsed)])
		results.append("FLAG_OK enable_structures=%s generation=%d" % [
			str(restored.enable_structures), field.generation])
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
	print("PASS: T08 structure save round trip")
	_finish(0)


func _watchdog() -> void:
	while not finished:
		if Time.get_ticks_msec() - started_ms > 600000:
			_fail("structure save probe timed out")
			return
		await process_frame


func _fail(message: String) -> void:
	if finished:
		return
	printerr("FAIL: " + message)
	_finish(1)


func _finish(code: int) -> void:
	finished = true
	if preview != null and is_instance_valid(preview):
		preview.queue_free()
	if restored != null and is_instance_valid(restored):
		restored.queue_free()
	for _frame in 3:
		await process_frame
	quit(code)

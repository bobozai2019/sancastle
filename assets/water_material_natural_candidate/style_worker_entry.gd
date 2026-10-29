extends "res://assets/water_material_natural_candidate/style_entry.gd"

## Validate immutable sand readback away from the main thread.
## The authoritative shadow assignment and command application remain on main.
var sand_worker_task_id := -1


func _on_shadow_field(data: PackedByteArray, field: String,
		revision: int, token: int) -> void:
	if field != "sand":
		super._on_shadow_field(data, field, revision, token)
		return
	sand_worker_task_id = WorkerThreadPool.add_task(
		_worker_validate_sand.bind(data, revision, token), true,
		"test1 sand shadow decode")


func _worker_validate_sand(data: PackedByteArray,
		revision: int, token: int) -> void:
	var valid := data.size() == GRID_SIZE * GRID_SIZE * 4
	var values := PackedFloat32Array()
	if valid:
		values = data.to_float32_array()
		for value in values:
			if not is_finite(value) or value < -0.000001:
				valid = false
				break
	call_deferred("_shadow_sand_worker_ready", values, valid,
		revision, token)


func _shadow_sand_worker_ready(values: PackedFloat32Array, valid: bool,
		revision: int, token: int) -> void:
	if sand_worker_task_id >= 0:
		WorkerThreadPool.wait_for_task_completion(sand_worker_task_id)
		sand_worker_task_id = -1
	if closing or token != generation or shadow_sync_reason.is_empty() or \
			solver.state_revision != revision:
		return
	if not valid:
		_fail("shadow sync nonfinite/negative or size mismatch: sand")
		return
	shadow_sync_fields["sand"] = values
	if shadow_sync_fields.size() < (4 if shadow_sync_full else 1):
		return
	shadow_domain.sand = shadow_sync_fields["sand"]
	shadow_sand_revision = revision
	if shadow_sync_full:
		shadow_domain.sediment = shadow_sync_fields["sediment"]
		shadow_domain.wetness = shadow_sync_fields["wetness"]
		shadow_domain.compaction = shadow_sync_fields["compaction"]
		shadow_revision = revision
		full_shadow_syncs += 1
		full_shadow_bytes += GRID_SIZE * GRID_SIZE * (8 + 4)
	else:
		sand_only_syncs += 1
		sand_only_bytes += GRID_SIZE * GRID_SIZE * 4
	shadow_sync_fields.clear()
	var reason := shadow_sync_reason
	shadow_sync_reason = ""
	shadow_sync_full = false
	tick_pending = false
	_resume_shadow_sync(reason)


func _exit_tree() -> void:
	if sand_worker_task_id >= 0:
		WorkerThreadPool.wait_for_task_completion(sand_worker_task_id)
		sand_worker_task_id = -1
	super._exit_tree()

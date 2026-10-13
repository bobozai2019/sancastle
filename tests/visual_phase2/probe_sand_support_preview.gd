extends SceneTree

const SCENE := preload("res://scenes/sand_visual_fixture.tscn")
const Store := preload("res://scripts/simulation/checkpoint_store.gd")
const OUT := "res://test_output/sandcastle_visual_reconstruction_phase2/验收/S02_sand_support_preview.json"
const GRID := 256

var preview: Node3D
var sand_bytes := PackedByteArray()
var compare_readbacks: Dictionary = {}
var frames := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	preview = SCENE.instantiate()
	root.add_child(preview)
	while (not preview.ready_for_ticks or preview.completed_ticks < 600) and preview.last_error.is_empty() and frames < 36000:
		await process_frame
		frames += 1
	if not preview.last_error.is_empty() or preview.completed_ticks < 600:
		_fail("failed before support loss: " + preview.last_error)
		return
	preview.playing = false
	while preview.tick_pending:
		await process_frame
	var event_tick: int = preview.completed_ticks
	var stale: Dictionary = preview.request_sand_support_loss({"generation": preview.generation - 1, "request_id": 1})
	if stale.ok or stale.code != &"inactive_generation":
		_fail("stale generation was accepted")
		return
	var accepted: Dictionary = preview.request_sand_support_loss({"generation": preview.generation, "request_id": 1})
	var duplicate: Dictionary = preview.request_sand_support_loss({"generation": preview.generation, "request_id": 1})
	if not accepted.ok or duplicate.ok:
		_fail("support request admission failed")
		return
	while preview.support_loss_applied_id != 1 and preview.last_support_loss_error.is_empty() and frames < 37000:
		await process_frame
		frames += 1
	if preview.support_loss_applied_id != 1:
		_fail("support request did not apply: " + String(preview.last_support_loss_error))
		return
	preview.playing = true
	while preview.completed_ticks < event_tick + 900 and preview.last_error.is_empty() and frames < 90000:
		await process_frame
		frames += 1
	if not preview.last_error.is_empty() or preview.completed_ticks < event_tick + 900:
		_fail("failed after support loss: " + preview.last_error)
		return
	preview.playing = false
	while preview.tick_pending:
		await process_frame
	RenderingServer.call_on_render_thread(_read_sand)
	while sand_bytes.is_empty() and frames < 91000:
		await process_frame
		frames += 1
	if sand_bytes.size() != GRID * GRID * 4:
		_fail("sand readback invalid")
		return
	var sand: PackedFloat32Array = sand_bytes.to_float32_array()
	var high := 0
	var boundary := 0.0
	var boundary_count := 0
	var total := 0.0
	var minimum := INF
	for z in GRID:
		for x in GRID:
			var h: float = sand[z * GRID + x]
			total += h * 0.125 * 0.125
			minimum = minf(minimum, h)
			if absi(x - 80) <= 8 and absi(z - 128) <= 8:
				if h > 0.9:
					high += 1
				if absi(x - 80) == 8 or absi(z - 128) == 8:
					boundary += h
					boundary_count += 1
	var result := {"event_tick": event_tick, "end_tick": preview.completed_ticks,
		"support_event": preview.support_loss_events[0],
		"packed_high_shape_iou": float(high) / 289.0,
		"packed_boundary_mean_m": boundary / float(boundary_count),
		"total_sand_m3": total, "minimum_sand_m": minimum,
		"stale_generation_rejected": true, "duplicate_rejected": true}
	await physics_frame
	await physics_frame
	var center_world := Vector3((80.5 * 0.125) - 16.0, 0.0,
		(128.5 * 0.125) - 16.0)
	var query := PhysicsRayQueryParameters3D.create(
		center_world + Vector3.UP * 10.0,
		center_world + Vector3.DOWN * 10.0)
	var hit: Dictionary = root.world_3d.direct_space_state.intersect_ray(query)
	if not hit.has("position"):
		_fail("collision proxy misses collapsed sand")
		return
	var expected_bed: float = 0.20 + sand[128 * GRID + 80]
	var collision_error: float = absf(hit.position.y - expected_bed)
	result["collision_height_error_m"] = collision_error
	if collision_error > 0.125:
		_fail("collision proxy differs from collapsed sand: %.6f" % collision_error)
		return
	preview.set_fixture_camera(&"oblique")
	await process_frame
	await process_frame
	var screenshot_path := ProjectSettings.globalize_path(
		"res://test_output/sandcastle_visual_reconstruction_phase2/验收/S02_sand_support_t1500.png")
	if root.get_viewport().get_texture().get_image().save_png(screenshot_path) != OK:
		_fail("cannot capture support-loss frame")
		return
	var path := ProjectSettings.globalize_path(OUT)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_fail("cannot write evidence")
		return
	file.store_string(JSON.stringify(result, "  "))
	file.close()
	if result.packed_high_shape_iou >= 0.85 or minimum < -0.000001:
		_fail("support loss did not slump or sand became negative: " + JSON.stringify(result))
		return
	var save_path := "user://s02_support_" + str(Time.get_ticks_usec()) + ".sandcp"
	var save_error: StringName = preview.request_checkpoint_save(save_path)
	if not save_error.is_empty():
		_fail("checkpoint request failed: " + String(save_error))
		return
	while preview.last_save_path.is_empty() and preview.last_save_error.is_empty() and frames < 93000:
		await process_frame
		frames += 1
	if preview.last_save_path.is_empty():
		_fail("checkpoint did not finish: " + String(preview.last_save_error))
		return
	var loaded: Dictionary = Store.load(save_path)
	if not loaded.error.is_empty() or loaded.checkpoint.support_loss_events.size() != 1:
		_fail("checkpoint support history invalid: " + str(loaded.error))
		return
	var restored: Node3D = SCENE.instantiate()
	restored.generation = preview.generation + 1
	restored.replay_checkpoint = loaded.checkpoint
	restored.replay_prefix_commands = loaded.prefix_commands
	restored.replay_target_tick = 1800
	root.add_child(restored)
	while not restored.ready_for_ticks and restored.last_error.is_empty() and frames < 95000:
		await process_frame
		frames += 1
	if not restored.ready_for_ticks or restored.support_loss_applied_id != 1 or \
			restored.support_loss_events[0].generation != restored.generation:
		_fail("restored support metadata invalid: " + restored.last_error)
		return
	preview.playing = true
	while (preview.completed_ticks < 1800 or restored.completed_ticks < 1800) and \
			preview.last_error.is_empty() and restored.last_error.is_empty() and frames < 120000:
		await process_frame
		frames += 1
	preview.playing = false
	while preview.tick_pending or restored.tick_pending:
		await process_frame
	if preview.completed_ticks != 1800 or restored.completed_ticks != 1800:
		_fail("restart tick mismatch: %d/%d" % [preview.completed_ticks, restored.completed_ticks])
		return
	RenderingServer.call_on_render_thread(_read_compare.bind(preview, "original"))
	RenderingServer.call_on_render_thread(_read_compare.bind(restored, "restored"))
	while compare_readbacks.size() < 10 and frames < 122000:
		await process_frame
		frames += 1
	var equal_fields := {}
	for field in ["sand", "compaction", "water", "momentum_x", "momentum_z"]:
		equal_fields[field] = compare_readbacks.get("original_" + field,
			PackedByteArray()) == compare_readbacks.get("restored_" + field,
			PackedByteArray())
		if not equal_fields[field]:
			_fail("checkpoint continuation differs: " + field)
			return
	result["checkpoint_saved_tick"] = loaded.checkpoint.tick
	result["restart_target_tick"] = 1800
	result["equal_restart_fields"] = equal_fields
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_fail("cannot update restart evidence")
		return
	file.store_string(JSON.stringify(result, "  "))
	file.close()
	print("PASS: S02 preview support loss " + JSON.stringify(result))
	quit(0)


func _read_sand() -> void:
	var data: PackedByteArray = RenderingServer.get_rendering_device().texture_get_data(
		preview.solver.current_texture("sand"), 0)
	call_deferred("_receive_sand", data)


func _receive_sand(data: PackedByteArray) -> void:
	sand_bytes = data


func _read_compare(scene: Node3D, label: String) -> void:
	var rd := RenderingServer.get_rendering_device()
	for field in ["sand", "compaction", "water", "momentum_x", "momentum_z"]:
		var data: PackedByteArray = rd.texture_get_data(
			scene.solver.current_texture(field), 0)
		call_deferred("_receive_compare", label + "_" + field, data)


func _receive_compare(key: String, data: PackedByteArray) -> void:
	compare_readbacks[key] = data


func _fail(message: String) -> void:
	push_error("FAIL: S02 preview support loss " + message)
	quit(1)

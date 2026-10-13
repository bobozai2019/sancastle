extends SceneTree

var main: Node3D
var reference: Node3D
var started_ms := 0
var finished := false
var readback := PackedByteArray()
var phase := "initial"
var replay_steps := 8
var coupled := false


func _init() -> void:
	call_deferred("_begin")


func _begin() -> void:
	coupled = OS.get_environment("SANDCASTLE_COUPLED_REPLAY") == "1"
	var requested_steps := int(OS.get_environment("SANDCASTLE_REPLAY_STEPS"))
	if requested_steps > replay_steps:
		replay_steps = requested_steps
	var scene: PackedScene = load("res://scenes/main.tscn")
	if scene == null:
		_fail("GPU replay main scene missing")
		return
	main = scene.instantiate()
	main.enable_gpu_erosion = coupled
	root.add_child(main)
	started_ms = Time.get_ticks_msec()
	call_deferred("_watchdog")
	call_deferred("_run")


func _run() -> void:
	while main.active_scene == null or main.active_scene.completed_ticks < 3:
		if main.active_scene != null and not main.active_scene.last_error.is_empty():
			_fail(main.active_scene.last_error)
			return
		await process_frame
	var preview: Node3D = main.active_scene
	preview.playing = false
	while preview.tick_pending:
		await process_frame
	while preview.collision_proxy.shapes.size() < 64:
		await process_frame
	if coupled and preview.shadow_revision != preview.solver.state_revision:
		preview._request_shadow_sync("debug")
		while preview.shadow_revision != preview.solver.state_revision:
			await process_frame
	var initial_shape: CollisionShape3D = preview.collision_proxy.shapes[24]
	if absf(initial_shape.shape.map_data[29 * 33 + 22] -
			preview.shadow_domain.bed_at(preview.shadow_domain.index(22, 125))) > 0.00001:
		_fail("GPU initial collision sample differs from bed")
		return
	var edit_error: StringName = preview._submit_brush(&"remove_sand", 0.08,
		Vector3(-13.0, 0.0, 0.0), Vector3(-13.0, 0.0, 0.0), &"circle")
	if not edit_error.is_empty():
		_fail("GPU replay edit rejected: " + String(edit_error))
		return
	while preview.completed_patch_batches < 1 or preview.tick_pending:
		await process_frame
	if preview.command_queue.applied_log.size() != 1 or \
			preview.shadow_domain.tool_inventory_m3 < 0.07:
		_fail("GPU replay edit not applied")
		return
	var edit_tick: int = preview.completed_ticks
	preview.playing = true
	while preview.completed_ticks < edit_tick + replay_steps:
		if not preview.last_error.is_empty():
			_fail(preview.last_error)
			return
		await process_frame
	preview.playing = false
	while preview.tick_pending:
		await process_frame
	var target_tick: int = preview.completed_ticks
	var edited_source: float = preview.solver.water_source_m3
	var edited_sink: float = preview.solver.water_sink_m3
	var edited_inventory: float = preview.shadow_domain.tool_inventory_m3
	var edited_state: Dictionary = await _read_state(preview)
	if finished:
		return
	var undo_event := InputEventKey.new()
	undo_event.keycode = KEY_Z
	undo_event.pressed = true
	var undo_started_usec := Time.get_ticks_usec()
	main._input(undo_event)
	if main.staging_scene == null:
		_fail("GPU cross-tick undo did not start replay")
		return
	while main.active_scene == preview:
		if not main.history_replay_error.is_empty():
			_fail(main.history_replay_error)
			return
		await process_frame
	var undone: Node3D = main.active_scene
	var undo_ms := float(Time.get_ticks_usec() - undo_started_usec) / 1000.0
	if undone.completed_ticks != target_tick or undone.command_queue.applied_log.size() != 0 or \
			undone.command_queue.redo_stack.size() != 1 or \
			absf(undone.shadow_domain.tool_inventory_m3) > 0.000001:
		_fail("GPU cross-tick undo history/tick/inventory mismatch")
		return
	var undone_state: Dictionary = await _read_state(undone)
	if finished:
		return
	var reference_scene: PackedScene = load("res://scenes/gpu_water_preview.tscn")
	reference = reference_scene.instantiate()
	reference.enable_erosion = coupled
	reference.visible = false
	reference.replay_target_tick = target_tick
	reference.playing = false
	reference.set_process_unhandled_input(false)
	root.add_child(reference)
	reference.get_node("GpuOverviewCamera").current = false
	undone.get_node("GpuOverviewCamera").current = true
	while not reference.replay_ready:
		if not reference.last_error.is_empty():
			_fail(reference.last_error)
			return
		await process_frame
	var reference_state: Dictionary = await _read_state(reference)
	if finished:
		return
	var undo_error := _max_state_error(undone_state, reference_state)
	var water_effect := _field_error(edited_state, reference_state, "water")
	if water_effect < 0.001:
		_fail("GPU replay probe edit did not materially change water history: %.8f" % water_effect)
		return
	var edited_cell := _first_different_cell(edited_state, reference_state, "sand")
	if edited_cell < 0:
		_fail("GPU replay edited cell unavailable")
		return
	var undo_ledger_error := maxf(
		absf(undone.solver.water_source_m3 - reference.solver.water_source_m3),
		absf(undone.solver.water_sink_m3 - reference.solver.water_sink_m3))
	if undo_error > 0.00001 or undo_ledger_error > 0.00001:
		_fail("GPU cross-tick undo differs from fresh no-edit replay state=%.8f ledger=%.8f" % [
			undo_error, undo_ledger_error])
		return
	reference.queue_free()
	reference = null
	await physics_frame
	await physics_frame
	if not await _verify_collision(undone, edited_cell, undone_state):
		return
	var redo_event := InputEventKey.new()
	redo_event.keycode = KEY_Y
	redo_event.pressed = true
	var redo_started_usec := Time.get_ticks_usec()
	main._input(redo_event)
	if main.staging_scene == null:
		_fail("GPU cross-tick redo did not start replay")
		return
	while main.active_scene == undone:
		if not main.history_replay_error.is_empty():
			_fail(main.history_replay_error)
			return
		await process_frame
	var redone: Node3D = main.active_scene
	var redo_ms := float(Time.get_ticks_usec() - redo_started_usec) / 1000.0
	if redone.completed_ticks != target_tick or redone.command_queue.applied_log.size() != 1 or \
			redone.command_queue.redo_stack.size() != 0 or \
			absf(redone.shadow_domain.tool_inventory_m3 - edited_inventory) > 0.000001:
		_fail("GPU cross-tick redo history/tick/inventory mismatch")
		return
	var redone_state: Dictionary = await _read_state(redone)
	if finished:
		return
	var redo_error := _max_state_error(redone_state, edited_state)
	var redo_ledger_error := maxf(absf(redone.solver.water_source_m3 - edited_source),
		absf(redone.solver.water_sink_m3 - edited_sink))
	if redo_error > 0.00001 or redo_ledger_error > 0.00001:
		_fail("GPU cross-tick redo differs from original state=%.8f ledger=%.8f" % [
			redo_error, redo_ledger_error])
		return
	if not await _verify_collision(redone, edited_cell, redone_state):
		return
	var first_command: Dictionary = redone.command_queue.applied_log[0].duplicate(true)
	phase = "second_edit"
	var previous_batches: int = redone.completed_patch_batches
	var second_error: StringName = redone._submit_brush(&"remove_sand", 0.05,
		Vector3(-12.5, 0.0, 0.3), Vector3(-12.5, 0.0, 0.3), &"circle")
	if not second_error.is_empty():
		_fail("GPU second replay edit rejected: " + String(second_error))
		return
	while redone.completed_patch_batches <= previous_batches or redone.tick_pending:
		await process_frame
	phase = "second_advance"
	redone.playing = true
	while redone.completed_ticks < target_tick + 5:
		await process_frame
	redone.playing = false
	while redone.tick_pending:
		await process_frame
	var second_target_tick: int = redone.completed_ticks
	var two_edit_source: float = redone.solver.water_source_m3
	var two_edit_sink: float = redone.solver.water_sink_m3
	var two_edit_state: Dictionary = await _read_state(redone)
	if finished:
		return
	main._input(undo_event)
	phase = "second_undo"
	if main.staging_scene == null:
		_fail("GPU second cross-tick undo did not start")
		return
	while main.active_scene == redone:
		if not main.history_replay_error.is_empty():
			_fail(main.history_replay_error)
			return
		await process_frame
	var one_edit: Node3D = main.active_scene
	if one_edit.command_queue.applied_log.size() != 1 or \
			one_edit.command_queue.redo_stack.size() != 1:
		_fail("GPU second cross-tick undo history mismatch")
		return
	var one_edit_state: Dictionary = await _read_state(one_edit)
	if finished:
		return
	reference = reference_scene.instantiate()
	reference.enable_erosion = coupled
	phase = "second_reference"
	reference.visible = false
	reference.replay_target_tick = second_target_tick
	var first_only: Array[Dictionary] = [first_command]
	reference.replay_commands = first_only
	reference.playing = false
	reference.set_process_unhandled_input(false)
	root.add_child(reference)
	reference.get_node("GpuOverviewCamera").current = false
	one_edit.get_node("GpuOverviewCamera").current = true
	while not reference.replay_ready:
		if not reference.last_error.is_empty():
			_fail(reference.last_error)
			return
		await process_frame
	var first_only_state: Dictionary = await _read_state(reference)
	if finished:
		return
	var second_undo_error := _max_state_error(one_edit_state, first_only_state)
	if second_undo_error > 0.00001:
		_fail("GPU second cross-tick undo differs from first-only replay: %.8f" % second_undo_error)
		return
	reference.queue_free()
	reference = null
	main._input(redo_event)
	phase = "second_redo"
	if main.staging_scene == null:
		_fail("GPU second cross-tick redo did not start")
		return
	while main.active_scene == one_edit:
		if not main.history_replay_error.is_empty():
			_fail(main.history_replay_error)
			return
		await process_frame
	var two_edit_redone: Node3D = main.active_scene
	if two_edit_redone.command_queue.applied_log.size() != 2 or \
			two_edit_redone.command_queue.redo_stack.size() != 0:
		_fail("GPU second cross-tick redo history mismatch")
		return
	var two_edit_redone_state: Dictionary = await _read_state(two_edit_redone)
	if finished:
		return
	var second_redo_error := _max_state_error(two_edit_redone_state, two_edit_state)
	var second_ledger_error := maxf(
		absf(two_edit_redone.solver.water_source_m3 - two_edit_source),
		absf(two_edit_redone.solver.water_sink_m3 - two_edit_sink))
	if second_redo_error > 0.00001 or second_ledger_error > 0.00001:
		_fail("GPU second cross-tick redo mismatch state=%.8f ledger=%.8f" % [
			second_redo_error, second_ledger_error])
		return
	# A failing candidate must never replace or modify the visible authority.
	if not main._start_gpu_history_replay(true) or main.staging_scene == null:
		_fail("GPU injected-failure replay did not start")
		return
	main.staging_scene.last_error = "injected candidate failure"
	while main.staging_scene != null:
		await process_frame
	if main.active_scene != two_edit_redone or not two_edit_redone.visible or \
			main.history_replay_error != "injected candidate failure" or \
			two_edit_redone.command_queue.applied_log.size() != 2 or \
			two_edit_redone.command_queue.redo_stack.size() != 0 or \
			two_edit_redone.completed_ticks != second_target_tick:
		_fail("GPU failed replay changed visible authority or history")
		return
	var failure_state: Dictionary = await _read_state(two_edit_redone)
	if finished:
		return
	if _max_state_error(failure_state, two_edit_redone_state) > 0.00001:
		_fail("GPU failed replay changed authoritative texture state")
		return
	# A recent edit should restore the checkpoint from tick 120, then replay
	# only the short tail. Compare against an independent full replay.
	phase = "checkpoint_tail"
	var base_commands: Array[Dictionary] = two_edit_redone.command_queue.applied_log.duplicate(true)
	two_edit_redone.playing = true
	while two_edit_redone.completed_ticks < 125:
		if not two_edit_redone.last_error.is_empty():
			_fail(two_edit_redone.last_error)
			return
		await process_frame
	two_edit_redone.playing = false
	while two_edit_redone.tick_pending or two_edit_redone.checkpoint_capture_pending:
		await process_frame
	var late_error: StringName = two_edit_redone._submit_brush(&"remove_sand", 0.03,
		Vector3(0.0, 0.0, 0.0), Vector3(0.0, 0.0, 0.0), &"circle")
	if not late_error.is_empty():
		_fail("GPU checkpoint-tail edit rejected: " + String(late_error))
		return
	while two_edit_redone.tick_pending:
		await process_frame
	var late_edit_tick: int = two_edit_redone.completed_ticks
	two_edit_redone.playing = true
	while two_edit_redone.completed_ticks < late_edit_tick + 5:
		await process_frame
	two_edit_redone.playing = false
	while two_edit_redone.tick_pending:
		await process_frame
	var late_target_tick: int = two_edit_redone.completed_ticks
	var late_edited_state: Dictionary = await _read_state(two_edit_redone)
	if finished:
		return
	var late_source: float = two_edit_redone.solver.water_source_m3
	var late_sink: float = two_edit_redone.solver.water_sink_m3
	var late_inventory: float = two_edit_redone.shadow_domain.tool_inventory_m3
	var checkpoint_undo_started := Time.get_ticks_usec()
	if not main._start_gpu_history_replay(true) or main.staging_scene == null or \
			main.staging_scene.replay_checkpoint.get("tick", -1) != 120:
		_fail("GPU recent undo did not select tick-120 checkpoint")
		return
	if main.staging_scene.shadow_domain.generation <= two_edit_redone.shadow_domain.generation or \
			main.staging_scene.shadow_domain.generation != main.staging_scene.generation:
		_fail("GPU checkpoint candidate reused old generation")
		return
	for command in main.staging_scene.command_queue.applied_log:
		if command["generation"] != main.staging_scene.shadow_domain.generation:
			_fail("GPU checkpoint prefix kept retired generation")
			return
	while main.active_scene == two_edit_redone:
		if not main.history_replay_error.is_empty():
			_fail(main.history_replay_error)
			return
		await process_frame
	var checkpoint_undo_ms := float(Time.get_ticks_usec() - checkpoint_undo_started) / 1000.0
	var checkpoint_undone_state: Dictionary = await _read_state(main.active_scene)
	if finished:
		return
	reference = reference_scene.instantiate()
	reference.enable_erosion = coupled
	reference.visible = false
	reference.replay_target_tick = late_target_tick
	reference.replay_commands = base_commands
	reference.set_process_unhandled_input(false)
	var full_reference_started := Time.get_ticks_usec()
	root.add_child(reference)
	reference.get_node("GpuOverviewCamera").current = false
	main.active_scene.get_node("GpuOverviewCamera").current = true
	while not reference.replay_ready:
		if not reference.last_error.is_empty():
			_fail(reference.last_error)
			return
		await process_frame
	var full_reference_state: Dictionary = await _read_state(reference)
	var full_reference_ms := float(Time.get_ticks_usec() - full_reference_started) / 1000.0
	if finished:
		return
	var checkpoint_error := _max_state_error(checkpoint_undone_state, full_reference_state)
	if checkpoint_error > 0.00001 or \
			absf(main.active_scene.solver.water_source_m3 - reference.solver.water_source_m3) > 0.00001 or \
			absf(main.active_scene.solver.water_sink_m3 - reference.solver.water_sink_m3) > 0.00001:
		_fail("GPU checkpoint-tail undo differs from full replay: %.8f" % checkpoint_error)
		return
	reference.queue_free()
	reference = null
	var checkpoint_undone: Node3D = main.active_scene
	var checkpoint_redo_started := Time.get_ticks_usec()
	if not main._start_gpu_history_replay(false) or main.staging_scene == null or \
			main.staging_scene.replay_checkpoint.get("tick", -1) != 120:
		_fail("GPU recent redo did not retain tick-120 checkpoint")
		return
	if main.staging_scene.shadow_domain.generation <= checkpoint_undone.shadow_domain.generation:
		_fail("GPU checkpoint redo reused old generation")
		return
	while main.active_scene == checkpoint_undone:
		if not main.history_replay_error.is_empty():
			_fail(main.history_replay_error)
			return
		await process_frame
	var checkpoint_redo_ms := float(Time.get_ticks_usec() - checkpoint_redo_started) / 1000.0
	var checkpoint_redone_state: Dictionary = await _read_state(main.active_scene)
	if finished:
		return
	var checkpoint_redo_error := _max_state_error(checkpoint_redone_state, late_edited_state)
	if checkpoint_redo_error > 0.00001 or \
			absf(main.active_scene.solver.water_source_m3 - late_source) > 0.00001 or \
			absf(main.active_scene.solver.water_sink_m3 - late_sink) > 0.00001 or \
			absf(main.active_scene.shadow_domain.tool_inventory_m3 - late_inventory) > 0.00001 or \
			main.active_scene.command_queue.applied_log.size() != 3 or \
			main.active_scene.command_queue.redo_stack.size() != 0:
		_fail("GPU checkpoint-tail redo differs from edited authority: %.8f" % checkpoint_redo_error)
		return
	var collision_error := _full_collision_error(main.active_scene, checkpoint_redone_state)
	if collision_error > 0.00001:
		_fail("GPU checkpoint-tail collision differs from texture: %.8f" % collision_error)
		return
	print("PASS: GPU %scross-tick undo/redo single+two-command histories through %d ticks; replay_ms=%.3f/%.3f water_effect=%.8f full water+momentum+sand+sediment+ledger errors undo=%.8f redo=%.8f second_undo=%.8f second_redo=%.8f; failed candidate preserves authority; tick-120 checkpoint undo/redo to tick %d %.3f/%.3f ms, full replay %.3f ms, errors=%.8f/%.8f collision=%.8f" % [
		"coupled " if coupled else "",
		second_target_tick, undo_ms, redo_ms, water_effect, undo_error, redo_error,
		second_undo_error, second_redo_error, late_target_tick, checkpoint_undo_ms,
		checkpoint_redo_ms, full_reference_ms, checkpoint_error, checkpoint_redo_error,
		collision_error])
	finished = true
	main.queue_free()
	quit(0)


func _read_state(scene: Node3D) -> Dictionary:
	var result := {}
	for field in ["water", "momentum_x", "momentum_z", "sand", "sediment", "rock"]:
		readback = PackedByteArray()
		RenderingServer.call_on_render_thread(_render_read_field.bind(scene, field))
		while readback.is_empty():
			if finished:
				return {}
			await process_frame
		result[field] = readback.to_float32_array()
	return result


func _render_read_field(scene: Node3D, field: String) -> void:
	var error: Error = scene.solver.request_data(field, _on_data)
	if error != OK:
		call_deferred("_fail", "GPU replay %s readback failed: %d" % [field, error])


func _on_data(data: PackedByteArray) -> void:
	call_deferred("_record_data", data)


func _record_data(data: PackedByteArray) -> void:
	if not finished:
		readback = data


func _max_state_error(left: Dictionary, right: Dictionary) -> float:
	var maximum := 0.0
	for field in ["water", "momentum_x", "momentum_z", "sand", "sediment", "rock"]:
		var a: PackedFloat32Array = left[field]
		var b: PackedFloat32Array = right[field]
		if a.size() != 256 * 256 or b.size() != a.size():
			return INF
		for i in a.size():
			maximum = maxf(maximum, absf(a[i] - b[i]))
	return maximum


func _full_collision_error(scene: Node3D, state: Dictionary) -> float:
	if scene.collision_proxy.shapes.size() != 64:
		return INF
	var rock: PackedFloat32Array = state["rock"]
	var sand: PackedFloat32Array = state["sand"]
	var maximum := 0.0
	for chunk_id in 64:
		var shape: CollisionShape3D = scene.collision_proxy.shapes[chunk_id]
		var values: PackedFloat32Array = shape.shape.map_data
		for local_z in 33:
			for local_x in 33:
				var x: int = mini((chunk_id % 8) * 32 + local_x, 255)
				var z: int = mini((chunk_id / 8) * 32 + local_z, 255)
				var i := z * 256 + x
				maximum = maxf(maximum, absf(values[local_z * 33 + local_x] - rock[i] - sand[i]))
	return maximum


func _field_error(left: Dictionary, right: Dictionary, field: String) -> float:
	var a: PackedFloat32Array = left[field]
	var b: PackedFloat32Array = right[field]
	if a.size() != b.size():
		return INF
	var maximum := 0.0
	for i in a.size():
		maximum = maxf(maximum, absf(a[i] - b[i]))
	return maximum


func _first_different_cell(left: Dictionary, right: Dictionary, field: String) -> int:
	var a: PackedFloat32Array = left[field]
	var b: PackedFloat32Array = right[field]
	for i in a.size():
		if absf(a[i] - b[i]) > 0.000001:
			return i
	return -1


func _verify_collision(scene: Node3D, cell_index: int, state: Dictionary) -> bool:
	var x: int = cell_index % 256
	var z: int = cell_index / 256
	var chunk_id: int = (z / 32) * 8 + x / 32
	var wait_started_ms := Time.get_ticks_msec()
	while int(scene.collision_proxy.applied_revisions.get(chunk_id, -1)) < 0:
		if Time.get_ticks_msec() - wait_started_ms > 5000:
			_fail("GPU replay collision chunk missing: %d" % chunk_id)
			return false
		await process_frame
	await physics_frame
	await physics_frame
	var position := Vector3((float(x) + 0.5) * 0.125 - 16.0, 0.0,
		(float(z) + 0.5) * 0.125 - 16.0)
	var query := PhysicsRayQueryParameters3D.create(position + Vector3.UP * 10.0,
		position + Vector3.DOWN * 10.0)
	var hit: Dictionary = root.world_3d.direct_space_state.intersect_ray(query)
	if not hit.has("position"):
		_fail("GPU replay collision ray missed")
		return false
	var expected: float = scene.shadow_domain.bed_at(cell_index)
	if absf(hit.position.y - expected) > 0.125:
		var node: CollisionShape3D = scene.collision_proxy.shapes[chunk_id]
		var local_x: int = x % 32
		var local_z: int = z % 32
		var samples: PackedFloat32Array = node.shape.map_data
		fail_collision(scene, cell_index, chunk_id, hit.position.y, expected,
			samples, local_x, local_z, node, state)
		return false
	return true


func fail_collision(scene: Node3D, cell_index: int, chunk_id: int,
		hit_height: float, expected: float, samples: PackedFloat32Array,
		local_x: int, local_z: int, node: CollisionShape3D, state: Dictionary) -> void:
	var x: int = cell_index % 256
	var z: int = cell_index / 256
	_fail("GPU replay collision mismatch cell=%d,%d chunk=%d hit=%.6f expected=%.6f map=%.6f,%.6f cpu_rock=%.6f cpu_sand=%.6f gpu_rock=%.6f gpu_sand=%.6f node=%s scene=%s" % [
			x, z, chunk_id, hit_height, expected,
			samples[local_z * 33 + local_x],
			samples[(local_z + 1) * 33 + local_x + 1],
			scene.shadow_domain.rock[cell_index],
			scene.shadow_domain.sand[cell_index],
			state.rock[cell_index], state.sand[cell_index],
			str(node.position), scene.name])


func _watchdog() -> void:
	if finished:
		return
	if Time.get_ticks_msec() - started_ms > (270000 if coupled else 120000):
		_fail("GPU cross-tick replay probe timed out at " + phase)
		return
	await process_frame
	call_deferred("_watchdog")


func _fail(message: String) -> void:
	if finished:
		return
	finished = true
	printerr("FAIL: " + message)
	if reference != null:
		reference.queue_free()
	if main != null:
		main.queue_free()
	quit(1)

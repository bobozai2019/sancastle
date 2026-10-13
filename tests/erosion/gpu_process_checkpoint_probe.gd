extends SceneTree

const Store = preload("res://scripts/simulation/checkpoint_store.gd")
const FIELDS := ["water", "momentum_x", "momentum_z", "sand", "sediment", "rock"]

var preview: Node3D
var main: Node3D
var checkpoint_path := ""
var reference_path := ""
var readback := PackedByteArray()
var finished := false
var started_ms := 0
var target_tick := 130


func _init() -> void:
	call_deferred("_begin")


func _begin() -> void:
	checkpoint_path = OS.get_environment("SANDCASTLE_PROCESS_CHECKPOINT_PATH")
	reference_path = OS.get_environment("SANDCASTLE_PROCESS_REFERENCE_PATH")
	if checkpoint_path.is_empty() or reference_path.is_empty():
		_fail("process checkpoint paths missing")
		return
	started_ms = Time.get_ticks_msec()
	var continuation_ticks := int(OS.get_environment("SANDCASTLE_PROCESS_CONTINUATION_TICKS"))
	if continuation_ticks > 0:
		target_tick = 120 + continuation_ticks
	call_deferred("_watchdog")
	var mode := OS.get_environment("SANDCASTLE_PROCESS_CHECKPOINT_MODE")
	if mode == "write":
		call_deferred("_write_process")
	elif mode == "read":
		call_deferred("_read_process")
	else:
		_fail("process checkpoint mode invalid")


func _write_process() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	main = scene.instantiate()
	main.enable_gpu_erosion = true
	main.selected_preset = 1
	root.add_child(main)
	while main.active_scene == null or not main.active_scene.ready_for_ticks:
		await process_frame
	preview = main.active_scene
	preview.checkpoint_interval_ticks = 60
	if main.save_active_checkpoint(checkpoint_path) != &"save_busy":
		_fail("checkpoint save accepted a running scene")
		return
	var edited := false
	while preview.completed_ticks < 120:
		if not preview.last_error.is_empty():
			_fail(preview.last_error)
			return
		if not edited and preview.completed_ticks >= 70:
			var error: StringName = preview._submit_brush(&"remove_sand", 0.01,
				Vector3(1.0, 0.0, 0.0), Vector3(1.0, 0.0, 0.0), &"circle")
			if not error.is_empty():
				_fail("checkpoint live edit rejected: " + String(error))
				return
			edited = true
		await process_frame
	preview.playing = false
	while preview.tick_pending or preview.checkpoint_capture_pending or \
			preview.checkpoints.is_empty() or preview.checkpoints.back().tick != 120:
		if not preview.last_error.is_empty():
			_fail(preview.last_error)
			return
		await process_frame
	var save_error: StringName = main.save_active_checkpoint(checkpoint_path)
	if not save_error.is_empty():
		_fail("checkpoint save failed: " + String(save_error))
		return
	if preview._submit_brush(&"remove_sand", 0.001, Vector3.ZERO,
			Vector3.ZERO, &"circle") != &"save_in_progress":
		_fail("checkpoint save did not freeze new tool input")
		return
	while preview.last_save_path != checkpoint_path and preview.last_save_error.is_empty():
		await process_frame
	if not preview.last_save_error.is_empty():
		_fail("checkpoint save callback failed: " + String(preview.last_save_error))
		return
	if main.save_active_checkpoint(checkpoint_path) != &"invalid_or_existing_path":
		_fail("checkpoint store unexpectedly overwrote an existing file")
		return
	preview.playing = true
	while preview.completed_ticks < target_tick:
		if not preview.last_error.is_empty():
			_fail(preview.last_error)
			return
		await process_frame
	preview.playing = false
	while preview.tick_pending:
		await process_frame
	var source_target_tick: int = preview.completed_ticks
	var expected := await _state_fingerprints()
	if finished:
		return
	expected["target_tick"] = source_target_tick
	expected["command_count"] = preview.command_queue.applied_log.size()
	expected["water_source_m3"] = preview.solver.water_source_m3
	expected["water_sink_m3"] = preview.solver.water_sink_m3
	expected["sand_source_m3"] = preview.shadow_domain.sand_source_m3
	expected["sand_sink_m3"] = preview.shadow_domain.sand_sink_m3
	expected["inventory_m3"] = preview.shadow_domain.tool_inventory_m3
	var reference := FileAccess.open(reference_path, FileAccess.WRITE)
	if reference == null:
		_fail("checkpoint reference open failed")
		return
	reference.store_string(JSON.stringify(expected) + "\n")
	reference.close()
	print("PASS: coupled checkpoint written in process A tick=120 commands=%d target=%d file_bytes=%d" % [
		preview.command_queue.applied_log.size(), source_target_tick,
		FileAccess.get_file_as_bytes(checkpoint_path).size()])
	_finish(0)


func _read_process() -> void:
	var loaded: Dictionary = Store.load(checkpoint_path)
	if not loaded.get("error", &"missing").is_empty() or not loaded.enable_erosion or \
			loaded.checkpoint.tick != 120:
		_fail("checkpoint load failed: " + str(loaded.get("error", &"missing")))
		return
	var damaged_path := checkpoint_path + ".damaged"
	var damaged_bytes := FileAccess.get_file_as_bytes(checkpoint_path)
	damaged_bytes[damaged_bytes.size() - 1] = damaged_bytes[-1] ^ 1
	var damaged_file := FileAccess.open(damaged_path, FileAccess.WRITE)
	if damaged_file == null:
		_fail("damaged checkpoint test file open failed")
		return
	damaged_file.store_buffer(damaged_bytes)
	damaged_file.close()
	if Store.load(damaged_path).get("error") != &"checksum_mismatch":
		_fail("checkpoint checksum did not reject a changed byte")
		return
	var reference_file := FileAccess.open(reference_path, FileAccess.READ)
	if reference_file == null:
		_fail("checkpoint reference file missing")
		return
	var expected: Variant = JSON.parse_string(reference_file.get_as_text())
	reference_file.close()
	if not expected is Dictionary or expected.get("target_tick", -1) < target_tick:
		_fail("checkpoint reference invalid")
		return
	var main_scene: PackedScene = load("res://scenes/main.tscn")
	main = main_scene.instantiate()
	root.add_child(main)
	while main.active_scene == null or not main.active_scene.ready_for_ticks:
		await process_frame
	var old_scene: Node3D = main.active_scene
	old_scene.playing = false
	while old_scene.tick_pending:
		await process_frame
	if main.load_saved_checkpoint(damaged_path) != &"checksum_mismatch" or \
			main.active_scene != old_scene:
		_fail("damaged checkpoint altered main authority")
		return
	var load_error: StringName = main.load_saved_checkpoint(checkpoint_path)
	if not load_error.is_empty():
		_fail("main checkpoint load rejected: " + String(load_error))
		return
	while main.active_scene == old_scene:
		if not main.history_replay_error.is_empty():
			_fail("main checkpoint candidate failed: " + main.history_replay_error)
			return
		await process_frame
	preview = main.active_scene
	if preview.completed_ticks != 120 or not preview.enable_erosion or \
			preview.preset_index != 1 or main.selected_preset != 1 or \
			not main.enable_gpu_erosion:
		_fail("main checkpoint load did not switch authoritative scene")
		return
	preview.replay_target_tick = expected.target_tick
	preview.replay_ready = false
	while not preview.replay_ready:
		if not preview.last_error.is_empty():
			_fail(preview.last_error)
			return
		await process_frame
	while preview.collision_proxy.shapes.size() < 64 or \
			not preview.collision_proxy.pending_revisions.is_empty() or \
			not preview.collision_proxy.active_chunks.is_empty():
		await process_frame
	var actual := await _state_fingerprints()
	if finished:
		return
	for field in FIELDS:
		if actual[field] != expected[field]:
			_fail("cross-process GPU field mismatch: " + field)
			return
	if preview.completed_ticks != expected.target_tick or \
			preview.command_queue.applied_log.size() != expected.command_count:
		_fail("cross-process tick/history mismatch")
		return
	for ledger in ["water_source_m3", "water_sink_m3", "sand_source_m3",
			"sand_sink_m3", "inventory_m3"]:
		var value: float = preview.solver.get(ledger) if ledger.begins_with("water_") else \
			preview.shadow_domain.get(ledger if ledger != "inventory_m3" else "tool_inventory_m3")
		if absf(value - float(expected[ledger])) > 0.000001:
			_fail("cross-process ledger mismatch: " + ledger)
			return
	print("PASS: coupled checkpoint loaded in process B, checksum corruption rejected, tick=120->%d full GPU field hashes and ledgers exact, collision_chunks=%d" % [
		preview.completed_ticks, preview.collision_proxy.shapes.size()])
	_finish(0)


func _state_fingerprints() -> Dictionary:
	var hashes := {}
	for field in FIELDS:
		readback = PackedByteArray()
		RenderingServer.call_on_render_thread(_render_read_field.bind(field))
		while readback.is_empty() and not finished:
			await process_frame
		if finished:
			return {}
		var hash := HashingContext.new()
		hash.start(HashingContext.HASH_SHA256)
		hash.update(readback)
		hashes[field] = hash.finish().hex_encode()
	return hashes


func _render_read_field(field: String) -> void:
	var error: Error = preview.solver.request_data(field, _on_data)
	if error != OK:
		call_deferred("_fail", "checkpoint %s readback failed: %d" % [field, error])


func _on_data(data: PackedByteArray) -> void:
	call_deferred("_record_data", data)


func _record_data(data: PackedByteArray) -> void:
	if not finished:
		readback = data


func _watchdog() -> void:
	if finished:
		return
	if Time.get_ticks_msec() - started_ms > 180000:
		_fail("process checkpoint timed out at %d" % (preview.completed_ticks if preview != null else -1))
		return
	await process_frame
	call_deferred("_watchdog")


func _fail(message: String) -> void:
	if finished:
		return
	printerr("FAIL: " + message)
	_finish(1)


func _finish(code: int) -> void:
	finished = true
	if main != null:
		main.queue_free()
	elif preview != null:
		preview.queue_free()
	for frame in 3:
		await process_frame
	quit(code)

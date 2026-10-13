extends SceneTree

const SCENE := preload("res://scenes/water_visual_fixture.tscn")
const Store := preload("res://scripts/simulation/checkpoint_store.gd")

var readbacks: Dictionary = {}
var target_tick := 60


func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--target-tick="):
			target_tick = int(arg.trim_prefix("--target-tick="))
	call_deferred("_run")


func _run() -> void:
	var original: Node3D = SCENE.instantiate()
	root.add_child(original)
	if not await _wait_ready(original):
		quit(1)
		return
	var request := {"domain_id": original.shadow_domain.domain_id,
		"generation": original.generation, "request_id": 7,
		"start_tick": 30, "profile_id": &"small_packet",
		"amplitude_m": 0.05, "duration_s": 1.0, "seed": 91}
	if not original.request_wave(request).ok:
		push_error("wave request failed")
		quit(1)
		return
	if not await _wait_tick(original, 20):
		quit(1)
		return
	original.playing = false
	while original.tick_pending:
		await process_frame
	var saved_tick: int = original.completed_ticks
	var save_path := "user://w04_wave_" + str(Time.get_ticks_usec()) + ".sandcp"
	var save_error: StringName = original.request_checkpoint_save(save_path)
	if not save_error.is_empty():
		push_error("save request: " + String(save_error))
		quit(1)
		return
	var frames := 0
	while original.last_save_path.is_empty() and original.last_save_error.is_empty() and frames < 1200:
		await process_frame
		frames += 1
	if original.last_save_path.is_empty():
		push_error("save did not complete: " + String(original.last_save_error))
		quit(1)
		return
	var loaded: Dictionary = Store.load(save_path)
	if not loaded.error.is_empty() or loaded.checkpoint.wave_requests.size() != 1 or \
			not loaded.checkpoint.has("foam_history"):
		push_error("wave history missing from save: " + str(loaded.get("error")))
		quit(1)
		return
	var restored: Node3D = SCENE.instantiate()
	restored.generation = original.generation + 1
	restored.replay_checkpoint = loaded.checkpoint
	restored.replay_prefix_commands = loaded.prefix_commands
	restored.replay_target_tick = target_tick
	root.add_child(restored)
	if not await _wait_ready(restored):
		quit(1)
		return
	if restored.wave_requests.size() != 1 or \
			restored.wave_requests[0].generation != restored.generation or \
			restored.wave_highwater_id != 7:
		push_error("restored wave metadata mismatch")
		quit(1)
		return
	request.generation = original.generation
	if restored.request_wave(request).code != &"inactive_generation":
		push_error("old generation request accepted after restore")
		quit(1)
		return
	original.playing = true
	if not await _wait_tick(original, target_tick):
		quit(1)
		return
	original.playing = false
	if not await _wait_tick(restored, target_tick):
		quit(1)
		return
	while original.tick_pending or restored.tick_pending:
		await process_frame
	readbacks.clear()
	RenderingServer.call_on_render_thread(_read_state.bind(original, "original"))
	RenderingServer.call_on_render_thread(_read_state.bind(restored, "restored"))
	frames = 0
	while readbacks.size() < 12 and frames < 1200:
		await process_frame
		frames += 1
	var equal_fields := {}
	for field in ["water", "momentum_x", "momentum_z", "sand", "rock", "foam"]:
		equal_fields[field] = readbacks.has("original_" + field) and \
			readbacks.has("restored_" + field) and \
			readbacks["original_" + field] == readbacks["restored_" + field]
	var same_ledger: bool = is_equal_approx(original.solver.water_source_m3,
		restored.solver.water_source_m3) and is_equal_approx(original.solver.water_sink_m3,
		restored.solver.water_sink_m3)
	var passes := same_ledger and saved_tick >= 20 and saved_tick < 30
	for field in equal_fields:
		passes = passes and bool(equal_fields[field])
	print(("PASS" if passes else "FAIL") + ": W04 checkpoint " + JSON.stringify({
		"saved_tick": saved_tick, "target_tick": target_tick,
		"equal_fields": equal_fields,
		"same_ledger": same_ledger,
		"restored_generation": restored.generation}))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	quit(0 if passes else 1)


func _wait_ready(scene: Node3D) -> bool:
	for i in 1800:
		if scene.ready_for_ticks:
			return true
		if not scene.last_error.is_empty():
			break
		await process_frame
	push_error("scene init failed: " + scene.last_error)
	return false


func _wait_tick(scene: Node3D, target: int) -> bool:
	for i in maxi(3600, target * 12):
		if scene.completed_ticks >= target:
			return true
		if not scene.last_error.is_empty():
			break
		await process_frame
	push_error("scene tick failed: " + scene.last_error)
	return false


func _read_state(scene: Node3D, key: String) -> void:
	for field in ["water", "momentum_x", "momentum_z", "sand", "rock"]:
		var error: Error = scene.solver.request_data(field,
			_on_field.bind(key + "_" + field))
		if error != OK:
			call_deferred("_receive_field", PackedByteArray(), key + "_" + field)
	var foam_error: Error = scene.foam_field.request_data(
		_on_field.bind(key + "_foam"))
	if foam_error != OK:
		call_deferred("_receive_field", PackedByteArray(), key + "_foam")


func _on_field(data: PackedByteArray, key: String) -> void:
	call_deferred("_receive_field", data, key)


func _receive_field(data: PackedByteArray, key: String) -> void:
	readbacks[key] = data

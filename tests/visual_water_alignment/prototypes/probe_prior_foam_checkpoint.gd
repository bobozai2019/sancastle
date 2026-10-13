extends SceneTree

# Load staging checkpoints written before the separate bed-height history existed.

const Store := preload("res://scripts/simulation/checkpoint_store.gd")
const FIXED_SCENE := preload("res://scenes/water_render_demo.tscn")
const COUPLED_SCENE := preload("res://scenes/water_render_coupled.tscn")

var output_dir := ""
var fixed_path := ""
var coupled_path := ""
var received := PackedByteArray()


func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			output_dir = arg.trim_prefix("--output=")
		elif arg.begins_with("--fixed="):
			fixed_path = arg.trim_prefix("--fixed=")
		elif arg.begins_with("--coupled="):
			coupled_path = arg.trim_prefix("--coupled=")
	call_deferred("_run")


func _run() -> void:
	if not DirAccess.dir_exists_absolute(output_dir) or \
			not FileAccess.file_exists(fixed_path) or \
			not FileAccess.file_exists(coupled_path):
		_fail("paths")
		return
	var results := {}
	for spec in [
		{"name": "fixed", "scene": FIXED_SCENE, "path": fixed_path},
		{"name": "coupled", "scene": COUPLED_SCENE, "path": coupled_path},
	]:
		var loaded: Dictionary = Store.load(spec.path)
		if not loaded.error.is_empty():
			_fail(spec.name + " old checkpoint load: " + String(loaded.error))
			return
		var checkpoint: Dictionary = loaded.checkpoint
		if checkpoint.tick < 1 or checkpoint.foam_history.size() != 256 * 256 * 2 or \
				checkpoint.shadow.rock.size() != 256 * 256 or \
				checkpoint.shadow.sand.size() != 256 * 256:
			_fail(spec.name + " old checkpoint shape")
			return
		var scene: Node3D = spec.scene.instantiate()
		scene.replay_checkpoint = checkpoint
		scene.replay_prefix_commands = loaded.prefix_commands
		scene.replay_target_tick = checkpoint.tick
		root.add_child(scene)
		var frames := 0
		while (not scene.ready_for_ticks or not scene.replay_ready or \
				scene.tick_pending) and scene.last_error.is_empty() and frames < 9000:
			await process_frame
			frames += 1
		if not scene.last_error.is_empty() or not scene.replay_ready or \
				scene.completed_ticks != checkpoint.tick or scene.foam_field == null:
			_fail(spec.name + " old checkpoint restore: " + String(scene.last_error))
			return
		var initial: Dictionary = await _foam_metrics(scene)
		if not initial.get("valid", false) or initial.coverage_05 < 100:
			_fail(spec.name + " old checkpoint foam inactive/invalid")
			return
		scene.replay_target_tick = -1
		scene.playing = true
		frames = 0
		var target_tick: int = checkpoint.tick + 30
		while scene.completed_ticks < target_tick and scene.last_error.is_empty() and frames < 9000:
			await process_frame
			frames += 1
		scene.playing = false
		while scene.tick_pending and scene.last_error.is_empty() and frames < 10000:
			await process_frame
			frames += 1
		if not scene.last_error.is_empty() or scene.completed_ticks != target_tick:
			_fail(spec.name + " old checkpoint advance: " + String(scene.last_error))
			return
		var after: Dictionary = await _foam_metrics(scene)
		if not after.get("valid", false) or after.coverage_05 < 100:
			_fail(spec.name + " old checkpoint later foam inactive/invalid")
			return
		results[spec.name] = {
			"source_checkpoint": spec.path,
			"source_checkpoint_sha256": FileAccess.get_sha256(spec.path),
			"save_tick": checkpoint.tick,
			"restored_foam": initial,
			"advanced_tick": scene.completed_ticks,
			"advanced_foam": after,
			"effective_profile_sha256": scene.effective_render_profile_sha256,
		}
		scene.queue_free()
		for settle in 4:
			await process_frame
	var path := output_dir.path_join("prior_foam_checkpoint_manifest.json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_fail("manifest")
		return
	file.store_string(JSON.stringify(results, "\t"))
	file.close()
	print("PASS: pre-bed-history staging checkpoints restore and advance")
	quit(0)


func _foam_metrics(scene: Node3D) -> Dictionary:
	received = PackedByteArray()
	RenderingServer.call_on_render_thread(_read_foam.bind(scene))
	for frame in 1800:
		if not received.is_empty():
			break
		await process_frame
	if received.size() != 256 * 256 * 8:
		return {"valid": false}
	var values := received.to_float32_array()
	var coverage := 0
	var maximum := 0.0
	for cell in 256 * 256:
		var value: float = values[cell * 2]
		if not is_finite(value) or value < 0.0 or value > 1.0:
			return {"valid": false}
		if value > 0.05:
			coverage += 1
		maximum = maxf(maximum, value)
	return {"valid": true, "coverage_05": coverage, "foam_max": maximum}


func _read_foam(scene: Node3D) -> void:
	var rd := RenderingServer.get_rendering_device()
	var bytes := rd.texture_get_data(scene.foam_field.current_texture(), 0)
	call_deferred("_receive", bytes)


func _receive(bytes: PackedByteArray) -> void:
	received = bytes


func _fail(message: String) -> void:
	push_error("FAIL: prior foam checkpoint " + message)
	quit(1)

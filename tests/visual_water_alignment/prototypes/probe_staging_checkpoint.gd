extends SceneTree

const WATER_SCENE := preload("res://scenes/water_render_demo.tscn")
const COUPLED_SCENE := preload("res://scenes/water_render_coupled.tscn")
const Store := preload("res://scripts/simulation/checkpoint_store.gd")
const ReadbackGuard := preload("res://tests/visual_water_alignment/prototypes/checkpoint_readback_guard.gd")
const FIELDS := ["water", "momentum_x", "momentum_z", "foam_history",
	"local_front_history"]

var output_dir := ""
var run_id := ""
var render_profile_path := "res://tests/visual_water_alignment/prototypes/water_render_staging_v1.json"
var received := {}
var front_face_source_gate := false
var pre_wave_source_gate := false
var interactive_source_gate := false
var source_start_tick := 8


func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			output_dir = arg.trim_prefix("--output=")
		elif arg.begins_with("--run-id="):
			run_id = arg.trim_prefix("--run-id=")
		elif arg.begins_with("--profile="):
			render_profile_path = arg.trim_prefix("--profile=")
		elif arg == "--front-face-source-gate":
			front_face_source_gate = true
		elif arg == "--pre-wave-source-gate":
			pre_wave_source_gate = true
		elif arg == "--interactive-source-gate":
			interactive_source_gate = true
	call_deferred("_run")


func _run() -> void:
	if output_dir.is_empty() or run_id.is_empty() or \
			not DirAccess.dir_exists_absolute(output_dir):
		_fail("output/run-id invalid")
		return
	if (pre_wave_source_gate or interactive_source_gate) and not front_face_source_gate or \
			(pre_wave_source_gate and interactive_source_gate):
		_fail("invalid source gate probe mode")
		return
	var save_target := 22 if interactive_source_gate else (4 if pre_wave_source_gate else 240)
	var comparison_ticks := [22, 24, 25, 60, 120] if interactive_source_gate else \
		([4, 8, 37, 120] if pre_wave_source_gate else [240, 270, 600])
	source_start_tick = 25 if interactive_source_gate else 8
	var results := {}
	for case in [{"name": "fixed", "scene": WATER_SCENE},
			{"name": "coupled", "scene": COUPLED_SCENE}]:
		var original: Node3D = case.scene.instantiate()
		original.render_profile_path = render_profile_path
		original.prototype_front_face_source_gate = front_face_source_gate
		if interactive_source_gate:
			original.staging_wave_workload = "none"
			original.replay_target_tick = 20
		elif pre_wave_source_gate:
			original.replay_target_tick = save_target
		root.add_child(original)
		if not await _wait_ready(original):
			_fail(case.name + " original init: " + original.last_error)
			return
		if front_face_source_gate:
			original.water_material.set_shader_parameter(
				"prototype_front_face_rim_tone", true)
		if interactive_source_gate:
			if not original.wave_requests.is_empty() or not await _wait_tick(original, 20):
				_fail(case.name + " interactive initial state")
				return
			original.playing = false
			while original.tick_pending:
				await process_frame
			if original.completed_ticks != 20:
				_fail(case.name + " interactive initial tick overshot")
				return
			var wave := {"domain_id": original.shadow_domain.domain_id,
				"generation": original.generation, "request_id": 1,
				"start_tick": source_start_tick, "profile_id": &"test_packet",
				"amplitude_m": 0.18, "duration_s": 6.0, "seed": 31}
			var stale: Dictionary = wave.duplicate(true)
			stale.generation = original.generation - 1
			if original.request_wave(stale).code != &"inactive_generation" or \
					not original.wave_requests.is_empty():
				_fail(case.name + " stale request admitted")
				return
			if not original.request_wave(wave).ok:
				_fail(case.name + " interactive request rejected")
				return
			original.replay_target_tick = save_target
			original.replay_ready = false
			original.playing = true
		if original.wave_requests.size() != 1 or \
				original.wave_requests[0].start_tick != source_start_tick or \
				original.wave_requests[0].seed != 31 or \
				not await _wait_tick(original, save_target):
			_fail(case.name + " wave or save tick: " + original.last_error)
			return
		original.playing = false
		while original.tick_pending:
			await process_frame
		var save_tick: int = original.completed_ticks
		if save_tick != save_target:
			_fail(case.name + " save tick overshot: " + str(save_tick))
			return
		if pre_wave_source_gate or interactive_source_gate:
			original.replay_target_tick = -1
		var path := output_dir.path_join("%s_%s.sandcp" % [run_id, case.name])
		if original.request_checkpoint_save(path) != &"":
			_fail(case.name + " save request")
			return
		var frames := 0
		while original.last_save_path.is_empty() and original.last_save_error.is_empty() and frames < 1800:
			await process_frame
			frames += 1
		if original.last_save_path.is_empty():
			_fail(case.name + " save completion: " + String(original.last_save_error))
			return
		var loaded: Dictionary = Store.load(path)
		if not loaded.error.is_empty() or \
				loaded.checkpoint.render_profile.source_sha256 != original.requested_render_profile_sha256 or \
				loaded.checkpoint.render_profile.visual_time_s != float(save_tick) / 30.0 or \
				loaded.checkpoint.foam_history.size() != 256 * 256 * 2 or \
				loaded.checkpoint.local_front_history.size() != 256 * 256 * 2 or \
				loaded.checkpoint.wave_requests.size() != 1:
			_fail(case.name + " checkpoint profile/foam/wave missing: " + String(loaded.error))
			return
		var active_foam_cells := 0
		var active_front_cells := 0
		for cell in 256 * 256:
			active_foam_cells += int(loaded.checkpoint.foam_history[cell * 2] > 0.05)
			active_front_cells += int(loaded.checkpoint.local_front_history[cell * 2 + 1] > 0.000001)
		if not pre_wave_source_gate and not interactive_source_gate and \
				(active_foam_cells < 100 or active_front_cells < 100):
			_fail(case.name + " save point not active: foam=" +
				str(active_foam_cells) + " front=" + str(active_front_cells))
			return
		var missing_profile: Dictionary = loaded.checkpoint.duplicate(true)
		missing_profile.erase("render_profile")
		if Store.save(path + ".invalid", missing_profile,
				loaded.prefix_commands, case.name == "coupled") != &"invalid_render_profile":
			_fail(case.name + " missing profile accepted")
			return
		var missing_front: Dictionary = loaded.checkpoint.duplicate(true)
		missing_front.erase("local_front_history")
		if Store.save(path + ".invalid_front", missing_front,
				loaded.prefix_commands, case.name == "coupled") != &"invalid_local_front_history":
			_fail(case.name + " missing local front accepted")
			return
		var restored: Node3D = case.scene.instantiate()
		restored.render_profile_path = render_profile_path
		restored.prototype_front_face_source_gate = front_face_source_gate
		restored.generation = original.generation + 1
		restored.replay_checkpoint = loaded.checkpoint
		restored.replay_prefix_commands = loaded.prefix_commands
		restored.replay_target_tick = save_tick
		root.add_child(restored)
		if not await _wait_ready(restored):
			_fail(case.name + " restored init: " + restored.last_error)
			return
		if front_face_source_gate:
			restored.water_material.set_shader_parameter(
				"prototype_front_face_rim_tone", true)
		frames = 0
		while (not restored.replay_ready or restored.tick_pending) and frames < 9000:
			await process_frame
			frames += 1
		if not restored.replay_ready or restored.completed_ticks != save_tick or \
				restored.wave_requests.size() != 1 or \
				restored.wave_requests[0].generation != restored.generation:
			_fail(case.name + " restored save point: " + restored.last_error)
			return
		var checkpoints := {}
		for target in comparison_ticks:
			if target != save_tick:
				restored.replay_target_tick = -1
				original.playing = true
				restored.playing = true
				if not await _advance_pair(original, restored, target):
					_fail(case.name + " advance to " + str(target))
					return
			var comparison: Dictionary = await _compare_pair(original, restored,
					case.name, target)
			if not comparison.get("ok", false):
				_fail(case.name + " tick " + str(target) + ": " + String(comparison.get("error", "comparison")))
				return
			checkpoints[str(target)] = comparison
		results[case.name] = {"save_tick": save_tick,
			"target_tick": comparison_ticks.back(),
			"save_foam_cells_gt_0_05": active_foam_cells,
			"save_front_cells_gt_1e_6": active_front_cells,
			"profile_sha256": original.requested_render_profile_sha256,
			"effective_profile_sha256": original.effective_render_profile_sha256,
			"visual_time_s": original.visual_time_s,
			"comparisons": checkpoints,
			"saved_checkpoint": path,
			"saved_checkpoint_sha256": FileAccess.get_sha256(path)}
		original.queue_free()
		restored.queue_free()
		for cleanup in 4:
			await process_frame
	var manifest_path := output_dir.path_join(run_id + "_manifest.json")
	var file := FileAccess.open(manifest_path, FileAccess.WRITE)
	if file == null:
		_fail("manifest open")
		return
	file.store_string(JSON.stringify({"run_id": run_id,
		"render_profile_path": render_profile_path,
		"front_face_source_gate": front_face_source_gate,
		"pre_wave_source_gate": pre_wave_source_gate,
		"interactive_source_gate": interactive_source_gate,
		"source_start_tick": source_start_tick,
		"cases": results}, "\t"))
	file.close()
	print("PASS: W08 staging checkpoint fixed/coupled")
	quit(0)


func _wait_ready(scene: Node3D) -> bool:
	for frame in 1800:
		if scene.ready_for_ticks:
			return true
		if not scene.last_error.is_empty():
			return false
		await process_frame
	return false


func _wait_tick(scene: Node3D, target: int) -> bool:
	for frame in 9000:
		if scene.completed_ticks >= target:
			return true
		if not scene.last_error.is_empty():
			return false
		await process_frame
	return false


func _advance_pair(original: Node3D, restored: Node3D, target: int) -> bool:
	for frame in 18000:
		if original.completed_ticks >= target:
			original.playing = false
		if restored.completed_ticks >= target:
			restored.playing = false
		if not original.last_error.is_empty() or not restored.last_error.is_empty():
			return false
		if original.completed_ticks == target and restored.completed_ticks == target and \
				not original.tick_pending and not restored.tick_pending:
			return true
		await process_frame
	return false


func _compare_pair(original: Node3D, restored: Node3D,
		case_name: String, target: int) -> Dictionary:
	if original.completed_ticks != target or restored.completed_ticks != target or \
			original.tick_pending or restored.tick_pending or \
			not is_equal_approx(original.visual_time_s, float(target) / 30.0) or \
			not is_equal_approx(restored.visual_time_s, float(target) / 30.0) or \
			original.effective_render_profile_sha256 != restored.effective_render_profile_sha256:
		return {"ok": false, "error": "tick/time/effective profile"}
	if front_face_source_gate:
		var original_started := bool(original.water_material.get_shader_parameter(
			"prototype_front_face_source_started"))
		var restored_started := bool(restored.water_material.get_shader_parameter(
			"prototype_front_face_source_started"))
		var expected_started := target >= source_start_tick
		if original_started != expected_started or restored_started != expected_started:
			return {"ok": false, "error": "source gate phase mismatch: " +
				str({"expected": expected_started, "original": original_started,
					"restored": restored_started})}
	var offshore_core_started: Variant = null
	if original.requested_render_profile.visual.get("offshore_core", false):
		var original_core_started := bool(original.water_material.get_shader_parameter(
			"prototype_offshore_core_source_started"))
		var restored_core_started := bool(restored.water_material.get_shader_parameter(
			"prototype_offshore_core_source_started"))
		var expected_core_started := target >= source_start_tick
		if original_core_started != expected_core_started or \
				restored_core_started != expected_core_started:
			return {"ok": false, "error": "offshore core source phase mismatch: " +
				str({"expected": expected_core_started,
					"original": original_core_started,
					"restored": restored_core_started})}
		offshore_core_started = expected_core_started
	received.clear()
	var expected := {
		"original": {"tick": original.completed_ticks,
			"revision": original.solver.state_revision,
			"generation": original.generation},
		"restored": {"tick": restored.completed_ticks,
			"revision": restored.solver.state_revision,
			"generation": restored.generation},
	}
	RenderingServer.call_on_render_thread(_read.bind(original, "original",
		expected.original))
	RenderingServer.call_on_render_thread(_read.bind(restored, "restored",
		expected.restored))
	for frame in 1800:
		if received.size() >= FIELDS.size() * 2 + 2:
			break
		await process_frame
	var guard: Dictionary = ReadbackGuard.compare(received, expected, target)
	if not guard.ok:
		return guard
	var images := {}
	for side in ["original", "restored"]:
		original.visible = side == "original"
		restored.visible = side == "restored"
		var scene: Node3D = original if side == "original" else restored
		scene.overview_camera.make_current()
		for settle in 30:
			await RenderingServer.frame_post_draw
		var image_path := output_dir.path_join("%s_%s_tick%d_%s.png" % [
			run_id, case_name, target, side])
		if root.get_texture().get_image().save_png(image_path) != OK:
			return {"ok": false, "error": "image write " + side}
		images[side] = FileAccess.get_sha256(image_path)
	original.visible = true
	restored.visible = true
	if images.original != images.restored:
		return {"ok": false, "error": "image phase " + str({
			"camera_original": original.overview_camera.global_transform,
			"camera_restored": restored.overview_camera.global_transform,
			"fov_original": original.overview_camera.fov,
			"fov_restored": restored.overview_camera.fov,
			"images": images})}
	return {"ok": true, "tick": target, "visual_time_s": original.visual_time_s,
		"equal_gpu_fields": guard.equal_gpu_fields,
		"readback_stamps": expected, "image_sha256": images.original,
		"front_face_source_started": target >= source_start_tick if front_face_source_gate else null,
		"offshore_core_source_started": offshore_core_started,
		"effective_profile_sha256": original.effective_render_profile_sha256}


func _read(scene: Node3D, prefix: String, stamp: Dictionary) -> void:
	var rd := RenderingServer.get_rendering_device()
	var data := {prefix + "_stamp": stamp}
	for field in FIELDS:
		var texture: RID = scene.foam_field.current_texture() if field == \
			"foam_history" else (scene.local_front_field.texture if field == \
			"local_front_history" else scene.solver.current_texture(field))
		data[prefix + "_" + field] = rd.texture_get_data(texture, 0)
	call_deferred("_receive", data)


func _receive(data: Dictionary) -> void:
	received.merge(data)


func _fail(message: String) -> void:
	push_error("FAIL: W08 staging checkpoint " + message)
	quit(1)

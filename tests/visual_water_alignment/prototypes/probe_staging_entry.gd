extends SceneTree

const FIXED_SCENE := preload("res://scenes/water_render_demo.tscn")
const COUPLED_SCENE := preload("res://scenes/water_render_coupled.tscn")
const FIXED_CONTINUOUS_SCENE := preload("res://scenes/water_render_demo_continuous.tscn")
const COUPLED_CONTINUOUS_SCENE := preload("res://scenes/water_render_coupled_continuous.tscn")
const UniformSnapshot := preload("res://scripts/visual/water_render_uniform_snapshot.gd")
const RenderProfile := preload("res://scripts/visual/water_render_profile.gd")

var output_dir := ""
var run_id := ""
var render_profile_path := "res://tests/visual_water_alignment/prototypes/water_render_staging_v1.json"
var wave_workload_id := "single_packet_v1"
var target_tick := 30
var pause_test := false
var inject_water_readback_timeout := false
var water_readback := PackedByteArray()
var water_readback_ready := false


func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			output_dir = arg.trim_prefix("--output=")
		elif arg.begins_with("--run-id="):
			run_id = arg.trim_prefix("--run-id=")
		elif arg.begins_with("--profile="):
			render_profile_path = arg.trim_prefix("--profile=")
		elif arg.begins_with("--wave-workload="):
			wave_workload_id = arg.trim_prefix("--wave-workload=")
		elif arg.begins_with("--tick="):
			target_tick = int(arg.trim_prefix("--tick="))
		elif arg == "--pause-test":
			pause_test = true
		elif arg == "--inject-water-readback-timeout":
			inject_water_readback_timeout = true
	call_deferred("_run")


func _run() -> void:
	if output_dir.is_empty() or run_id.is_empty() or target_tick < 1 or \
			wave_workload_id not in ["none", "single_packet_v1", "continuous_packets_v1"] or \
			not DirAccess.dir_exists_absolute(output_dir):
		_fail("output/run-id invalid")
		return
	var continuous := wave_workload_id == "continuous_packets_v1"
	var cases := [{"name": "fixed", "scene": FIXED_CONTINUOUS_SCENE if continuous else FIXED_SCENE},
		{"name": "coupled", "scene": COUPLED_CONTINUOUS_SCENE if continuous else COUPLED_SCENE}]
	var results := {}
	for case in cases:
		var preview: Node3D = case.scene.instantiate()
		preview.render_profile_path = render_profile_path
		preview.staging_wave_workload = wave_workload_id
		root.add_child(preview)
		var frames := 0
		while not preview.ready_for_ticks and preview.last_error.is_empty() and \
				frames < 1800:
			await process_frame
			frames += 1
		if not preview.ready_for_ticks or not preview.last_error.is_empty():
			_fail("%s initialization: %s" % [case.name, preview.last_error])
			return
		for field in ["depth_write", "face_normal", "screen_abs_fresnel",
				"screen_world_glint",
				"crest_broken_core",
				"local_front", "crest_height_m", "shallow_extinction_m",
				"refraction_scale", "caustic_pattern", "caustic_pattern_width",
				"caustic_pattern_height"]:
			var drift: Dictionary = preview.effective_render_profile.duplicate(true)
			match field:
				"caustic_pattern": drift[field] = "res://wrong_pattern.png"
				"caustic_pattern_width", "caustic_pattern_height": drift[field] = 512
				"crest_height_m", "shallow_extinction_m", "refraction_scale":
					drift[field] = float(drift[field]) + 0.01
				_: drift[field] = not drift[field]
			if RenderProfile.effective_matches_request(preview.requested_render_profile,
					preview.fixture_id, drift):
				_fail("%s missed effective drift: %s" % [case.name, field])
				return
		if preview.requested_render_profile.schema_version == 2:
			for field in ["offshore_core", "offshore_core_broken"]:
				var drift: Dictionary = preview.effective_render_profile.duplicate(true)
				drift[field] = not drift[field]
				if RenderProfile.effective_matches_request(
						preview.requested_render_profile, preview.fixture_id, drift):
					_fail("%s missed effective drift: %s" % [case.name, field])
					return
		if preview.requested_render_profile.schema_version >= 3:
			for field in ["offshore_core", "offshore_core_broken",
					"offshore_core_crown"]:
				var drift: Dictionary = preview.effective_render_profile.duplicate(true)
				drift[field] = not drift[field]
				if RenderProfile.effective_matches_request(
						preview.requested_render_profile, preview.fixture_id, drift):
					_fail("%s missed effective drift: %s" % [case.name, field])
					return
		if preview.requested_render_profile.schema_version >= 4:
			var bed_drift: Dictionary = preview.effective_render_profile.duplicate(true)
			bed_drift["reference_bed"] = "natural_structured_v1"
			if RenderProfile.effective_matches_request(
					preview.requested_render_profile, preview.fixture_id, bed_drift):
				_fail("%s missed reference bed drift" % case.name)
				return
		if preview.requested_render_profile.schema_version >= 4:
			var optical_drift: Dictionary = preview.effective_render_profile.duplicate(true)
			optical_drift["shallow_preserve"] = not optical_drift.get(
				"shallow_preserve", false)
			if RenderProfile.effective_matches_request(
					preview.requested_render_profile, preview.fixture_id, optical_drift):
				_fail("%s missed shallow preserve drift" % case.name)
				return
		var initial_hashes := {
			"rock": hash(preview.shadow_domain.rock),
			"sand": hash(preview.shadow_domain.sand),
			"water": hash(preview.shadow_domain.water),
		}
		frames = 0
		while preview.completed_ticks < target_tick and preview.last_error.is_empty() and \
				frames < max(3600, target_tick * 60):
			await process_frame
			frames += 1
		preview.playing = false
		while preview.tick_pending and frames < 3900:
			await process_frame
			frames += 1
		if not preview.last_error.is_empty() or preview.completed_ticks < target_tick or \
				preview.tick_pending or preview.effective_render_profile.is_empty() or \
				not is_equal_approx(preview.visual_time_s,
				float(preview.completed_ticks) / 30.0):
			_fail("%s completed clock: ticks=%d time=%f error=%s" % [
				case.name, preview.completed_ticks, preview.visual_time_s,
				preview.last_error])
			return
		water_readback_ready = false
		water_readback = PackedByteArray()
		if not inject_water_readback_timeout and \
				preview.solver.request_data("water", _on_water_readback) != OK:
			_fail("%s water readback request" % case.name)
			return
		var readback_frames := 0
		var readback_limit := 3 if inject_water_readback_timeout else 1800
		while not water_readback_ready and readback_frames < readback_limit:
			await process_frame
			readback_frames += 1
		if not water_readback_ready:
			_fail("%s water readback timeout after %d frames" % [
				case.name, readback_frames])
			return
		if water_readback.size() != 256 * 256 * 4:
			_fail("%s water readback size" % case.name)
			return
		var water_path := output_dir.path_join("%s_%s_water_f32.bin" % [
			run_id, case.name])
		var water_file := FileAccess.open(water_path, FileAccess.WRITE)
		if water_file == null:
			_fail("water write " + water_path)
			return
		water_file.store_buffer(water_readback)
		water_file.close()
		var image_path := output_dir.path_join("%s_%s_tick%d.png" % [
			run_id, case.name, preview.completed_ticks])
		for warmup in 30:
			await RenderingServer.frame_post_draw
		if root.get_texture().get_image().save_png(image_path) != OK:
			_fail("PNG write " + image_path)
			return
		results[case.name] = {
			"wave_workload_id": preview.staging_wave_workload,
			"wave_requests": preview.wave_requests,
			"fixture_id": String(preview.fixture_id),
			"tick": preview.completed_ticks,
			"revision": preview.solver.state_revision,
			"visual_time_s": preview.visual_time_s,
			"requested_profile_sha256": preview.requested_render_profile_sha256,
			"effective_profile": preview.effective_render_profile,
			"effective_profile_sha256": preview.effective_render_profile_sha256,
			"terrain_uniforms": UniformSnapshot.material_values(
				preview.terrain_material),
			"water_uniforms": UniformSnapshot.material_values(
				preview.water_material),
			"initial_state_hashes": initial_hashes,
			"image": image_path,
			"water_field": water_path,
			"water_sha256": FileAccess.get_sha256(water_path),
		}
		if pause_test:
			var held_tick: int = preview.completed_ticks
			var held_visual_time_s: float = preview.visual_time_s
			for hold_frame in 30:
				await RenderingServer.frame_post_draw
			var paused_path := output_dir.path_join("%s_%s_paused.png" % [
				run_id, case.name])
			if root.get_texture().get_image().save_png(paused_path) != OK or \
					FileAccess.get_sha256(paused_path) != FileAccess.get_sha256(image_path) or \
					preview.completed_ticks != held_tick or \
					not is_equal_approx(preview.visual_time_s, held_visual_time_s):
				_fail("%s pause changed frame/time/tick" % case.name)
				return
			preview.playing = true
			var resume_frames := 0
			while preview.completed_ticks < held_tick + 1 and preview.last_error.is_empty() and \
					resume_frames < 1200:
				await process_frame
				resume_frames += 1
			preview.playing = false
			while preview.tick_pending and resume_frames < 1500:
				await process_frame
				resume_frames += 1
			if preview.completed_ticks < held_tick + 1 or not preview.last_error.is_empty() or \
					not is_equal_approx(preview.visual_time_s,
					float(preview.completed_ticks) / 30.0):
				_fail("%s resume clock/tick" % case.name)
				return
			for settle in 30:
				await RenderingServer.frame_post_draw
			var resumed_path := output_dir.path_join("%s_%s_resumed_tick%d.png" % [
				run_id, case.name, preview.completed_ticks])
			if root.get_texture().get_image().save_png(resumed_path) != OK:
				_fail("%s resumed PNG write" % case.name)
				return
			results[case.name]["pause_resume"] = {
				"held_tick": held_tick, "held_visual_time_s": held_visual_time_s,
				"paused_image_sha256": FileAccess.get_sha256(paused_path),
				"resumed_tick": preview.completed_ticks,
				"resumed_visual_time_s": preview.visual_time_s,
				"resumed_image": resumed_path,
				"resumed_image_sha256": FileAccess.get_sha256(resumed_path),
			}
		preview.queue_free()
		for cleanup in 4:
			await process_frame
	if results.fixed.initial_state_hashes != results.coupled.initial_state_hashes:
		_fail("initial bed mismatch")
		return
	var path := output_dir.path_join(run_id + "_manifest.json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_fail("manifest write " + path)
		return
	file.store_string(JSON.stringify({"run_id": run_id, "cases": results,
		"target_tick": target_tick,
		"viewport_px": [root.size.x, root.size.y],
		"hardware": RenderingServer.get_video_adapter_name()}, "\t"))
	file.close()
	print("PASS: staging entry fixed/coupled tick>=" + str(target_tick))
	quit(0)


func _on_water_readback(data: PackedByteArray) -> void:
	call_deferred("_receive_water_readback", data)


func _receive_water_readback(data: PackedByteArray) -> void:
	water_readback = data
	water_readback_ready = true


func _fail(message: String) -> void:
	push_error("FAIL: staging entry " + message)
	quit(1)

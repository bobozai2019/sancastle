extends SceneTree

const WATER_SCENE := preload("res://scenes/water_render_demo.tscn")
const COUPLED_SCENE := preload("res://scenes/water_render_coupled.tscn")
const WATER_CONTINUOUS_SCENE := preload("res://scenes/water_render_demo_continuous.tscn")
const COUPLED_CONTINUOUS_SCENE := preload("res://scenes/water_render_coupled_continuous.tscn")

var case_id := "water"
var output_dir := ""
var run_id := ""
var render_profile_path := "res://tests/visual_water_alignment/prototypes/water_render_staging_v1.json"
var wave_workload_id := "single_packet_v1"
var target_tick := 60
var args_valid := true
var write_frame_timeline := false
var camera_sweep := false
var camera_id := "oblique"
var front_face_rim_tone := false
var front_face_foam_gate := false
var front_face_source_gate := false
var offshore_core := false
var offshore_core_broken := false
var shore_contour := false
var caustic_recovery_gain := 0.0
var caustic_recovery_scale := 1.0


func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--case="):
			case_id = arg.trim_prefix("--case=")
		elif arg.begins_with("--output="):
			output_dir = arg.trim_prefix("--output=")
		elif arg.begins_with("--run-id="):
			run_id = arg.trim_prefix("--run-id=")
		elif arg.begins_with("--profile="):
			render_profile_path = arg.trim_prefix("--profile=")
		elif arg.begins_with("--wave-workload="):
			wave_workload_id = arg.trim_prefix("--wave-workload=")
		elif arg.begins_with("--tick="):
			target_tick = int(arg.trim_prefix("--tick="))
		elif arg == "--write-frame-timeline":
			write_frame_timeline = true
		elif arg == "--camera-sweep":
			camera_sweep = true
		elif arg.begins_with("--camera="):
			camera_id = arg.trim_prefix("--camera=")
		elif arg == "--front-face-rim-tone":
			front_face_rim_tone = true
		elif arg == "--front-face-foam-gate":
			front_face_foam_gate = true
		elif arg == "--front-face-source-gate":
			front_face_source_gate = true
		elif arg == "--offshore-core":
			offshore_core = true
		elif arg == "--offshore-core-broken":
			offshore_core = true
			offshore_core_broken = true
		elif arg == "--shore-contour":
			shore_contour = true
		elif arg.begins_with("--caustic-recovery-gain="):
			caustic_recovery_gain = float(arg.trim_prefix("--caustic-recovery-gain="))
		elif arg.begins_with("--caustic-recovery-scale="):
			caustic_recovery_scale = float(arg.trim_prefix("--caustic-recovery-scale="))
		else:
			args_valid = false
	call_deferred("_run")


func _run() -> void:
	if not args_valid or (camera_sweep and not write_frame_timeline) or \
			(camera_sweep and camera_id != "oblique") or \
			camera_id not in ["oblique", "close", "grazing", "wavefront_side"] or \
			(front_face_foam_gate and not front_face_rim_tone) or \
			case_id not in ["water", "coupled"] or \
			wave_workload_id not in ["none", "single_packet_v1", "continuous_packets_v1"] or \
			output_dir.is_empty() or run_id.is_empty() or target_tick < 1 or \
			caustic_recovery_gain < 0.0 or caustic_recovery_gain > 1.0 or \
			caustic_recovery_scale < 1.0 or caustic_recovery_scale > 3.0 or \
			(caustic_recovery_gain == 0.0 and caustic_recovery_scale != 1.0) or \
			not DirAccess.dir_exists_absolute(output_dir) or \
			root.size != Vector2i(1920, 1080) or \
			DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED:
		_fail("arguments or 1080p VSync-off invalid")
		return
	var scene: PackedScene
	if wave_workload_id == "continuous_packets_v1":
		scene = WATER_CONTINUOUS_SCENE if case_id == "water" else COUPLED_CONTINUOUS_SCENE
	else:
		scene = WATER_SCENE if case_id == "water" else COUPLED_SCENE
	var preview: Node3D = scene.instantiate()
	preview.prototype_front_face_source_gate = front_face_source_gate
	preview.prototype_offshore_core_source_gate = offshore_core
	preview.render_profile_path = render_profile_path
	preview.staging_wave_workload = wave_workload_id
	root.add_child(preview)
	var frames := 0
	while not preview.ready_for_ticks and preview.last_error.is_empty() and frames < 1800:
		await process_frame
		frames += 1
	if not preview.ready_for_ticks or not preview.last_error.is_empty():
		_fail("initialization: " + preview.last_error)
		return
	if front_face_rim_tone:
		var capabilities: Dictionary = preview.requested_render_profile.capabilities
		if not capabilities.local_front.enabled or not capabilities.screen_optics.enabled:
			_fail("front face rim tone requires local front and screen optics")
			return
		preview.water_material.set_shader_parameter(
			"prototype_front_face_rim_tone", true)
		preview.water_material.set_shader_parameter(
			"prototype_front_face_foam_gate", front_face_foam_gate)
	if offshore_core:
		if not preview.requested_render_profile.capabilities.local_front.enabled:
			_fail("offshore core requires local front")
			return
		preview.water_material.set_shader_parameter("prototype_offshore_core", true)
		preview.water_material.set_shader_parameter("prototype_offshore_core_broken",
			offshore_core_broken)
	var effective_offshore_core := bool(preview.water_material.get_shader_parameter(
		"prototype_offshore_core"))
	var effective_offshore_core_broken := bool(
		preview.water_material.get_shader_parameter("prototype_offshore_core_broken"))
	if shore_contour:
		if not preview.requested_render_profile.capabilities.local_front.enabled:
			_fail("shore contour requires local front")
			return
		preview.water_material.set_shader_parameter("prototype_shore_unscaled_depth", true)
		preview.water_material.set_shader_parameter("prototype_shore_linear_weights", true)
	var recovery_pattern: Texture2D
	if caustic_recovery_gain > 0.0:
		var cap: Dictionary = preview.requested_render_profile.capabilities
		if not cap.screen_optics.enabled or not cap.fold_caustics.enabled:
			_fail("caustic recovery needs staging screen optics and fold pattern")
			return
		recovery_pattern = preview.terrain_material.get_shader_parameter(
			"caustic_pattern") as Texture2D
		if recovery_pattern == null or recovery_pattern.get_width() != 1024:
			_fail("caustic recovery pattern missing")
			return
		preview.terrain_material.set_shader_parameter(
			"prototype_caustic_uv_scale", caustic_recovery_scale)
		preview.water_material.set_shader_parameter(
			"prototype_caustic_pattern", recovery_pattern)
		preview.water_material.set_shader_parameter(
			"prototype_caustic_recovery_uv_scale", caustic_recovery_scale)
		preview.water_material.set_shader_parameter(
			"prototype_caustic_recovery_gain", caustic_recovery_gain)
	var sweep_camera: Camera3D
	var sweep_start := Transform3D.IDENTITY
	var sweep_end := Transform3D.IDENTITY
	var sweep_start_fov := 0.0
	var sweep_end_fov := 0.0
	if not camera_sweep and camera_id != "oblique" and \
			not preview.set_fixture_camera(StringName(camera_id)):
		_fail("fixture camera unavailable: " + camera_id)
		return
	if camera_sweep:
		if not preview.set_fixture_camera(&"oblique"):
			_fail("camera sweep oblique unavailable")
			return
		sweep_camera = preview.overview_camera
		sweep_start = sweep_camera.transform
		sweep_start_fov = sweep_camera.fov
		if not preview.set_fixture_camera(&"grazing"):
			_fail("camera sweep grazing unavailable")
			return
		sweep_end = sweep_camera.transform
		sweep_end_fov = sweep_camera.fov
		sweep_camera.transform = sweep_start
		sweep_camera.fov = sweep_start_fov
	frames = 0
	var timeline := []
	while preview.completed_ticks < target_tick and preview.last_error.is_empty() and frames < 18000:
		await process_frame
		frames += 1
		if camera_sweep:
			var fraction := clampf(float(frames) / float(target_tick * 2), 0.0, 1.0)
			sweep_camera.transform = sweep_start.interpolate_with(sweep_end, fraction)
			sweep_camera.fov = lerpf(sweep_start_fov, sweep_end_fov, fraction)
		if write_frame_timeline:
			var sample := {"drawn_frame": Engine.get_frames_drawn(),
				"completed_tick": preview.completed_ticks,
				"visual_time_s": preview.visual_time_s}
			if front_face_source_gate:
				sample["front_face_source_started"] = bool(
					preview.water_material.get_shader_parameter(
						"prototype_front_face_source_started"))
			if effective_offshore_core:
				sample["offshore_core_source_started"] = bool(
					preview.water_material.get_shader_parameter(
						"prototype_offshore_core_source_started"))
			if camera_sweep:
				var pos := sweep_camera.position
				var forward := -sweep_camera.transform.basis.z
				sample["camera_position"] = [pos.x, pos.y, pos.z]
				sample["camera_forward"] = [forward.x, forward.y, forward.z]
				sample["camera_fov"] = sweep_camera.fov
			timeline.append(sample)
	preview.playing = false
	while preview.tick_pending and frames < 18300:
		await process_frame
		frames += 1
		if write_frame_timeline:
			var pending_sample := {"drawn_frame": Engine.get_frames_drawn(),
				"completed_tick": preview.completed_ticks,
				"visual_time_s": preview.visual_time_s}
			if front_face_source_gate:
				pending_sample["front_face_source_started"] = bool(
					preview.water_material.get_shader_parameter(
						"prototype_front_face_source_started"))
			if effective_offshore_core:
				pending_sample["offshore_core_source_started"] = bool(
					preview.water_material.get_shader_parameter(
						"prototype_offshore_core_source_started"))
			timeline.append(pending_sample)
	if not preview.last_error.is_empty() or preview.completed_ticks < target_tick or \
			preview.tick_pending or not is_equal_approx(preview.visual_time_s,
			float(preview.completed_ticks) / 30.0):
		_fail("runtime tick or visual clock: " + preview.last_error)
		return
	var summary := {
		"role": "w08_staging_profile_movie",
		"run_id": run_id,
		"case": case_id,
		"fixture_id": String(preview.fixture_id),
		"target_tick": target_tick,
		"completed_tick": preview.completed_ticks,
		"visual_time_s": preview.visual_time_s,
		"requested_profile_path": render_profile_path,
		"requested_profile_sha256": preview.requested_render_profile_sha256,
		"effective_profile": preview.effective_render_profile,
		"effective_profile_sha256": preview.effective_render_profile_sha256,
		"effective_water_shader": preview.water_material.shader.resource_path,
		"wave_workload_id": preview.staging_wave_workload,
		"wave_requests": preview.wave_requests,
		"viewport_px": [root.size.x, root.size.y],
		"vsync_mode": DisplayServer.window_get_vsync_mode(),
		"movie_maker_requested": true,
		"rendering_driver": RenderingServer.get_current_rendering_driver_name(),
		"adapter": RenderingServer.get_video_adapter_name(),
		"timeline_sample_count": timeline.size(),
		"camera_sweep": camera_sweep,
		"camera_id": camera_id,
		"front_face_rim_tone": front_face_rim_tone,
		"front_face_foam_gate": front_face_foam_gate,
		"front_face_source_gate": front_face_source_gate,
		"offshore_core": effective_offshore_core,
		"offshore_core_broken": effective_offshore_core_broken,
		"offshore_core_cli_override": offshore_core,
		"shore_contour": shore_contour,
		"caustic_recovery_gain": caustic_recovery_gain,
		"caustic_recovery_scale": caustic_recovery_scale,
		"caustic_recovery_pattern_size": [recovery_pattern.get_width(),
			recovery_pattern.get_height()] if recovery_pattern != null else [],
	}
	if write_frame_timeline:
		var timeline_path := output_dir.path_join("%s_%s_timeline.json" % [run_id, case_id])
		var timeline_file := FileAccess.open(timeline_path, FileAccess.WRITE)
		if timeline_file == null:
			_fail("timeline open: " + timeline_path)
			return
		timeline_file.store_string(JSON.stringify({"run_id": run_id,
			"case": case_id, "samples": timeline}, "\t"))
		timeline_file.close()
		summary["timeline_artifact"] = timeline_path
	var path := output_dir.path_join("%s_%s_manifest.json" % [run_id, case_id])
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_fail("manifest open: " + path)
		return
	file.store_string(JSON.stringify(summary, "\t"))
	file.close()
	print("PASS: W08 staging movie case=%s tick=%d" % [case_id, preview.completed_ticks])
	quit(0)


func _fail(message: String) -> void:
	printerr("FAIL: W08 staging movie " + message)
	quit(1)

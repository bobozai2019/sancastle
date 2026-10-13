extends SceneTree

const WATER_SCENE := preload("res://tests/visual_water_alignment/prototypes/reference_fixed.tscn")
const COUPLED_SCENE := preload("res://tests/visual_water_alignment/prototypes/reference_coupled.tscn")
const STAGING_WATER_SCENE := preload("res://scenes/water_render_demo_v8_preview.tscn")
const STAGING_COUPLED_SCENE := preload("res://scenes/water_render_coupled_v8_preview.tscn")
const STAGING_WATER_CONTINUOUS_SCENE := preload("res://scenes/water_render_demo_v8_preview.tscn")
const STAGING_COUPLED_CONTINUOUS_SCENE := preload("res://scenes/water_render_coupled_v8_preview.tscn")
const CAMERA_IDS: Array[StringName] = [&"oblique", &"close", &"grazing"]

var case_id := "water"
var output_dir := ""
var run_id := ""
var warmup_s := 30
var stage_s := 60
var max_waves := 80
var soak_packets := 80
var wave_load := "continuous"
var display_variant := "combined"
var selected_camera := "all"
var render_profile_path := ""
var profile_requested := false
var profile_args_valid := true
var caustic_recovery_gain := 0.0
var caustic_recovery_scale := 1.0
var tick_timing := false
var main_frame_timing := false
var sync_boundary_readback := false
var worker_handoff := false
var crest_curtain := false
var crest_ribbon := false
var crest_rise_ribbon := false
var rise_crest := false
var depth_write := false
var front_field := false
var crest_face := false
var crest_height_override := -1.0
var ledger_ring_capacity := 0
var ledger_batch_ticks := 0
var batch_bookkeeping := false
var fixed_substeps := 0
var fixed_cfl_audit := false
var planar_reflection_mode := "off"
var planar_reflection_size := Vector2i(960, 540)
var preview: Node3D
var reflection_viewport: SubViewport
var reflection_camera: Camera3D
var wave_requests: Array[Dictionary] = []


func _init() -> void:
	var user_args := OS.get_cmdline_user_args()
	for arg in user_args:
		if arg.begins_with("--case="):
			case_id = arg.trim_prefix("--case=")
		elif arg.begins_with("--output="):
			output_dir = arg.trim_prefix("--output=")
		elif arg.begins_with("--run-id="):
			run_id = arg.trim_prefix("--run-id=")
		elif arg.begins_with("--warmup="):
			warmup_s = int(arg.trim_prefix("--warmup="))
		elif arg.begins_with("--seconds="):
			stage_s = int(arg.trim_prefix("--seconds="))
		elif arg.begins_with("--wave-load="):
			wave_load = arg.trim_prefix("--wave-load=")
		elif arg.begins_with("--soak-packets="):
			soak_packets = int(arg.trim_prefix("--soak-packets="))
		elif arg.begins_with("--display="):
			display_variant = arg.trim_prefix("--display=")
		elif arg.begins_with("--camera="):
			selected_camera = arg.trim_prefix("--camera=")
		elif arg.begins_with("--profile="):
			profile_requested = true
			render_profile_path = arg.trim_prefix("--profile=")
		elif arg.begins_with("--caustic-recovery-gain="):
			caustic_recovery_gain = float(arg.trim_prefix("--caustic-recovery-gain="))
		elif arg.begins_with("--caustic-recovery-scale="):
			caustic_recovery_scale = float(arg.trim_prefix("--caustic-recovery-scale="))
		elif arg == "--tick-timing":
			tick_timing = true
		elif arg == "--main-frame-timing":
			main_frame_timing = true
		elif arg == "--sync-boundary-readback":
			sync_boundary_readback = true
		elif arg == "--worker-handoff":
			worker_handoff = true
		elif arg == "--crest-curtain":
			crest_curtain = true
		elif arg == "--crest-ribbon":
			crest_ribbon = true
		elif arg == "--crest-rise-ribbon":
			crest_rise_ribbon = true
		elif arg == "--rise-crest":
			rise_crest = true
		elif arg == "--depth-write":
			depth_write = true
		elif arg == "--front-field":
			front_field = true
		elif arg == "--crest-face":
			crest_face = true
		elif arg.begins_with("--crest-height="):
			crest_height_override = float(arg.trim_prefix("--crest-height="))
		elif arg.begins_with("--ledger-ring-capacity="):
			ledger_ring_capacity = int(arg.trim_prefix("--ledger-ring-capacity="))
		elif arg.begins_with("--ledger-batch="):
			ledger_batch_ticks = int(arg.trim_prefix("--ledger-batch="))
		elif arg == "--batch-bookkeeping":
			batch_bookkeeping = true
		elif arg.begins_with("--fixed-substeps="):
			fixed_substeps = int(arg.trim_prefix("--fixed-substeps="))
		elif arg == "--fixed-cfl-audit":
			fixed_cfl_audit = true
		elif arg.begins_with("--planar-reflection="):
			planar_reflection_mode = arg.trim_prefix("--planar-reflection=")
		elif arg.begins_with("--planar-reflection-size="):
			var size_token := arg.trim_prefix("--planar-reflection-size=")
			if size_token == "half":
				planar_reflection_size = Vector2i(480, 270)
			elif size_token != "full":
				planar_reflection_size = Vector2i.ZERO
	if profile_requested:
		for arg in user_args:
			if not (arg.begins_with("--profile=") or arg.begins_with("--case=") or \
					arg.begins_with("--caustic-recovery-gain=") or \
					arg.begins_with("--caustic-recovery-scale=") or \
					arg.begins_with("--output=") or arg.begins_with("--run-id=") or \
					arg.begins_with("--warmup=") or arg.begins_with("--seconds=") or \
					arg.begins_with("--wave-load=") or arg.begins_with("--camera=") or \
					arg.begins_with("--soak-packets=") or arg == "--tick-timing"):
				profile_args_valid = false
	call_deferred("_run")


func _run() -> void:
	if not profile_args_valid or (profile_requested and render_profile_path.is_empty()) or \
			caustic_recovery_gain < 0.0 or caustic_recovery_gain > 1.0 or \
			caustic_recovery_scale < 1.0 or caustic_recovery_scale > 3.0 or \
			(caustic_recovery_gain == 0.0 and caustic_recovery_scale != 1.0) or \
			(caustic_recovery_gain > 0.0 and not profile_requested) or \
			case_id not in ["water", "coupled"] or output_dir.is_empty() or run_id.is_empty() or warmup_s < 0 or stage_s < 1 or \
			wave_load not in ["continuous", "none"] or display_variant not in ["combined", "phase2"] or \
			selected_camera not in ["all", "oblique", "close", "grazing"] or \
			soak_packets < 80 or soak_packets > 320 or \
			(soak_packets != 80 and (not profile_requested or wave_load != "continuous" or case_id != "coupled")) or \
			planar_reflection_mode not in ["off", "local", "baseline", "projected"] or \
			planar_reflection_size == Vector2i.ZERO or \
			(planar_reflection_size != Vector2i(960, 540) and planar_reflection_mode not in ["baseline", "projected"]) or \
			(planar_reflection_mode != "off" and (rise_crest or depth_write or
				crest_curtain or crest_ribbon or crest_rise_ribbon or front_field or
				crest_face or display_variant != "combined")) or \
			(main_frame_timing and not tick_timing) or \
			(worker_handoff and (tick_timing or sync_boundary_readback)) or \
			(crest_height_override >= 0.0 and crest_height_override > 0.25) or \
			((rise_crest or crest_rise_ribbon) and not depth_write) or \
			ledger_ring_capacity < 0 or ledger_ring_capacity > 4096 or \
			ledger_batch_ticks < 0 or ledger_batch_ticks > 1024 or \
			(batch_bookkeeping and ledger_batch_ticks < 1) or \
			(fixed_substeps > 0 and not batch_bookkeeping) or \
			(fixed_cfl_audit and fixed_substeps < 1) or \
			fixed_substeps < 0 or fixed_substeps > 64 or \
			(ledger_ring_capacity > 0 and ledger_batch_ticks > 0):
		_fail("invalid arguments")
		return
	if not DirAccess.dir_exists_absolute(output_dir):
		_fail("output directory missing")
		return
	if root.size != Vector2i(1920, 1080) or DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED:
		_fail("requires actual 1920x1080 VSync-off viewport; got %s, mode=%d" % [str(root.size), DisplayServer.window_get_vsync_mode()])
		return
	var profile_mode := not render_profile_path.is_empty()
	if profile_mode:
		var scene: PackedScene
		if wave_load == "continuous":
			scene = STAGING_WATER_CONTINUOUS_SCENE if case_id == "water" else \
				STAGING_COUPLED_CONTINUOUS_SCENE
		else:
			scene = STAGING_WATER_SCENE if case_id == "water" else STAGING_COUPLED_SCENE
		preview = scene.instantiate()
		preview.render_profile_path = render_profile_path
		preview.staging_wave_workload = "continuous_packets_v1" if wave_load == "continuous" else "none"
	else:
		preview = WATER_SCENE.instantiate() if case_id == "water" else COUPLED_SCENE.instantiate()
		preview.prototype_sync_boundary_readback = sync_boundary_readback
		preview.prototype_worker_handoff = worker_handoff
		preview.prototype_crest_curtain = crest_curtain
		preview.prototype_crest_ribbon = crest_ribbon
		preview.prototype_crest_rise_ribbon = crest_rise_ribbon
		preview.prototype_rise_crest = rise_crest
		preview.prototype_rise_front_field = front_field
		preview.prototype_ledger_ring_capacity = ledger_ring_capacity
		preview.prototype_ledger_batch_ticks = ledger_batch_ticks
		preview.prototype_batched_ledger_bookkeeping = batch_bookkeeping
		preview.prototype_fixed_substeps = fixed_substeps
		preview.prototype_fixed_cfl_audit = fixed_cfl_audit
		if planar_reflection_mode != "off":
			preview.prototype_local_front_field = true
			preview.prototype_coupled_caustics = case_id == "coupled"
			preview.prototype_fold_caustics = case_id == "coupled"
	root.add_child(preview)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	var init_us := Time.get_ticks_usec()
	while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_usec() - init_us < 30000000:
		await process_frame
	if not preview.ready_for_ticks or not preview.last_error.is_empty():
		_fail("initialization: " + preview.last_error)
		return
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
	preview.profile_tick_timing = tick_timing
	preview.profile_main_frame_timing = main_frame_timing
	if not profile_mode:
		preview.set_visual_time(-1.0)
	if not profile_mode and planar_reflection_mode != "off":
		preview.water_material.shader = load(
			"res://tests/visual_water_alignment/prototypes/reference_water_local_front.gdshader")
		preview.water_material.set_shader_parameter("local_front_state",
			preview.local_front_texture)
		preview.water_material.set_shader_parameter("prototype_use_local_front", true)
		preview.water_material.set_shader_parameter("prototype_eta_normals", true)
		preview.water_material.set_shader_parameter("prototype_crest_height_m", 0.25)
		preview.water_material.set_shader_parameter("prototype_screen_optics", true)
		preview.water_material.set_shader_parameter("prototype_screen_abs_fresnel", true)
		preview.water_material.set_shader_parameter("prototype_screen_face_normal", true)
		preview.water_material.set_shader_parameter("prototype_refraction_scale", 0.02)
		if planar_reflection_mode != "local":
			_setup_reflection_viewport()
			_update_reflection_camera(root.get_camera_3d())
	elif not profile_mode and rise_crest:
		preview.water_material.shader = load(
			"res://tests/visual_water_alignment/prototypes/reference_water_rise_crest.gdshader")
		preview.water_material.set_shader_parameter("foam_previous_state",
			preview.previous_foam_texture)
		preview.water_material.set_shader_parameter("prototype_rise_crest", true)
		if front_field:
			preview.water_material.set_shader_parameter("rise_front_state",
				preview.rise_front_texture)
			preview.water_material.set_shader_parameter("prototype_use_front_field", true)
	elif not profile_mode and depth_write:
		preview.water_material.shader = load(
			"res://tests/visual_water_alignment/prototypes/reference_water_depthwrite.gdshader")
	if not profile_mode and planar_reflection_mode == "off":
		preview.water_material.set_shader_parameter("prototype_eta_normals", display_variant == "combined")
	var crest_height := crest_height_override if crest_height_override >= 0.0 else \
		(0.16 if display_variant == "combined" else 0.0)
	if not profile_mode and planar_reflection_mode == "off":
		preview.water_material.set_shader_parameter("prototype_crest_height_m", crest_height)
	if not profile_mode and crest_rise_ribbon:
		var ribbon_material := (preview.get_node("PrototypeCrestRibbon") as MeshInstance3D).material_override as ShaderMaterial
		ribbon_material.set_shader_parameter("crest_height_m", crest_height)
	if not profile_mode:
		preview.water_material.set_shader_parameter("prototype_crest_white_face", crest_face)
		preview.water_material.set_shader_parameter("prototype_irregular_foam",
			planar_reflection_mode == "off" and display_variant == "combined")
	if not profile_mode and planar_reflection_mode == "off":
		preview.water_material.set_shader_parameter("prototype_screen_optics", false)
	# This candidate uses the current phase-2 transmission/reflection and foam path.
	# The optional screen-optics branch is separate and excludes that foam path.
	if profile_mode:
		for request in preview.wave_requests:
			wave_requests.append(request.duplicate(true))
		if soak_packets > 80:
			if wave_requests.size() != 80:
				_fail("long soak requires canonical 80-packet workload")
				return
			for index in range(80, soak_packets):
				var request := {"domain_id": preview.shadow_domain.domain_id,
					"generation": preview.generation, "request_id": index + 1,
					"start_tick": 8 + index * 180,
					"profile_id": &"test_packet", "amplitude_m": 0.18,
					"duration_s": 6.0, "seed": 31 + index * 17}
				var admitted: Dictionary = preview.request_wave(request)
				if not admitted.ok:
					_fail("long soak wave %d rejected: %s" % [index + 1, String(admitted.code)])
					return
				wave_requests.append(request)
	else:
		for request_id in range(1, max_waves + 1 if wave_load == "continuous" else 1):
			var request := {"domain_id": preview.shadow_domain.domain_id,
				"generation": preview.generation, "request_id": request_id,
				"start_tick": preview.completed_ticks + 8 + (request_id - 1) * 180,
				"profile_id": &"test_packet", "amplitude_m": 0.18,
				"duration_s": 6.0, "seed": 31 + request_id * 17}
			var admitted: Dictionary = preview.request_wave(request)
			if not admitted.ok:
				_fail("wave %d rejected: %s" % [request_id, String(admitted.code)])
				return
			wave_requests.append(request)
	# A multi-camera run must not measure its later cameras after the finite
	# staging packet schedule has ended. This rejects impossible activity
	# coverage before spending minutes collecting an idle stage.
	if profile_mode and wave_load == "continuous":
		var last_source_tick := 0
		for request in wave_requests:
			last_source_tick = maxi(last_source_tick, int(request.start_tick) + 180)
		var stage_count := CAMERA_IDS.size() if selected_camera == "all" else 1
		for stage_index in stage_count:
			var planned_start_tick: int = preview.completed_ticks + \
				(warmup_s + stage_index * stage_s) * 30
			var required_active_ticks: int = ceili(float(stage_s * 30) * 0.25)
			if last_source_tick < planned_start_tick + required_active_ticks:
				_fail("wave workload expires before stage %d can reach 25%% source activity" % stage_index)
				return
	var warm_start := Time.get_ticks_usec()
	while Time.get_ticks_usec() - warm_start < warmup_s * 1000000:
		await process_frame
		if not _healthy():
			return
	print("COST_WARMUP case=%s seconds=%d tick=%d" % [case_id, warmup_s, preview.completed_ticks])
	var csv_path := output_dir.path_join("%s_%s_frames.csv" % [run_id, case_id])
	var csv := FileAccess.open(csv_path, FileAccess.WRITE)
	if csv == null:
		_fail("CSV open")
		return
	csv.store_csv_line(["camera", "frame", "wall_ms", "process_ms", "render_cpu_ms", "render_gpu_ms", "tick", "substeps", "source_active", "static_bytes", "video_bytes"])
	var stages: Array[Dictionary] = []
	var camera_ids: Array[StringName] = CAMERA_IDS.duplicate()
	if selected_camera != "all":
		camera_ids.clear()
		camera_ids.append(StringName(selected_camera))
	for camera_id in camera_ids:
		if not preview.set_fixture_camera(camera_id):
			csv.close()
			_fail("camera " + String(camera_id))
			return
		if planar_reflection_mode in ["baseline", "projected"]:
			_update_reflection_camera(root.get_camera_3d())
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var camera := root.get_camera_3d()
		if camera == null:
			csv.close()
			_fail("active camera missing")
			return
		var start_us := Time.get_ticks_usec()
		var before_us := start_us
		var tick_start: int = preview.completed_ticks
		var frames := 0
		var active_frames := 0
		var wall_values := PackedFloat32Array()
		var gpu_values := PackedFloat32Array()
		var csv_lines: Array[PackedStringArray] = []
		var static_min := 9223372036854775807
		var static_max := 0
		var video_min := 9223372036854775807
		var video_max := 0
		while Time.get_ticks_usec() - start_us < stage_s * 1000000:
			await process_frame
			if not _healthy():
				csv.close()
				return
			var now_us := Time.get_ticks_usec()
			var wall_ms := float(now_us - before_us) / 1000.0
			var gpu_ms := RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid())
			var static_bytes := int(Performance.get_monitor(Performance.MEMORY_STATIC))
			var video_bytes := int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED))
			var active := _source_active(preview.completed_ticks)
			active_frames += int(active)
			static_min = mini(static_min, static_bytes)
			static_max = maxi(static_max, static_bytes)
			video_min = mini(video_min, video_bytes)
			video_max = maxi(video_max, video_bytes)
			wall_values.append(wall_ms)
			gpu_values.append(gpu_ms)
			csv_lines.append(PackedStringArray([String(camera_id), str(frames), "%.6f" % wall_ms,
				"%.6f" % (float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0),
				"%.6f" % RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()),
				"%.6f" % gpu_ms, str(preview.completed_ticks), str(preview.last_substeps),
				str(int(active)), str(static_bytes), str(video_bytes)]))
			if csv_lines.size() >= 1024:
				for row in csv_lines:
					csv.store_csv_line(row)
				csv_lines.clear()
			frames += 1
			before_us = now_us
		var elapsed_s := float(Time.get_ticks_usec() - start_us) / 1000000.0
		for row in csv_lines:
			csv.store_csv_line(row)
		var tick_end: int = preview.completed_ticks
		wall_values.sort()
		gpu_values.sort()
		var stage := {"camera": String(camera_id), "camera_transform": str(camera.global_transform),
			"fov_deg": camera.fov, "seconds": elapsed_s, "frames": frames,
			"tick_start": tick_start, "tick_end": tick_end,
			"tick_rate": float(tick_end - tick_start) / elapsed_s,
			"source_active_frames": active_frames,
			"source_active_fraction": float(active_frames) / float(frames),
			"wall_p50_ms": _percentile(wall_values, 0.50),
			"wall_p95_ms": _percentile(wall_values, 0.95),
			"wall_p99_ms": _percentile(wall_values, 0.99),
			"render_gpu_p99_ms": _percentile(gpu_values, 0.99),
			"static_memory_range_bytes": static_max - static_min,
			"video_memory_range_bytes": video_max - video_min}
		stage["meets_cost_bound"] = frames >= 600 and elapsed_s >= 60.0 and \
			float(stage.wall_p99_ms) <= 33.3 and float(stage.tick_rate) >= 30.0 and \
			float(stage.source_active_fraction) >= 0.25
		stages.append(stage)
		print("COST_STAGE " + JSON.stringify(stage))
	csv.close()
	preview.playing = false
	while preview.tick_pending:
		await process_frame
	var tick_timing_path := ""
	var main_frame_timing_path := ""
	var tick_timing_summary := {}
	if tick_timing:
		tick_timing_path = output_dir.path_join("%s_%s_tick_timing.csv" % [run_id, case_id])
		var tick_csv := FileAccess.open(tick_timing_path, FileAccess.WRITE)
		if tick_csv == null:
			_fail("tick timing CSV open")
			return
		tick_csv.store_csv_line(["tick", "stage", "start_us", "ledger_us", "cfl_us",
			"both_us", "finished_us", "substeps", "render_begin_us",
			"render_submit_us", "ledger_render_us", "cfl_render_us",
			"render_finish_us", "render_finish_submit_us",
			"boundary_ms", "finish_ms", "total_ms"])
		var boundary_values := PackedFloat32Array()
		var finish_values := PackedFloat32Array()
		var total_values := PackedFloat32Array()
		for row in preview.profile_tick_rows:
			var stage_name := "warmup"
			for stage in stages:
				if row[0] > int(stage.tick_start) and row[0] <= int(stage.tick_end):
					stage_name = String(stage.camera)
					break
			var boundary_ms := float(row[4] - row[1]) / 1000.0
			var finish_ms := float(row[5] - row[4]) / 1000.0
			var total_ms := float(row[5] - row[1]) / 1000.0
			if stage_name != "warmup":
				boundary_values.append(boundary_ms)
				finish_values.append(finish_ms)
				total_values.append(total_ms)
			tick_csv.store_csv_line([str(row[0]), stage_name, str(row[1]),
				str(row[2]), str(row[3]), str(row[4]), str(row[5]),
				str(row[6]), str(row[7]), str(row[8]), str(row[9]),
				str(row[10]), str(row[11]), str(row[12]),
				"%.6f" % boundary_ms, "%.6f" % finish_ms,
				"%.6f" % total_ms])
		tick_csv.close()
		boundary_values.sort()
		finish_values.sort()
		total_values.sort()
		tick_timing_summary = {"stage_ticks": total_values.size(),
			"boundary_p50_ms": _percentile(boundary_values, 0.50),
			"boundary_p95_ms": _percentile(boundary_values, 0.95),
			"boundary_p99_ms": _percentile(boundary_values, 0.99),
			"finish_p50_ms": _percentile(finish_values, 0.50),
			"finish_p95_ms": _percentile(finish_values, 0.95),
			"finish_p99_ms": _percentile(finish_values, 0.99),
			"total_p50_ms": _percentile(total_values, 0.50),
			"total_p95_ms": _percentile(total_values, 0.95),
			"total_p99_ms": _percentile(total_values, 0.99)}
	if main_frame_timing:
		main_frame_timing_path = output_dir.path_join("%s_%s_main_frames.csv" % [run_id, case_id])
		var frame_timing_csv := FileAccess.open(main_frame_timing_path, FileAccess.WRITE)
		if frame_timing_csv == null:
			_fail("main frame timing CSV open")
			return
		frame_timing_csv.store_csv_line(["process_frame", "process_enter_us", "completed_tick", "tick_pending"])
		for row in preview.profile_main_frame_rows:
			frame_timing_csv.store_csv_line([str(row[0]), str(row[1]), str(row[2]), str(row[3])])
		frame_timing_csv.close()
	var summary := {"role": "w07_planar_reflection_cost_probe" if planar_reflection_mode != "off" else ("w07_combined_candidate_cost_probe" if display_variant == "combined" and wave_load == "continuous" else "w07_cost_ablation_probe"), "run_id": run_id,
		"case": case_id, "fixture_id": String(preview.fixture_id),
		"wave_load": wave_load, "display_variant": display_variant,
		"selected_camera": selected_camera,
		"soak_packets": soak_packets,
		"caustic_recovery_gain": caustic_recovery_gain,
		"caustic_recovery_scale": caustic_recovery_scale,
		"caustic_recovery_pattern_size": [recovery_pattern.get_width(),
			recovery_pattern.get_height()] if recovery_pattern != null else [],
		"planar_reflection_mode": planar_reflection_mode,
		"reflection_viewport_px": [planar_reflection_size.x, planar_reflection_size.y] if planar_reflection_mode in ["baseline", "projected"] else [],
		"effective_water_shader": preview.water_material.shader.resource_path,
		"candidate": {"phase2_optics": true, "phase2_foam": true,
			"prototype_eta_normals": display_variant == "combined",
			"prototype_crest_height_m": 0.25 if planar_reflection_mode != "off" else crest_height,
			"prototype_crest_white_face": crest_face,
			"prototype_crest_curtain": crest_curtain,
			"prototype_crest_ribbon": crest_ribbon,
			"prototype_crest_rise_ribbon": crest_rise_ribbon,
			"prototype_rise_crest": rise_crest,
			"prototype_depth_write": depth_write,
			"prototype_rise_front_field": front_field,
			"prototype_ledger_ring_capacity": ledger_ring_capacity,
			"prototype_ledger_batch_ticks": ledger_batch_ticks,
			"prototype_batched_ledger_bookkeeping": batch_bookkeeping,
			"prototype_fixed_substeps": fixed_substeps,
			"prototype_fixed_cfl_audit": fixed_cfl_audit,
			"prototype_irregular_foam": planar_reflection_mode == "off" and display_variant == "combined",
			"prototype_screen_optics": planar_reflection_mode != "off",
			"prototype_planar_reflection_water": planar_reflection_mode == "projected",
			"prototype_local_front_profile": planar_reflection_mode != "off",
			"prototype_coupled_caustics": planar_reflection_mode != "off" and case_id == "coupled",
			"prototype_sync_boundary_readback": sync_boundary_readback,
			"prototype_worker_handoff": worker_handoff},
		"warmup_seconds": warmup_s, "stage_target_seconds": stage_s,
		"viewport_px": [root.size.x, root.size.y],
		"vsync_mode": DisplayServer.window_get_vsync_mode(),
		"frame_queue_size_setting": ProjectSettings.get_setting(
			"rendering/rendering_device/vsync/frame_queue_size"),
		"engine_max_fps": Engine.max_fps,
		"adapter": RenderingServer.get_video_adapter_name(),
		"rendering_driver": RenderingServer.get_current_rendering_driver_name(), "sim_hz": 30,
		"wave_requests": wave_requests, "stages": stages,
		"csv": csv_path, "tick_end": preview.completed_ticks,
		"tick_timing_csv": tick_timing_path,
		"main_frame_timing_csv": main_frame_timing_path,
		"tick_timing_summary": tick_timing_summary,
		"sand_only_syncs": preview.sand_only_syncs,
		"sand_prefetch_hits": preview.sand_prefetch_hits,
		"dirty_summaries_checked": preview.dirty_summaries_checked,
		"dirty_summaries_missed": preview.dirty_summaries_missed,
		"max_substeps": preview.solver.max_substeps_used,
		"fixed_cfl_audit_count": preview.fixed_cfl_audit_count,
		"fixed_cfl_max_required": preview.fixed_cfl_max_required,
		"fixed_cfl_over_bound": preview.fixed_cfl_over_bound,
		"overload_events": preview.solver.overload_events,
		"nan_events": preview.solver.nan_events,
		"wave_clamp_events": preview.wave_clamp_events,
		"invalid_water_cells": preview.audit_invalid_cells,
		"negative_water_cells": preview.audit_negative_cells,
		"invalid_sand_cells": preview.audit_sand_invalid_cells,
		"negative_sand_cells": preview.audit_sand_negative_cells,
		"sand_closure_m3": preview.audit_sand_closure_m3,
		"cost_bound_met_all_stages": stages.all(func(s: Dictionary) -> bool: return s.meets_cost_bound)}
	if profile_mode:
		summary.role = "w08_staging_profile_cost_probe"
		summary["wave_workload_id"] = preview.staging_wave_workload
		summary.erase("candidate")
		summary.erase("display_variant")
		summary.erase("planar_reflection_mode")
		summary.erase("reflection_viewport_px")
		summary["requested_profile_path"] = render_profile_path
		summary["requested_profile_sha256"] = preview.requested_render_profile_sha256
		summary["effective_profile"] = preview.effective_render_profile
		summary["effective_profile_sha256"] = preview.effective_render_profile_sha256
		summary["visual_time_s"] = preview.visual_time_s
		summary["profile_time_matches_tick"] = is_equal_approx(
			preview.visual_time_s, float(preview.completed_ticks) / 30.0)
		if not summary.profile_time_matches_tick:
			_fail("profile visual time differs from completed tick")
			return
	var manifest_path := output_dir.path_join("%s_%s_manifest.json" % [run_id, case_id])
	var file := FileAccess.open(manifest_path, FileAccess.WRITE)
	if file == null:
		_fail("manifest open")
		return
	file.store_string(JSON.stringify(summary, "\t"))
	file.close()
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), false)
	print("PASS: %s cost probe collected %s %d stages" % ["W08 profile" if profile_mode else "W07", case_id, stages.size()])
	quit(0)


func _setup_reflection_viewport() -> void:
	reflection_viewport = SubViewport.new()
	reflection_viewport.size = planar_reflection_size
	reflection_viewport.world_3d = root.world_3d
	reflection_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(reflection_viewport)
	reflection_camera = Camera3D.new()
	reflection_camera.cull_mask = 4
	reflection_viewport.add_child(reflection_camera)
	reflection_camera.make_current()
	(preview.get_node("GpuWaterSurface") as MeshInstance3D).layers = 2
	preview.overview_camera.set_cull_mask_value(3, false)
	preview.player_camera.set_cull_mask_value(3, false)
	var reflection_bed := MeshInstance3D.new()
	reflection_bed.name = "ReflectionAboveWaterBed"
	reflection_bed.mesh = (preview.get_node("GpuSandTerrain") as MeshInstance3D).mesh
	reflection_bed.layers = 4
	var reflection_bed_material := preview.terrain_material.duplicate() as ShaderMaterial
	var reflection_bed_shader := Shader.new()
	reflection_bed_shader.code = (preview.terrain_material.shader as Shader).code.replace(
		"void fragment() {",
		"void fragment() {\n    if ((INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).y < 0.0) { discard; }")
	reflection_bed_material.shader = reflection_bed_shader
	reflection_bed.material_override = reflection_bed_material
	preview.add_child(reflection_bed)
	if planar_reflection_mode == "projected":
		preview.water_material.set_shader_parameter(
			"prototype_planar_reflection_enabled", true)
		preview.water_material.set_shader_parameter(
			"prototype_planar_reflection_projected", true)
		preview.water_material.set_shader_parameter(
			"prototype_planar_reflection", reflection_viewport.get_texture())


func _update_reflection_camera(source_camera: Camera3D) -> void:
	if source_camera == null:
		return
	reflection_camera.fov = source_camera.fov
	reflection_camera.near = source_camera.near
	reflection_camera.far = source_camera.far
	var source_basis := source_camera.global_transform.basis
	var reflected_position := source_camera.global_position
	reflected_position.y = -reflected_position.y
	var reflected_forward := -source_basis.z
	reflected_forward.y = -reflected_forward.y
	var reflected_up := source_basis.y
	reflected_up.y = -reflected_up.y
	reflection_camera.global_position = reflected_position
	reflection_camera.look_at(reflected_position + reflected_forward, reflected_up)
	if planar_reflection_mode == "projected":
		var reflected_view_projection := reflection_camera.get_camera_projection() * \
			Projection(reflection_camera.global_transform.affine_inverse())
		preview.water_material.set_shader_parameter(
			"prototype_planar_view_projection", reflected_view_projection)


func _source_active(tick: int) -> bool:
	for request in wave_requests:
		if tick >= int(request.start_tick) and tick < int(request.start_tick) + 180:
			return true
	return false


func _percentile(values: PackedFloat32Array, quantile: float) -> float:
	return values[int((values.size() - 1) * quantile)] if not values.is_empty() else INF


func _healthy() -> bool:
	if not preview.last_error.is_empty() or preview.solver.nan_events > 0 or \
			preview.solver.overload_events > 0 or preview.audit_invalid_cells > 0 or \
			preview.audit_negative_cells > 0 or preview.audit_sand_invalid_cells > 0 or \
			preview.audit_sand_negative_cells > 0:
		_fail("runtime: " + preview.last_error)
		return false
	return true


func _fail(message: String) -> void:
	printerr("FAIL: W07 cost probe " + message)
	quit(1)


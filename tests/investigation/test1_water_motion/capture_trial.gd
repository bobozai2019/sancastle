extends SceneTree

var scene: Test1WaterMotionTrial
var output := "D:/godot/project/sandcastle/test_output/test1_water_motion/gpu_release_v1"
var mode := "release"
var end_tick := 800
var target_tick := 0
var saved_path := ""
var pause_on_ready := false
var manifest := {"operation_complete": false, "samples": [], "errors": []}
const SOURCES := ["res://scenes/test1_water_motion_trial.tscn", "res://scripts/visual/test1_water_motion_trial.gd", "res://shaders/simulation/test1_water_motion.glsl", "res://assets/test1_water_motion/bed.gdshader", "res://assets/test1_water_motion/water.gdshader", "res://assets/test1_water_motion/capture_profile.json", "res://assets/test1_water_motion/capture_state.rgba32f", "res://assets/test1_water_motion/capture_aux.rgba32f", "res://assets/test1_water_motion/grid.res", "res://assets/water_material_natural_candidate/water_normal_681.png", "res://tests/investigation/test1_water_motion/capture_trial.gd"]
const MAIN_SOURCES := ["res://scripts/visual/test1_main_presentation.gd", "res://shaders/simulation/test1_main_display.glsl", "res://assets/test1_water_motion/main_water.tres", "res://assets/test1_water_motion/main_sand.tres", "res://assets/test1_water_motion/main_fine.tres", "res://assets/test1_water_motion/main_contact.tres", "res://assets/test1_water_motion/main_grid.res", "res://assets/test1_water_motion/main_fine_mesh.res", "res://assets/test1_water_motion/main_environment.res", "res://assets/test1_water_motion/main_presentation.json", "res://assets/water_material_natural_candidate/rdc_water.gdshader", "res://assets/water_material_natural_candidate/rdc_bed.gdshader", "res://assets/water_material_natural_candidate/foam_distribution.gdshader", "res://assets/water_material_natural_candidate/contact_shape.gdshader", "res://assets/water_material_natural_candidate/rdc_caustic_1105_mipped.res", "res://scripts/visual/gpu_foam_field.gd", "res://tests/visual_water_alignment/prototypes/reference_local_front_field.gd", "res://shaders/simulation/visual_foam_step.glsl", "res://tests/visual_water_alignment/prototypes/reference_local_front_x.glsl", "res://tests/visual_water_alignment/prototypes/reference_local_front_z.glsl"]

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			output = argument.trim_prefix("--output=")
		elif argument.begins_with("--mode="):
			mode = argument.trim_prefix("--mode=")
		elif argument.begins_with("--end-tick="):
			end_tick = int(argument.trim_prefix("--end-tick="))
	DirAccess.make_dir_recursive_absolute(output)
	call_deferred("_run")

func _run() -> void:
	manifest["source_index"] = []
	for path in SOURCES + MAIN_SOURCES + ["res://assets/test1_water_motion/main_capture_grid.res", "res://tests/visual_water_alignment/prototypes/caustic_fold_v1.png", "res://tests/investigation/test1_water_motion/bake_main_presentation.gd", "res://tests/investigation/test1_water_motion/bake_display_mesh.gd"]:
		var snapshot := output.path_join("source_snapshot").path_join(path.trim_prefix("res://") + ".source")
		DirAccess.make_dir_recursive_absolute(snapshot.get_base_dir())
		var file := FileAccess.open(snapshot, FileAccess.WRITE)
		file.store_buffer(FileAccess.get_file_as_bytes(path))
		manifest.source_index.append({"path": path, "snapshot": snapshot, "sha256": FileAccess.get_sha256(path)})
	scene = load("res://scenes/test1_water_motion_trial.tscn").instantiate()
	scene.motion_mode = mode
	scene.paused = true
	scene.snapshot_saved.connect(func(path: String) -> void: saved_path = path)
	scene.tick_completed.connect(_tick_finished)
	scene.trial_ready.connect(func() -> void:
		if pause_on_ready:
			scene.paused = true)
	root.add_child(scene)
	var deadline := Time.get_ticks_msec() + 60000
	while not scene.ready_for_ticks and scene.last_error.is_empty() and Time.get_ticks_msec() < deadline:
		await process_frame
	if not scene.ready_for_ticks or not scene.last_error.is_empty():
		_finish("initialization: " + scene.last_error)
		return
	manifest["profile_sha256"] = FileAccess.get_sha256("res://assets/test1_water_motion/capture_profile.json")
	manifest["mode"] = mode
	manifest["engine"] = Engine.get_version_info()
	manifest["adapter"] = RenderingServer.get_video_adapter_name()
	manifest["source_sha256"] = "761aa980c2426f75a1fa7364bf6d2655ff4dd20ea76566e630ee5b53ea0ec5b2"
	manifest["temporal_scope"] = "captured initial state; fixed sand; experimental future input; time is tick/40"
	manifest["main_materials"] = _material_identity()
	while scene.completed_ticks <= end_tick:
		if not scene.last_error.is_empty():
			_finish(scene.last_error)
			return
		var tick := scene.completed_ticks
		var path := output.path_join("state_%04d.rgba32f" % tick)
		saved_path = ""
		if not scene.request_snapshot(path):
			_finish("snapshot rejected")
			return
		deadline = Time.get_ticks_msec() + 30000
		while saved_path != path and Time.get_ticks_msec() < deadline:
			await process_frame
		if saved_path != path:
			_finish("snapshot timed out")
			return
		var row := {"tick": tick, "adaptation_time": float(tick) / 40.0, "override": scene.level_override(tick), "raw_path": path, "sha256": FileAccess.get_sha256(path)}
		if tick in [0, 80, 240, 400, 560, 800] or tick == end_tick:
			var render_done := [false]
			RenderingServer.call_on_render_thread(func() -> void:
				for name in scene.presentation.published():
					var bytes: PackedByteArray = scene.rd.texture_get_data(scene.presentation.published()[name], 0)
					var field := FileAccess.open(output.path_join("render_%04d_%s.f32" % [tick, name]), FileAccess.WRITE)
					field.store_buffer(bytes)
				render_done[0] = true)
			while not render_done[0]:
				await process_frame
			for frame in 3:
				await RenderingServer.frame_post_draw
			row["picture"] = output.path_join("frame_%04d.png" % tick)
			root.get_texture().get_image().save_png(row.picture)
			scene._on_flow_toggled(true)
			for frame in 3:
				await RenderingServer.frame_post_draw
			row["flow_picture"] = output.path_join("flow_%04d.png" % tick)
			root.get_texture().get_image().save_png(row.flow_picture)
			scene._on_flow_toggled(false)
			if tick == 240:
				row["visual_negatives"] = []
				for pair in [[scene.water_material, "rdc_normal_enabled"], [scene.bed_material, "rdc_caustics_enabled"]]:
					var material: ShaderMaterial = pair[0]
					var key: String = pair[1]
					var original: Variant = material.get_shader_parameter(key)
					material.set_shader_parameter(key, false)
					for frame in 3:
						await RenderingServer.frame_post_draw
					var picture := output.path_join("negative_%s.png" % key)
					root.get_texture().get_image().save_png(picture)
					material.set_shader_parameter(key, original)
					row.visual_negatives.append({"only_changed_uniform": key, "picture": picture})
				var negative_path := output.path_join("visual_negatives_state.rgba32f")
				saved_path = ""
				scene.request_snapshot(negative_path)
				while saved_path != negative_path:
					await process_frame
				row["visual_negatives_preserve_state"] = FileAccess.get_sha256(negative_path) == row.sha256
		manifest.samples.append(row)
		var file := FileAccess.open(output.path_join("progress.json"), FileAccess.WRITE)
		file.store_string(JSON.stringify(manifest, "\t"))
		print("motion sample ", tick)
		if tick >= end_tick:
			break
		target_tick = mini(tick + 40, end_tick)
		scene.paused = false
		deadline = Time.get_ticks_msec() + 60000
		while scene.completed_ticks < target_tick and scene.last_error.is_empty() and Time.get_ticks_msec() < deadline:
			await process_frame
		if scene.completed_ticks != target_tick:
			_finish("tick advance failed: " + scene.last_error)
			return
	await _check_controls()
	_finish("")

func _check_controls() -> void:
	manifest["controls"] = {}
	var before_tick := scene.completed_ticks
	var before_clock: float = scene.water_material.get_shader_parameter("visual_time_s")
	var path := output.path_join("paused_after.rgba32f")
	for frame in 20:
		await process_frame
	saved_path = ""
	scene.request_snapshot(path)
	while saved_path != path:
		await process_frame
	var last: Dictionary = manifest.samples.back()
	manifest.controls["paused_state_identical"] = FileAccess.get_sha256(path) == last.sha256
	manifest.controls["paused_tick_clock_identical"] = scene.completed_ticks == before_tick and scene.water_material.get_shader_parameter("visual_time_s") == before_clock
	manifest.controls["water_sand_clocks_identical"] = scene.bed_material.get_shader_parameter("visual_time_s") == before_clock
	manifest.controls["complete_generation"] = scene.presentation.generation == before_tick
	scene.get_node("Interface/Panel/Margin/Controls/Buttons/Flow").button_pressed = true
	path = output.path_join("flow_toggle.rgba32f")
	saved_path = ""
	scene.request_snapshot(path)
	while saved_path != path:
		await process_frame
	manifest.controls["flow_display_preserves_state"] = FileAccess.get_sha256(path) == last.sha256
	manifest.controls["flow_toggle_consumed"] = scene.flow_enabled and scene.get_node("FlowOverlay").visible and not scene.get_node("Water").visible
	scene.get_node("Interface/Panel/Margin/Controls/Buttons/Flow").button_pressed = false
	for button in ["Release", "Hold", "Repeat", "Reset"]:
		pause_on_ready = true
		scene.get_node("Interface/Panel/Margin/Controls/Buttons/" + button).pressed.emit()
		while not scene.ready_for_ticks:
			await process_frame
		path = output.path_join("reset_" + button + ".rgba32f")
		saved_path = ""
		scene.request_snapshot(path)
		while saved_path != path:
			await process_frame
		manifest.controls["reset_" + button] = scene.completed_ticks == 0 and FileAccess.get_sha256(path) == FileAccess.get_sha256(scene.STATE_PATH) and is_equal_approx(float(scene.water_material.get_shader_parameter("visual_time_s")), 0.0)
	pause_on_ready = false
	target_tick = 40
	scene.get_node("Interface/Panel/Margin/Controls/Buttons/Pause").pressed.emit()
	while scene.completed_ticks < target_tick:
		await process_frame
	manifest.controls["pause_button_resumes_ticks"] = scene.completed_ticks == 40
	for value in manifest.controls.values():
		if not value:
			manifest.errors.append("control check failed")

func _tick_finished(tick: int) -> void:
	if tick >= target_tick:
		scene.paused = true
		scene._update_status()

func _finish(error: String) -> void:
	if not error.is_empty():
		manifest.errors.append(error)
	manifest["sources_unchanged"] = true
	for row in manifest.get("source_index", []):
		if FileAccess.get_sha256(row.path) != row.sha256:
			manifest.sources_unchanged = false
	manifest.operation_complete = manifest.errors.is_empty() and manifest.sources_unchanged
	var file := FileAccess.open(output.path_join("manifest.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "\t"))
	if is_instance_valid(scene):
		scene.queue_free()
		await process_frame
		await process_frame
	quit(0 if error.is_empty() else 1)

func _material_identity() -> Dictionary:
	var baked: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/test1_water_motion/main_presentation.json"))
	var result := {"shader_identity": true, "parameters_identical": true, "runtime_fields": {}}
	var materials := {"water": scene.water_material, "sand": scene.bed_material, "fine": scene.fine_material, "contact": scene.contact_material}
	for row in baked.materials:
		var material: ShaderMaterial = materials[row.material]
		result.shader_identity = result.shader_identity and material.shader.resource_path == row.shader and FileAccess.get_sha256(row.shader) == row.shader_sha256
		for key in row.parameters:
			if key in ["visual_time_s", "prototype_planar_view_projection", "viewport_height_px"]:
				continue
			var value: Variant = material.get_shader_parameter(key)
			var recorded: Variant = str_to_var(row.parameters[key]) if not String(row.parameters[key]).begins_with("res://") else load(row.parameters[key])
			if value != recorded:
				# Text serialization rounds Vector components; compare numeric vectors approximately.
				var same: bool = value.is_equal_approx(recorded) if value is Vector2 or value is Vector3 or value is Vector4 else false
				if not same:
					result.parameters_identical = false
					result[key] = [var_to_str(value), row.parameters[key]]
		for key in row.runtime_bindings_to_replace:
			result.runtime_fields[row.material + "/" + key] = material.get_shader_parameter(key) != null
	return result

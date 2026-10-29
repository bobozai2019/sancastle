extends SceneTree

## Compare effective inputs, not just inherited resource names. Diagnostic
## overrides are restored without advancing or writing the simulation.
const PATHS := ["res://scenes/main.tscn", "res://scenes/playable/test1_capture.tscn", "res://scenes/playable/test1_backwash.tscn"]
const FIELDS := ["water", "rock", "sand", "momentum_x", "momentum_z"]
var scene
var output := "D:/godot/project/sandcastle/test_output/water_material_consistency_20261013_v2"
var result := {"scenes": [], "checks": []}
var readbacks := {}

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	call_deferred("_run")

func _check(name: String, ok: bool) -> void:
	result.checks.append({"name": name, "pass": ok})
	print("MATERIAL_CHECK ", name, " ", ok)

func _read() -> void:
	for field in FIELDS:
		scene.solver.request_data(field, func(bytes: PackedByteArray) -> void: call_deferred("_receive", field, bytes))

func _receive(key: String, bytes: PackedByteArray) -> void:
	readbacks[key] = bytes

func _snapshot() -> Dictionary:
	readbacks.clear()
	RenderingServer.call_on_render_thread(_read)
	var deadline := Time.get_ticks_msec() + 30000
	while readbacks.size() < FIELDS.size() and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(scene.scene_key + "_readback", readbacks.size() == FIELDS.size())
	return readbacks.duplicate()

func _material(material: ShaderMaterial) -> Dictionary:
	var row := {"shader": material.shader.resource_path, "shader_sha256": FileAccess.get_sha256(material.shader.resource_path), "parameters": {}, "runtime": {}}
	for uniform in material.shader.get_shader_uniform_list():
		var key: String = uniform.name
		var value: Variant = material.get_shader_parameter(key)
		if value == null:
			value = RenderingServer.shader_get_parameter_default(material.shader.get_rid(), key)
		if value is Texture2DRD or value is ViewportTexture:
			row.runtime[key] = {"class": value.get_class(), "width": value.get_width(), "height": value.get_height()}
		elif key == "prototype_planar_view_projection":
			# Computed from the active camera, not a preset material parameter.
			row.runtime[key] = var_to_str(value)
		elif value is Texture:
			row.parameters[key] = {"resource": value.resource_path, "sha256": FileAccess.get_sha256(value.resource_path)}
		else:
			row.parameters[key] = var_to_str(value)
	return row

func _metrics(fields: Dictionary) -> Dictionary:
	var a := {}
	for key in FIELDS:
		a[key] = fields[key].to_float32_array()
	var wet := PackedFloat32Array()
	var speeds := PackedFloat32Array()
	var gradients := PackedFloat32Array()
	var total := 0.0
	for i in 256 * 256:
		var h: float = a.water[i]
		total += h * 0.015625
		if h <= 0.001:
			continue
		wet.append(h)
		speeds.append(Vector2(a.momentum_x[i], a.momentum_z[i]).length() / h)
		if i % 256 < 255 and i < 255 * 256 and a.water[i + 1] > 0.001 and a.water[i + 256] > 0.001:
			var eta: float = a.rock[i] + a.sand[i] + h
			gradients.append(Vector2(a.rock[i + 1] + a.sand[i + 1] + a.water[i + 1] - eta, a.rock[i + 256] + a.sand[i + 256] + a.water[i + 256] - eta).length() / 0.125)
	wet.sort()
	speeds.sort()
	gradients.sort()
	return {"water_m3": total, "wet_cells": wet.size(), "depth": _distribution(wet), "speed": _distribution(speeds), "eta_gradient": _distribution(gradients)}

func _distribution(a: PackedFloat32Array) -> Dictionary:
	if a.is_empty():
		return {}
	var mean := 0.0
	for value in a:
		mean += value
	return {"mean": mean / a.size(), "p50": a[int((a.size() - 1) * 0.5)], "p90": a[int((a.size() - 1) * 0.9)], "p99": a[int((a.size() - 1) * 0.99)], "max": a[-1]}

func _capture(suffix: String) -> void:
	# Allow camera-dependent planar reflection to update before sampling.
	for frame in 5:
		await process_frame
		await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(scene.scene_key + "_" + suffix + ".png"))

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var reference := {}
	var common_transform := Transform3D.IDENTITY
	var common_fov := 0.0
	var capture_fields := {}
	for path in PATHS:
		scene = load(path).instantiate()
		scene.playing = false
		root.add_child(scene)
		current_scene = scene
		var deadline := Time.get_ticks_msec() + 90000
		while not scene.ready_for_ticks and scene.last_error.is_empty() and Time.get_ticks_msec() < deadline:
			await process_frame
		_check(scene.scene_key + "_ready", scene.ready_for_ticks and scene.last_error.is_empty())
		if not scene.ready_for_ticks:
			break
		scene.get_node("Interface").hide()
		scene.get_node("Interface/PerformancePanel/Margin/Rows/Header/Sampling").button_pressed = false
		var materials := {}
		for pair in [["water", scene.water_material], ["sand", scene.terrain_material], ["fine", scene.get_node("PrototypeFrontFoamDense").material_override], ["contact", scene.get_node("ShoreContactOverlay").material_override]]:
			materials[pair[0]] = _material(pair[1])
		var fields := await _snapshot()
		var camera: Camera3D = root.get_camera_3d()
		var row := {"key": scene.scene_key, "path": path, "materials": materials, "camera": {"transform": var_to_str(camera.global_transform), "fov": camera.fov}, "sun": var_to_str(scene.get_node("SandFixtureSun").transform), "metrics": _metrics(fields)}
		for key in FIELDS:
			var file := FileAccess.open(output.path_join(scene.scene_key + "_" + key + ".f32"), FileAccess.WRITE)
			file.store_buffer(fields[key])
		result.scenes.append(row)
		if reference.is_empty():
			reference = materials
			common_transform = camera.global_transform
			common_fov = camera.fov
		else:
			for key in materials:
				_check(scene.scene_key + "_" + key + "_static_uniforms_match", materials[key].parameters == reference[key].parameters and materials[key].shader_sha256 == reference[key].shader_sha256)
				var compatible := true
				for binding in materials[key].runtime:
					if binding != "prototype_planar_view_projection":
						compatible = compatible and materials[key].runtime[binding] == reference[key].runtime.get(binding)
				_check(scene.scene_key + "_" + key + "_runtime_binding_shapes_match", compatible)
		if scene.scene_key == "test1_capture":
			capture_fields = fields
		elif scene.scene_key == "test1_backwash":
			_check("test1_initial_fields_equal", capture_fields == fields)
		await _capture("default")
		if scene.scene_key == "test1_backwash":
			_check("test1_initial_render_equal", FileAccess.get_sha256(output.path_join("test1_capture_default.png")) == FileAccess.get_sha256(output.path_join("test1_backwash_default.png")))
		var own_transform := camera.global_transform
		camera.global_transform = common_transform
		camera.fov = common_fov
		await _capture("main_camera")
		camera.global_transform = own_transform
		camera.fov = row.camera.fov
		if scene.scene_key != "main":
			scene.water_material.set_shader_parameter("rdc_normal_enabled", false)
			await _capture("no_detail_normal")
			scene.water_material.set_shader_parameter("rdc_normal_enabled", true)
			scene.water_material.set_shader_parameter("rdc_distance_scale", 0.0)
			await _capture("no_absorption")
			scene.water_material.set_shader_parameter("rdc_distance_scale", 1.0)
		var after := await _snapshot()
		_check(scene.scene_key + "_diagnostics_do_not_change_fields", fields == after)
		await scene.shutdown()
		scene.queue_free()
		await process_frame
		await process_frame
	result.engine = Engine.get_version_info()
	result.adapter = RenderingServer.get_video_adapter_name()
	result.pass = result.scenes.size() == 3
	for item in result.checks:
		result.pass = result.pass and item.pass
	var file := FileAccess.open(output.path_join("result.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	quit(0 if result.pass else 1)

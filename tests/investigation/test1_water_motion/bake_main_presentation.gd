extends SceneTree

## Bake main's effective visual resources; no live state textures are serialized.
func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	var deadline := Time.get_ticks_msec() + 90000
	while not scene.ready_for_ticks and scene.last_error.is_empty() and Time.get_ticks_msec() < deadline:
		await process_frame
	if not scene.ready_for_ticks or not scene.last_error.is_empty():
		push_error("main visual bake: " + scene.last_error)
		quit(1)
		return
	var manifest := {"source_scene": "res://scenes/main.tscn", "source_scene_sha256": FileAccess.get_sha256("res://scenes/main.tscn"), "materials": [], "front_band": scene.prototype_front_band_foam_source}
	for pair in [["water", scene.water_material], ["sand", scene.terrain_material], ["fine", scene.get_node("PrototypeFrontFoamDense").material_override], ["contact", scene.get_node("ShoreContactOverlay").material_override]]:
		var source: ShaderMaterial = pair[1]
		var material := ShaderMaterial.new()
		material.resource_local_to_scene = true
		material.shader = source.shader
		material.render_priority = source.render_priority
		var values := {}
		var omitted := []
		for uniform in source.shader.get_shader_uniform_list():
			var key: String = uniform.name
			var value: Variant = source.get_shader_parameter(key)
			if value is Texture2DRD or value is ViewportTexture:
				omitted.append(key)
				continue
			if value != null:
				material.set_shader_parameter(key, value)
				values[key] = var_to_str(value) if not value is Resource else value.resource_path
		var path := "res://assets/test1_water_motion/main_%s.tres" % pair[0]
		if ResourceSaver.save(material, path) != OK:
			quit(1)
			return
		manifest.materials.append({"material": pair[0], "path": path, "shader": source.shader.resource_path, "shader_sha256": FileAccess.get_sha256(source.shader.resource_path), "parameters": values, "runtime_bindings_to_replace": omitted})
	for pair in [["grid", scene.get_node("GpuWaterSurface").mesh], ["fine_mesh", scene.get_node("PrototypeFrontFoamDense").mesh], ["environment", scene.get_node("WorldEnvironment").environment]]:
		var path := "res://assets/test1_water_motion/main_%s.res" % pair[0]
		if ResourceSaver.save(pair[1], path) != OK:
			quit(1)
			return
	var file := FileAccess.open("res://assets/test1_water_motion/main_presentation.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "\t"))
	print("main presentation baked")
	scene.queue_free()
	await process_frame
	await process_frame
	quit(0)

extends "res://tests/water_material_natural/capture.gd"

func _lighting_sweep(before: Dictionary) -> void:
	var sun: DirectionalLight3D = preview.get_node("SandFixtureSun")
	var foam: ShaderMaterial = preview.get_node("PrototypeFrontFoamDense").material_override
	var water_values := _bindings(preview.water_material)
	var foam_values := _bindings(foam)
	var rows := {}
	preview.set_fixture_camera(&"oblique")
	var ids := ["normal_baseline", "engine_unshadowed", "engine_shadowed"]
	if preview.has_node("TerrainShadowProxy"): ids.append("engine_proxy")
	for id in ids:
		preview.water_material.shader = load("res://assets/water_material_natural_candidate/water_normal.gdshader" if id == "normal_baseline" else "res://assets/water_material_natural_candidate/water_engine_light.gdshader")
		foam.shader = load("res://assets/test1_beach/test1_front_foam_splats.gdshader" if id == "normal_baseline" else "res://assets/water_material_natural_candidate/foam_engine_light.gdshader")
		_restore(preview.water_material, water_values)
		_restore(foam, foam_values)
		sun.shadow_enabled = id in ["engine_shadowed", "engine_proxy"]
		if preview.has_node("TerrainShadowProxy"): preview.set_shadow_proxy(id == "engine_proxy")
		for i in range(30):
			await process_frame
			await RenderingServer.frame_post_draw
		var samples := []
		var sampling_start_unix := Time.get_unix_time_from_system()
		var start := Time.get_ticks_usec()
		var previous := start
		while Time.get_ticks_usec() - start < 5000000:
			await process_frame
			await RenderingServer.frame_post_draw
			var now := Time.get_ticks_usec()
			samples.append(float(now-previous)/1000.0)
			previous = now
		rows[id] = {"frame_ms":samples,"elapsed_us":previous-start,"viewport_px":root.size,
			"sampling_start_unix":sampling_start_unix,"sampling_end_unix":sampling_start_unix+float(previous-start)/1000000.0,
			"water_shader":preview.water_material.shader.resource_path,"foam_shader":foam.shader.resource_path,
			"sun_shadow":sun.shadow_enabled,"sun_direction":str(sun.global_basis.z.normalized()),
			"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			"video_mem_bytes":Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)}
	var file := FileAccess.open(output + "/short_cost.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"cases":rows,"tick":preview.completed_ticks,"revision":preview.solver.state_revision,
		"clock":preview.visual_time_s,"adapter":RenderingServer.get_video_adapter_name(),
		"driver":RenderingServer.get_current_rendering_driver_name(),"vsync":DisplayServer.window_get_vsync_mode(),
		"measurement":"visible 1280x720 frozen completed state; frame_post_draw wall intervals, 30 warm frames then 5s each; render-route attribution only, not final active simulation cost gate"},"\t"))
	file.close()

func _bindings(material: ShaderMaterial) -> Dictionary:
	var values := {}
	for uniform in material.shader.get_shader_uniform_list():
		values[uniform.name] = material.get_shader_parameter(uniform.name)
	return values

func _restore(material: ShaderMaterial, values: Dictionary) -> void:
	for uniform in material.shader.get_shader_uniform_list():
		if values.has(uniform.name):
			material.set_shader_parameter(uniform.name,values[uniform.name])

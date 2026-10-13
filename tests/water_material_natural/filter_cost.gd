extends "res://tests/water_material_natural/lighting_cost.gd"

func _lighting_sweep(before: Dictionary) -> void:
	var sun: DirectionalLight3D = preview.get_node("SandFixtureSun")
	var foam: ShaderMaterial = preview.get_node("PrototypeFrontFoamDense").material_override
	var water_values := _bindings(preview.water_material)
	var foam_values := _bindings(foam)
	var rows := {}
	preview.set_fixture_camera(&"oblique")
	var rid := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid,true)
	for id in ["normal_baseline", "engine_soft2", "engine_soft1", "engine_hard0", "no_standard_specular_soft1"]:
		var shader_path := "res://assets/water_material_natural_candidate/water_engine_light.gdshader"
		if id == "normal_baseline": shader_path = "res://assets/water_material_natural_candidate/water_normal.gdshader"
		if id == "no_standard_specular_soft1": shader_path = "res://assets/water_material_natural_candidate/water_engine_light_no_standard_specular.gdshader"
		preview.water_material.shader = load(shader_path)
		foam.shader = load("res://assets/test1_beach/test1_front_foam_splats.gdshader" if id == "normal_baseline" else "res://assets/water_material_natural_candidate/foam_engine_light.gdshader")
		_restore(preview.water_material,water_values);_restore(foam,foam_values)
		sun.shadow_enabled = id != "normal_baseline"
		var quality := 2 if id in ["normal_baseline", "engine_soft2"] else (0 if id == "engine_hard0" else 1)
		RenderingServer.directional_soft_shadow_filter_set_quality(quality)
		for i in range(30):
			await process_frame
			await RenderingServer.frame_post_draw
		var frames := []
		var gpu := []
		var cpu := []
		var sampling_start_unix := Time.get_unix_time_from_system()
		var start := Time.get_ticks_usec()
		var previous := start
		while Time.get_ticks_usec()-start<5000000:
			await process_frame
			await RenderingServer.frame_post_draw
			var now := Time.get_ticks_usec()
			frames.append(float(now-previous)/1000.0);previous=now
			gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(rid))
			cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(rid))
		var path: String = output + "/" + String(id) + ".png"
		root.get_texture().get_image().save_png(path)
		rows[id] = {"frame_ms":frames,"gpu_ms":gpu,"cpu_ms":cpu,"quality":quality,
			"water_shader":shader_path,"shadow_enabled":sun.shadow_enabled,
			"sampling_start_unix":sampling_start_unix,"sampling_end_unix":sampling_start_unix+float(previous-start)/1000000.0,
			"image":path,"image_sha256":FileAccess.get_sha256(path)}
	var file := FileAccess.open(output+"/filter_cost.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"cases":rows,"viewport_px":root.size,
		"adapter":RenderingServer.get_video_adapter_name(),"driver":RenderingServer.get_current_rendering_driver_name(),
		"clock":preview.visual_time_s,"tick":preview.completed_ticks,
		"scope":"720p frozen 5s visible route comparison; render time instrumentation enabled equally; not final 1080p active budget"},"\t"))
	file.close()

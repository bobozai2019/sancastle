extends "res://tests/water_material_natural/lighting_cost.gd"

func _lighting_sweep(before: Dictionary) -> void:
	var values := _bindings(preview.water_material)
	var rows := {}
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	for id in ["native", "packed", "specialized"]:
		var shader_path := "res://assets/water_material_natural_candidate/water_engine_light.gdshader"
		if id == "packed": shader_path = "res://assets/water_material_natural_candidate/water_engine_light_packed.gdshader"
		if id == "specialized": shader_path = "res://assets/water_material_natural_candidate/water_engine_light_specialized.gdshader"
		preview.water_material.shader = load(shader_path)
		_restore(preview.water_material,values)
		var images := {}
		for debug in [0,1,2,3,4]:
			preview.water_material.set_shader_parameter("natural_lighting_debug",debug)
			for camera in [&"oblique", &"close", &"grazing", &"sunward"]:
				preview.set_fixture_camera(camera)
				for i in range(8): await process_frame
				await RenderingServer.frame_post_draw
				var path: String = output + "/%s_debug%d_%s.png" % [String(id),debug,String(camera)]
				root.get_texture().get_image().save_png(path)
				images["%d_%s" % [debug,String(camera)]]={"path":path,"sha256":FileAccess.get_sha256(path)}
		preview.water_material.set_shader_parameter("natural_lighting_debug",0)
		preview.set_fixture_camera(&"oblique")
		for i in range(30):
			await process_frame
			await RenderingServer.frame_post_draw
		var samples := []
		var gpu := []
		var start := Time.get_ticks_usec()
		var previous := start
		while Time.get_ticks_usec()-start<5000000:
			await process_frame
			await RenderingServer.frame_post_draw
			var now := Time.get_ticks_usec()
			samples.append(float(now-previous)/1000.0);previous=now
			gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
		rows[id]={"images":images,"shader":shader_path,"frame_ms":samples,"gpu_ms":gpu}
	var file := FileAccess.open(output+"/packed_comparison.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"cases":rows,"tick":preview.completed_ticks,"revision":preview.solver.state_revision,
		"clock":preview.visual_time_s,"scope":"light input packing/specialization equivalence and frozen GPU attribution"},"\t"))
	file.close()

extends "res://tests/water_material_natural/optics_path_probe.gd"

func _lighting_sweep(before: Dictionary) -> void:
	var water := preview.water_material as ShaderMaterial
	var values := _bindings(water)
	water.shader = load("res://assets/water_material_natural_candidate/water_path_diagnostic.gdshader")
	_restore(water,values)
	var rows := {}
	for id in ["legacy","current","offset_zero","guard_off","unrefracted"]:
		water.set_shader_parameter("natural_path_mode",0 if id == "legacy" else 1)
		water.set_shader_parameter("natural_path_unrefracted",id == "unrefracted")
		water.set_shader_parameter("prototype_refraction_scale",0.0 if id == "offset_zero" else 0.02)
		water.set_shader_parameter("prototype_depth_guard",id != "guard_off")
		water.set_shader_parameter("prototype_deep_extinction_m",0.40)
		var images := {}
		for debug in [0,2,3,4]:
			water.set_shader_parameter("natural_optics_debug",debug)
			preview.get_node("PrototypeFrontFoamDense").visible = debug == 0
			preview.get_node("ShoreContactOverlay").visible = debug == 0
			for camera in [&"oblique",&"close",&"grazing"]:
				preview.set_fixture_camera(camera)
				for i in range(8): await process_frame
				await RenderingServer.frame_post_draw
				var path: String = output + "/%s_debug%d_%s.png" % [id,debug,String(camera)]
				root.get_texture().get_image().save_png(path)
				images["%d_%s" % [debug,String(camera)]]={"path":path,"sha256":FileAccess.get_sha256(path)}
		rows[id]={"images":images,"uniforms":Uniforms.material_values(water)}
	fields.clear()
	RenderingServer.call_on_render_thread(_read_fields)
	var deadline := Time.get_ticks_msec()+10000
	while fields.size()<7:
		await process_frame
		if Time.get_ticks_msec()>deadline: _fail("boundary readback timeout"); return
	var same := {}
	for field in fields:
		var ctx := HashingContext.new()
		ctx.start(HashingContext.HASH_SHA256);ctx.update(fields[field])
		same[field]=ctx.finish().hex_encode()==before[field].sha256
		if not same[field]: _fail("boundary authority changed"); return
	var file := FileAccess.open(output+"/path_boundary.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"cases":rows,"fields_unchanged":same,"shader_sha256":FileAccess.get_sha256(water.shader.resource_path)},"\t"))
	file.close()

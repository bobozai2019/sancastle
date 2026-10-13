extends "res://tests/water_material_natural/lighting_cost.gd"

func _lighting_sweep(before: Dictionary) -> void:
	var water := preview.water_material as ShaderMaterial
	var values := _bindings(water)
	var rows := {}
	for id in ["native","legacy","reconstructed"]:
		water.shader = load("res://assets/water_material_natural_candidate/water_engine_light.gdshader" if id == "native" else "res://assets/water_material_natural_candidate/water_optics.gdshader")
		_restore(water,values)
		if id != "native": water.set_shader_parameter("natural_path_mode",1 if id == "reconstructed" else 0)
		var images := {}
		for debug in ([0] if id == "native" else [0,1,2,3,4,5,6]):
			if id != "native": water.set_shader_parameter("natural_optics_debug",debug)
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
		if Time.get_ticks_msec()>deadline: _fail("optics readback timeout"); return
	var same := {}
	for field in fields:
		var ctx := HashingContext.new()
		ctx.start(HashingContext.HASH_SHA256);ctx.update(fields[field])
		same[field]=ctx.finish().hex_encode()==before[field].sha256
		if not same[field]: _fail("optics authority changed"); return
	var file := FileAccess.open(output+"/optics_path.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"cases":rows,"fields_unchanged":same,"effective_optics":preview.effective_optics},"\t"))
	file.close()

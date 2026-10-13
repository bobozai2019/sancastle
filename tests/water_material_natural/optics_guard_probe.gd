extends "res://tests/water_material_natural/capture.gd"

func _lighting_sweep(before: Dictionary) -> void:
	var water := preview.water_material as ShaderMaterial
	var rows := {}
	preview.get_node("PrototypeFrontFoamDense").visible = false
	preview.get_node("ShoreContactOverlay").visible = false
	for id in ["protected","unguarded","edge_clamp","zero_refraction"]:
		water.set_shader_parameter("prototype_depth_guard",id != "unguarded")
		water.set_shader_parameter("prototype_legacy_edge_clamp",id == "edge_clamp")
		water.set_shader_parameter("prototype_refraction_scale",0.0 if id == "zero_refraction" else preview.optics_profile.refraction_scale)
		var images := {}
		for debug in [3,6]:
			water.set_shader_parameter("natural_optics_debug",debug)
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
		if Time.get_ticks_msec()>deadline: _fail("guard readback timeout"); return
	var same := {}
	for field in fields:
		var ctx := HashingContext.new()
		ctx.start(HashingContext.HASH_SHA256);ctx.update(fields[field])
		same[field]=ctx.finish().hex_encode()==before[field].sha256
		if not same[field]: _fail("guard authority changed"); return
	var file := FileAccess.open(output+"/optics_guard.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"cases":rows,"fields_unchanged":same,"effective_optics":preview.effective_optics},"\t"))
	file.close()

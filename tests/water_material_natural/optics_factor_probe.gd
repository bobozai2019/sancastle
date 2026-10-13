extends "res://tests/water_material_natural/capture.gd"

func _lighting_sweep(before: Dictionary) -> void:
	var water := preview.water_material as ShaderMaterial
	var rows := {}
	var candidates := {
		"baseline":{}, "deep_022":{"prototype_deep_extinction_m":0.22},
		"deep_040":{"prototype_deep_extinction_m":0.40},
		"shallow_050":{"prototype_shallow_extinction_m":0.50},
		"scatter_075":{"natural_scatter_gain":0.75},
		"scatter_050":{"natural_scatter_gain":0.50},
		"preserve_off":{"prototype_optical_shallow_preserve":false}}
	for id in candidates:
		water.set_shader_parameter("prototype_deep_extinction_m",preview.optics_profile.extinction_deep_m)
		water.set_shader_parameter("prototype_shallow_extinction_m",preview.optics_profile.extinction_shallow_m)
		water.set_shader_parameter("natural_scatter_gain",preview.optics_profile.scatter_gain)
		water.set_shader_parameter("prototype_optical_shallow_preserve",preview.optics_profile.shallow_preserve)
		for name in candidates[id]: water.set_shader_parameter(name,candidates[id][name])
		var images := {}
		for debug in [0,4]:
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
		rows[id]={"images":images,"changes":candidates[id],"uniforms":Uniforms.material_values(water)}
	fields.clear()
	RenderingServer.call_on_render_thread(_read_fields)
	var deadline := Time.get_ticks_msec()+10000
	while fields.size()<7:
		await process_frame
		if Time.get_ticks_msec()>deadline: _fail("factor readback timeout"); return
	var same := {}
	for field in fields:
		var ctx := HashingContext.new()
		ctx.start(HashingContext.HASH_SHA256);ctx.update(fields[field])
		same[field]=ctx.finish().hex_encode()==before[field].sha256
		if not same[field]: _fail("factor authority changed"); return
	var file := FileAccess.open(output+"/optics_factors.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"cases":rows,"fields_unchanged":same,"effective_optics":preview.effective_optics},"\t"))
	file.close()

extends "res://tests/water_material_natural/optics_path_probe.gd"

func _lighting_sweep(before: Dictionary) -> void:
	var water:=preview.water_material as ShaderMaterial
	var values:=_bindings(water)
	var env:Environment=preview.get_node("WorldEnvironment").environment
	var rows:={}
	preview.get_node("PrototypeFrontFoamDense").visible=false
	preview.get_node("ShoreContactOverlay").visible=false
	for id in ["raw","source_color","protected_source_color"]:
		water.shader=load("res://assets/water_material_natural_candidate/water_reflection.gdshader" if id=="raw" else "res://assets/water_material_natural_candidate/water_reflection_srgb_probe.gdshader")
		_restore(water,values)
		water.set_shader_parameter("natural_reflection_protected",id=="protected_source_color")
		water.set_shader_parameter("natural_reflection_perturbation",false)
		var images:={}
		for debug in [0,4]:
			water.set_shader_parameter("natural_reflection_debug",debug)
			for camera in [&"oblique",&"close",&"grazing"]:
				preview.set_fixture_camera(camera)
				for i in range(8):await process_frame
				await RenderingServer.frame_post_draw
				var path:String=output+"/%s_debug%d_%s.png"%[id,debug,String(camera)]
				root.get_texture().get_image().save_png(path)
				images["%d_%s"%[debug,String(camera)]]={"path":path,"sha256":FileAccess.get_sha256(path)}
		rows[id]={"images":images,"shader":water.shader.resource_path,"shader_sha256":FileAccess.get_sha256(water.shader.resource_path),
			"uniforms":Uniforms.material_values(water)}
	fields.clear();RenderingServer.call_on_render_thread(_read_fields)
	var deadline:=Time.get_ticks_msec()+10000
	while fields.size()<7:
		await process_frame
		if Time.get_ticks_msec()>deadline:_fail("reflection color readback timeout");return
	var same:={}
	for name in fields:
		var ctx:=HashingContext.new();ctx.start(HashingContext.HASH_SHA256);ctx.update(fields[name])
		same[name]=ctx.finish().hex_encode()==before[name].sha256
		if not same[name]:_fail("reflection color authority changed");return
	var file:=FileAccess.open(output+"/reflection_color.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"cases":rows,"fields_unchanged":same,"environment":{"background_color":str(env.background_color),
		"background_mode":env.background_mode,"background_energy":env.background_energy_multiplier,
		"tonemap_mode":env.tonemap_mode,"exposure":env.tonemap_exposure},
		"scope":"Only planar color sampler hint changes; guarded case is separate from encoding-only comparison."},"\t"));file.close()

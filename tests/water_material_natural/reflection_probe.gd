extends "res://tests/water_material_natural/capture.gd"

func _lighting_sweep(before: Dictionary) -> void:
	var water:=preview.water_material as ShaderMaterial
	var fine:ShaderMaterial=preview.get_node("PrototypeFrontFoamDense").material_override
	var contact:ShaderMaterial=preview.get_node("ShoreContactOverlay").material_override
	var cases:={
		"legacy":{"protected":false,"perturb":false,"shift":.25,"limit":.03,"gain":1.,"detail":true,"debug":[0,3,4,5]},
		"guarded":{"protected":true,"perturb":false,"shift":.25,"limit":.03,"gain":1.,"detail":true,"debug":[0,1,2,3,4,5]},
		"perturbed":{"protected":true,"perturb":true,"shift":.25,"limit":.03,"gain":1.,"detail":true,"debug":[0,1,2,3,4,5]},
		"zero_shift":{"protected":true,"perturb":true,"shift":0.,"limit":.03,"gain":1.,"detail":true,"debug":[0,2]},
		"zero_limit":{"protected":true,"perturb":true,"shift":.25,"limit":0.,"gain":1.,"detail":true,"debug":[0,2]},
		"zero_gain":{"protected":true,"perturb":true,"shift":.25,"limit":.03,"gain":0.,"detail":true,"debug":[0]},
		"detail_off":{"protected":true,"perturb":true,"shift":.25,"limit":.03,"gain":1.,"detail":false,"debug":[2,4]}}
	var rows:={}
	for id in cases:
		var c:Dictionary=cases[id]
		water.set_shader_parameter("natural_reflection_protected",c.protected)
		water.set_shader_parameter("natural_reflection_perturbation",c.perturb)
		water.set_shader_parameter("natural_reflection_shift_m",c.shift)
		water.set_shader_parameter("natural_reflection_uv_limit",c.limit)
		water.set_shader_parameter("natural_reflection_gain",c.gain)
		water.set_shader_parameter("use_detail_normals",c.detail)
		var images:={}
		for debug in c.debug:
			water.set_shader_parameter("natural_reflection_debug",debug)
			fine.set_shader_parameter("natural_fine_enabled",debug==0)
			contact.set_shader_parameter("natural_contact_enabled",debug==0)
			for camera in [&"oblique",&"close",&"grazing"]:
				preview.set_fixture_camera(camera)
				for i in range(8):await process_frame
				await RenderingServer.frame_post_draw
				var path:String=output+"/%s_debug%d_%s.png"%[id,debug,String(camera)]
				root.get_texture().get_image().save_png(path)
				images["%d_%s"%[debug,String(camera)]]={"path":path,"sha256":FileAccess.get_sha256(path)}
		rows[id]={"images":images,"uniforms":Uniforms.material_values(water),"controls":c}
	fields.clear();RenderingServer.call_on_render_thread(_read_fields)
	var deadline:=Time.get_ticks_msec()+10000
	while fields.size()<7:
		await process_frame
		if Time.get_ticks_msec()>deadline:_fail("reflection readback timeout");return
	var same:={}
	for name in fields:
		var ctx:=HashingContext.new();ctx.start(HashingContext.HASH_SHA256);ctx.update(fields[name])
		same[name]=ctx.finish().hex_encode()==before[name].sha256
		if not same[name]:_fail("reflection changed authority");return
	var file:=FileAccess.open(output+"/reflection_cases.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"cases":rows,"fields_unchanged":same,"effective_reflection":preview.effective_reflection},"\t"));file.close()

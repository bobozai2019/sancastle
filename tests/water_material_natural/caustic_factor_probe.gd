extends "res://tests/water_material_natural/capture.gd"

func _lighting_sweep(before: Dictionary) -> void:
	var bed:=preview.terrain_material as ShaderMaterial
	var rows:={}
	var cases:={"baseline":{},"soft00":{"prototype_caustic_softness":0.},
		"soft05":{"prototype_caustic_softness":.5},"gain05":{"prototype_caustic_strength":.5},
		"scale10":{"prototype_caustic_uv_scale":1.},"scale30":{"prototype_caustic_uv_scale":3.},
		"disabled":{"phase2_caustics":false},"gain00":{"prototype_caustic_strength":0.}}
	for id in cases:
		bed.set_shader_parameter("phase2_caustics",true)
		bed.set_shader_parameter("prototype_caustic_softness",1.)
		bed.set_shader_parameter("prototype_caustic_strength",.8)
		bed.set_shader_parameter("prototype_caustic_uv_scale",2.)
		for name in cases[id]:bed.set_shader_parameter(name,cases[id][name])
		var images:={}
		for mode in ["production","bed_only"]:
			preview.get_node("GpuWaterSurface").visible=mode=="production"
			preview.get_node("PrototypeFrontFoamDense").visible=mode=="production"
			preview.get_node("ShoreContactOverlay").visible=mode=="production"
			for camera in [&"oblique",&"close",&"grazing"]:
				preview.set_fixture_camera(camera)
				for i in range(8):await process_frame
				await RenderingServer.frame_post_draw
				var path:String=output+"/%s_%s_%s.png"%[id,mode,String(camera)]
				root.get_texture().get_image().save_png(path)
				images["%s_%s"%[mode,String(camera)]]={"path":path,"sha256":FileAccess.get_sha256(path)}
		rows[id]={"images":images,"changes":cases[id],"bed_uniforms":Uniforms.material_values(bed)}
	fields.clear();RenderingServer.call_on_render_thread(_read_fields)
	var deadline:=Time.get_ticks_msec()+10000
	while fields.size()<7:
		await process_frame
		if Time.get_ticks_msec()>deadline:_fail("caustic readback timeout");return
	var same:={}
	for name in fields:
		var ctx:=HashingContext.new();ctx.start(HashingContext.HASH_SHA256);ctx.update(fields[name])
		same[name]=ctx.finish().hex_encode()==before[name].sha256
		if not same[name]:_fail("caustic authority changed");return
	var file:=FileAccess.open(output+"/caustic_factors.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"cases":rows,"fields_unchanged":same,"effective_reflection":preview.effective_reflection,
		"scope":"Existing bed caustic parameters only; stable completed state and bed UV anchoring."},"\t"));file.close()

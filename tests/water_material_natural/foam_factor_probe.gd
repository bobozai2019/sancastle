extends "res://tests/water_material_natural/capture.gd"

func _lighting_sweep(before: Dictionary) -> void:
	var water:=preview.water_material as ShaderMaterial
	var fine: ShaderMaterial=preview.get_node("PrototypeFrontFoamDense").material_override
	var contact: ShaderMaterial=preview.get_node("ShoreContactOverlay").material_override
	var mesh: ArrayMesh=preview.get_node("PrototypeFrontFoamDense").mesh
	var arrays:=mesh.surface_get_arrays(0)
	var centers:=[]
	for i in range(0,arrays[Mesh.ARRAY_TEX_UV].size(),4):
		var uv: Vector2=arrays[Mesh.ARRAY_TEX_UV][i]
		centers.append([uv.x,uv.y])
	var mesh_record:={"centers_uv":centers,"resource":mesh.resource_path,
		"sha256":FileAccess.get_sha256(mesh.resource_path),"fine_uniforms":Uniforms.material_values(fine)}
	var defaults:={"natural_fine_size_mode":0,"natural_fine_size_range":Vector2(.65,1.3),
		"natural_cluster_strength":0.0,"natural_fine_gain":1.0,"natural_foam_direct_fraction":.5,"splat_jitter_m":.02}
	var cases:={"baseline":{},"weighted":{"natural_fine_size_mode":1,"natural_fine_size_range":Vector2(.35,1.9)},
		"cluster065":{"natural_cluster_strength":.65},"coverage070":{"natural_fine_gain":.7},
		"direct075":{"natural_foam_direct_fraction":.75},"jitter005":{"splat_jitter_m":.05},
		"contact0003":{"surface_offset_m":.003}}
	var rows:={}
	for id in cases:
		for name in defaults: fine.set_shader_parameter(name,defaults[name])
		contact.set_shader_parameter("surface_offset_m",.016)
		for name in cases[id]:
			if name=="surface_offset_m":contact.set_shader_parameter(name,cases[id][name])
			else:fine.set_shader_parameter(name,cases[id][name])
		var images:={}
		for mode in ["production","fine_only"]:
			water.set_shader_parameter("natural_main_foam_gain",1.0 if mode=="production" else 0.0)
			contact.set_shader_parameter("natural_contact_enabled",mode=="production")
			for camera in [&"oblique",&"close",&"grazing"]:
				preview.set_fixture_camera(camera)
				for i in range(8):await process_frame
				await RenderingServer.frame_post_draw
				var path:String=output+"/%s_%s_%s.png"%[id,mode,String(camera)]
				root.get_texture().get_image().save_png(path)
				images["%s_%s"%[mode,String(camera)]]={"path":path,"sha256":FileAccess.get_sha256(path)}
		rows[id]={"images":images,"changes":cases[id],"fine_uniforms":Uniforms.material_values(fine),
			"contact_offset_m":contact.get_shader_parameter("surface_offset_m")}
	fields.clear();RenderingServer.call_on_render_thread(_read_fields)
	var deadline:=Time.get_ticks_msec()+10000
	while fields.size()<7:
		await process_frame
		if Time.get_ticks_msec()>deadline:_fail("foam factor readback timeout");return
	var same:={}
	for field in fields:
		var ctx:=HashingContext.new();ctx.start(HashingContext.HASH_SHA256);ctx.update(fields[field])
		same[field]=ctx.finish().hex_encode()==before[field].sha256
		if not same[field]:_fail("foam factor authority changed");return
	var file:=FileAccess.open(output+"/foam_factors.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"cases":rows,"fields_unchanged":same,"mesh":mesh_record,
		"effective_foam":preview.effective_foam},"\t"));file.close()

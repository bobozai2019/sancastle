extends "res://tests/water_material_natural/optics_path_probe.gd"

func _lighting_sweep(before: Dictionary) -> void:
	var water:=preview.water_material as ShaderMaterial
	var contact: ShaderMaterial=preview.get_node("ShoreContactOverlay").material_override
	var rows:={}
	var meshes:={}
	for name in ["GpuWaterSurface","ShoreContactOverlay"]:
		var node: MeshInstance3D=preview.get_node(name)
		var arrays:=node.mesh.surface_get_arrays(0)
		var uv: PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV]
		meshes[name]={"vertices":arrays[Mesh.ARRAY_VERTEX].size(),"indices":arrays[Mesh.ARRAY_INDEX].size(),
			"uv_first":str(uv[0]),"uv_last":str(uv[-1]),"mesh":node.mesh.resource_path,"transform":str(node.global_transform)}
	for height in [.016,.008,.004,.003]:
		contact.set_shader_parameter("surface_offset_m",height)
		var images:={}
		for mode in ["all_on","contact_only","bed_only","depth_labels"]:
			preview.get_node("GpuWaterSurface").visible=mode in ["all_on","depth_labels"]
			preview.get_node("PrototypeFrontFoamDense").visible=mode=="all_on"
			preview.get_node("ShoreContactOverlay").visible=mode in ["all_on","contact_only"]
			water.set_shader_parameter("natural_optics_debug",1 if mode=="depth_labels" else 0)
			for camera in [&"oblique",&"close",&"grazing"]:
				preview.set_fixture_camera(camera)
				for i in range(8):await process_frame
				await RenderingServer.frame_post_draw
				var path:String=output+"/h%04d_%s_%s.png"%[roundi(height*1000),mode,String(camera)]
				root.get_texture().get_image().save_png(path)
				images["%s_%s"%[mode,String(camera)]]={"path":path,"sha256":FileAccess.get_sha256(path)}
		rows[str(roundi(height*1000))]={"images":images,"height_m":contact.get_shader_parameter("surface_offset_m")}
	fields.clear();RenderingServer.call_on_render_thread(_read_fields)
	var deadline:=Time.get_ticks_msec()+10000
	while fields.size()<7:
		await process_frame
		if Time.get_ticks_msec()>deadline:_fail("contact height readback timeout");return
	var same:={}
	for field in fields:
		var ctx:=HashingContext.new();ctx.start(HashingContext.HASH_SHA256);ctx.update(fields[field])
		same[field]=ctx.finish().hex_encode()==before[field].sha256
		if not same[field]:_fail("contact height authority changed");return
	var file:=FileAccess.open(output+"/contact_height.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"cases":rows,"fields_unchanged":same,"meshes":meshes,
		"water_uniforms":Uniforms.material_values(water),"contact_uniforms":Uniforms.material_values(contact)},"\t"));file.close()

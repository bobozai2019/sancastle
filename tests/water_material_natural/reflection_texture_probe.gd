extends "res://tests/water_material_natural/capture.gd"

func _lighting_sweep(before: Dictionary) -> void:
	var water:=preview.water_material as ShaderMaterial
	var reflection:SubViewport=preview.get_node("ReflectionViewport")
	var camera_node:Camera3D=preview.get_node("ReflectionViewport/ReflectionCamera")
	var env_node:Node3D=preview.get_node("ReflectionRockEnvironment")
	preview.get_node("PrototypeFrontFoamDense").visible=false
	preview.get_node("ShoreContactOverlay").visible=false
	water.set_shader_parameter("natural_reflection_debug",4)
	water.set_shader_parameter("natural_reflection_protected",true)
	var rows:={}
	for id in ["rocks","no_rocks"]:
		env_node.visible=id=="rocks"
		var images:={}
		for camera in [&"oblique",&"close",&"grazing"]:
			preview.set_fixture_camera(camera)
			for i in range(8):await process_frame
			await RenderingServer.frame_post_draw
			var ref_image:=reflection.get_texture().get_image()
			var ref_path:String=output+"/%s_texture_%s.png"%[id,String(camera)]
			ref_image.save_png(ref_path)
			var path:String=output+"/%s_water_%s.png"%[id,String(camera)]
			root.get_texture().get_image().save_png(path)
			images[String(camera)]={"water":path,"water_sha256":FileAccess.get_sha256(path),
				"texture":ref_path,"texture_sha256":FileAccess.get_sha256(ref_path),"texture_format":ref_image.get_format(),
				"hdr_2d":reflection.use_hdr_2d,"camera_transform":var_to_str(camera_node.global_transform),
				"camera_cull_mask":camera_node.cull_mask,"view_projection":str(water.get_shader_parameter("prototype_planar_view_projection"))}
		rows[id]=images
	fields.clear();RenderingServer.call_on_render_thread(_read_fields)
	var deadline:=Time.get_ticks_msec()+10000
	while fields.size()<7:
		await process_frame
		if Time.get_ticks_msec()>deadline:_fail("reflection texture readback timeout");return
	var same:={}
	for name in fields:
		var ctx:=HashingContext.new();ctx.start(HashingContext.HASH_SHA256);ctx.update(fields[name])
		same[name]=ctx.finish().hex_encode()==before[name].sha256
		if not same[name]:_fail("reflection texture authority changed");return
	var file:=FileAccess.open(output+"/reflection_texture.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"cases":rows,"fields_unchanged":same,
		"environment_resource":env_node.scene_file_path,"environment_sha256":FileAccess.get_sha256(env_node.scene_file_path)},"\t"));file.close()

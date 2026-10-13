extends "res://tests/water_material_natural/optics_path_probe.gd"

func _lighting_sweep(before: Dictionary) -> void:
	var water:=preview.water_material as ShaderMaterial
	var values:=_bindings(water)
	var reflection:SubViewport=preview.get_node("ReflectionViewport")
	var ref_camera:Camera3D=preview.get_node("ReflectionViewport/ReflectionCamera")
	var actors:=preview.get_node("ReflectionRockEnvironment").get_children()
	preview.get_node("PrototypeFrontFoamDense").visible=false
	preview.get_node("ShoreContactOverlay").visible=false
	var rows:={}
	for id in ["original","original_no_reflected_rocks","flip_y","flip_y_no_reflected_rocks"]:
		var flipped:bool=id.begins_with("flip_y")
		water.shader=load("res://assets/water_material_natural_candidate/water_reflection_flip_y_probe.gdshader" if flipped else "res://assets/water_material_natural_candidate/water_reflection.gdshader")
		_restore(water,values)
		for actor in actors:actor.layers=1 if id.ends_with("no_reflected_rocks") else 5
		var images:={}
		for debug in [0,4]:
			water.set_shader_parameter("natural_reflection_debug",debug)
			for camera in [&"oblique",&"close",&"grazing"]:
				preview.set_fixture_camera(camera)
				for i in range(8):await process_frame
				await RenderingServer.frame_post_draw
				var path:String=output+"/%s_debug%d_%s.png"%[id,debug,String(camera)]
				root.get_texture().get_image().save_png(path)
				var ref_path:String=output+"/%s_texture%d_%s.png"%[id,debug,String(camera)]
				reflection.get_texture().get_image().save_png(ref_path)
				var projected:={}
				for actor in actors:projected[actor.name]={"screen":str(ref_camera.unproject_position(actor.global_position)),
					"world":str(actor.global_position),"layers":actor.layers}
				images["%d_%s"%[debug,String(camera)]]={"path":path,"sha256":FileAccess.get_sha256(path),
					"texture":ref_path,"texture_sha256":FileAccess.get_sha256(ref_path),"projected_actor_origins":projected}
		rows[id]={"images":images,"shader":water.shader.resource_path,"shader_sha256":FileAccess.get_sha256(water.shader.resource_path),
			"uniforms":Uniforms.material_values(water),"runtime_change":"Y UV mapping only; actor layer 5->1 removes reflected bit while preserving main-view bit1"}
	fields.clear();RenderingServer.call_on_render_thread(_read_fields)
	var deadline:=Time.get_ticks_msec()+10000
	while fields.size()<7:
		await process_frame
		if Time.get_ticks_msec()>deadline:_fail("orientation readback timeout");return
	var same:={}
	for name in fields:
		var ctx:=HashingContext.new();ctx.start(HashingContext.HASH_SHA256);ctx.update(fields[name])
		same[name]=ctx.finish().hex_encode()==before[name].sha256
		if not same[name]:_fail("orientation authority changed");return
	var file:=FileAccess.open(output+"/reflection_orientation.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"cases":rows,"fields_unchanged":same,
		"scope":"Reflection-only layer negative keeps actual main-view rocks; shader runtime swap only changes projected UV Y mapping."},"\t"));file.close()

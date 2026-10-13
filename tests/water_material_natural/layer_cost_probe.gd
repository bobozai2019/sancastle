extends "res://tests/water_material_natural/common_checkpoint_cost.gd"

func _lighting_sweep(before: Dictionary) -> void:
	preview.playing=false
	preview.replay_target_tick=-1
	preview.set_fixture_camera(&"close")
	var water:=preview.water_material as ShaderMaterial
	var bed:=preview.terrain_material as ShaderMaterial
	var sun:DirectionalLight3D=preview.get_node("SandFixtureSun")
	var contact:MeshInstance3D=preview.get_node("ShoreContactOverlay")
	var fine:MeshInstance3D=preview.get_node("PrototypeFrontFoamDense")
	var surface:MeshInstance3D=preview.get_node("GpuWaterSurface")
	var terrain:MeshInstance3D=preview.get_node("GpuSandTerrain")
	var reflect:SubViewport=preview.get_node("ReflectionViewport")
	var initial:={"shadow":sun.shadow_enabled,"contact":contact.visible,"fine":fine.visible,"water":surface.visible,"bed":terrain.visible,"reflection_update":reflect.render_target_update_mode}
	var controls:={"use_detail_normals":water.get_shader_parameter("use_detail_normals"),"natural_glint_enabled":water.get_shader_parameter("natural_glint_enabled"),"natural_reflection_gain":water.get_shader_parameter("natural_reflection_gain")}
	var caustic:Variant=bed.get_shader_parameter("natural_caustic_enabled")
	var cases:=["all_start","all_end"]
	if preview.get("style_profile_path") is String:
		cases=["all_start","shadow_off","contact_hidden","fine_hidden","water_hidden","bed_hidden","reflection_viewport_off","detail_off","glint_off","reflection_gain_zero","caustics_off","all_end"]
	var rid:=root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid,true)
	var rows:={}
	for id in cases:
		sun.shadow_enabled=initial.shadow;contact.visible=initial.contact;fine.visible=initial.fine;surface.visible=initial.water;terrain.visible=initial.bed
		reflect.render_target_update_mode=initial.reflection_update
		for key in controls:
			if controls[key]!=null:water.set_shader_parameter(key,controls[key])
		if caustic!=null:bed.set_shader_parameter("natural_caustic_enabled",caustic)
		match id:
			"shadow_off":sun.shadow_enabled=false
			"contact_hidden":contact.visible=false
			"fine_hidden":fine.visible=false
			"water_hidden":surface.visible=false
			"bed_hidden":terrain.visible=false
			"reflection_viewport_off":reflect.render_target_update_mode=SubViewport.UPDATE_DISABLED
			"detail_off":water.set_shader_parameter("use_detail_normals",false)
			"glint_off":water.set_shader_parameter("natural_glint_enabled",false)
			"reflection_gain_zero":water.set_shader_parameter("natural_reflection_gain",0.)
			"caustics_off":bed.set_shader_parameter("natural_caustic_enabled",false)
		for i in range(40):
			await process_frame;await RenderingServer.frame_post_draw
		var start:=Time.get_ticks_usec();var previous:=start
		var frames:=[];var gpu:=[];var cpu:=[]
		while Time.get_ticks_usec()-start<3000000:
			await process_frame;await RenderingServer.frame_post_draw
			if root.size!=Vector2i(1920,1080) or not root.visible:_fail("layer cost window changed");return
			var now:=Time.get_ticks_usec();frames.append(float(now-previous)/1000.);previous=now
			gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(rid));cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(rid))
		var image:String=output+"/"+String(id)+".png"
		if root.get_texture().get_image().save_png(image)!=OK:_fail("layer capture failure");return
		rows[id]={"frame_ms":frames,"gpu_render_ms":gpu,"cpu_render_ms":cpu,"elapsed_us":previous-start,"image":image,"image_sha256":FileAccess.get_sha256(image),"sun_shadow":sun.shadow_enabled,"contact_visible":contact.visible,"fine_visible":fine.visible,"water_visible":surface.visible,"bed_visible":terrain.visible,"reflection_update":reflect.render_target_update_mode,"water_uniforms":Uniforms.material_values(water),"bed_uniforms":Uniforms.material_values(bed),"tick":preview.completed_ticks,"visual_time_s":preview.visual_time_s}
	fields.clear();RenderingServer.call_on_render_thread(_read_fields)
	var deadline:=Time.get_ticks_msec()+10000
	while fields.size()<7:
		await process_frame
		if Time.get_ticks_msec()>deadline:_fail("layer readback timeout");return
	var pairs:={}
	for name in fields:
		var ctx:=HashingContext.new();ctx.start(HashingContext.HASH_SHA256);ctx.update(fields[name])
		pairs[name]=ctx.finish().hex_encode()==before[name].sha256
		if not pairs[name]:_fail("layer cost authority changed");return
	var file:=FileAccess.open(output+"/layer_cost.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"cases":rows,"authority_unchanged":pairs,"initial":initial,"scope":"Frozen common tick360 close1080, single-factor diagnostic only. Hidden layers are NOT delivery configs, not full cost acceptance."},"\t"));file.close()

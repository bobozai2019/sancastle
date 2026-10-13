extends "res://tests/water_material_natural/common_checkpoint_cost.gd"

func _state_hashes() -> Dictionary:
	fields.clear();RenderingServer.call_on_render_thread(_read_fields)
	var deadline:=Time.get_ticks_msec()+10000
	while fields.size()<7:
		await process_frame
		if Time.get_ticks_msec()>deadline:_fail("specialized state timeout");return {}
	var result:={}
	for key in fields:
		var ctx:=HashingContext.new();ctx.start(HashingContext.HASH_SHA256);ctx.update(fields[key]);result[key]=ctx.finish().hex_encode()
	return result

func _lighting_sweep(_before: Dictionary) -> void:
	preview.playing=false
	var mat:ShaderMaterial=preview.water_material
	var original:Shader=mat.shader
	var candidate:Shader=load("res://assets/water_material_natural_candidate/water_route_specialized.gdshader")
	var index:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/water_material_natural_candidate/water_route_full_index.json"))
	var rows:=[]
	var deadline:=Time.get_ticks_msec()+180000
	for tick in [360,540,1377,1380,1383]:
		mat.shader=original
		preview.replay_target_tick=tick;preview.replay_ready=false
		while not preview.replay_ready:
			await process_frame
			if Time.get_ticks_msec()>deadline or not preview.last_error.is_empty():_fail("specialized tick advance failed");return
		if preview.completed_ticks!=tick or preview.tick_pending or not is_equal_approx(preview.visual_time_s,float(tick)/30.):_fail("specialized incomplete clock");return
		for key in index.constants:
			var actual:Variant=mat.get_shader_parameter(key)
			if actual==null:actual=RenderingServer.shader_get_parameter_default(original.get_rid(),key)
			if actual!=index.constants[key]:_fail("specialized geometry input changed");return
		var before:=await _state_hashes()
		var params:={}
		for uniform in original.get_shader_uniform_list():
			var value:Variant=mat.get_shader_parameter(uniform.name)
			if value!=null:params[String(uniform.name)]=value
		var images:={}
		for id in ["original","specialized"]:
			mat.shader=original if id=="original" else candidate
			for key in params:mat.set_shader_parameter(key,params[key])
			for cam in [&"close",&"oblique",&"grazing"]:
				preview.set_fixture_camera(cam)
				for i in range(3):await process_frame
				await RenderingServer.frame_post_draw
				var path:String=output+"/%s_%d_%s.png"%[String(id),tick,String(cam)]
				if root.get_texture().get_image().save_png(path)!=OK:_fail("specialized sequence image failed");return
				images[String(id)+"_"+String(cam)]={"path":path,"sha256":FileAccess.get_sha256(path)}
		var after:=await _state_hashes()
		if before!=after:_fail("specialized sequence authority changed");return
		rows.append({"tick":tick,"time_s":preview.visual_time_s,"images":images,"before":before,"after":after,"uniforms":Uniforms.material_values(mat)})
	mat.shader=original
	var file:=FileAccess.open(output+"/route_sequence.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"frames":rows,"scope":"Five completed checkpoints incl former seam neighborhood, original vs fixed geometry shader on same authority. Sparse sequence, NOT full continuous acceptance."},"\t"));file.close()

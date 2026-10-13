extends "res://tests/water_material_natural/common_checkpoint_cost.gd"

func _lighting_sweep(before: Dictionary) -> void:
	preview.playing=false;preview.replay_target_tick=-1
	var mat:ShaderMaterial=preview.water_material
	var original:Shader=load("res://assets/water_material_natural_candidate/water_route_specialized.gdshader")
	var index:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/water_material_natural_candidate/water_reflection_specialized_index.json"))
	for key in index.constants:
		var actual:Variant=mat.get_shader_parameter(key)
		if actual==null:actual=RenderingServer.shader_get_parameter_default(original.get_rid(),key)
		if actual!=index.constants[key]:_fail("specialized geometry mismatch: "+key);return
	var parameters:={}
	for uniform in original.get_shader_uniform_list():
		var value:Variant=mat.get_shader_parameter(uniform.name)
		if value!=null:parameters[String(uniform.name)]=value
	var candidate:Shader=load("res://assets/water_material_natural_candidate/water_reflection_specialized.gdshader")
	var rid:=root.get_viewport_rid();RenderingServer.viewport_set_measure_render_time(rid,true)
	var rows:={}
	for id in ["original","specialized","original_end"]:
		mat.shader=original if id in ["original","original_end"] else candidate
		for key in parameters:mat.set_shader_parameter(key,parameters[key])
		preview.set_fixture_camera(&"close")
		for i in range(40):await process_frame;await RenderingServer.frame_post_draw
		var start:=Time.get_ticks_usec();var previous:=start;var frames:=[];var gpu:=[]
		while Time.get_ticks_usec()-start<3000000:
			await process_frame;await RenderingServer.frame_post_draw
			var now:=Time.get_ticks_usec();frames.append(float(now-previous)/1000.);previous=now
			gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(rid))
		var images:={}
		for cam in [&"close",&"oblique",&"grazing"]:
			preview.set_fixture_camera(cam)
			for i in range(8):await process_frame
			await RenderingServer.frame_post_draw
			var path:String=output+"/%s_%s.png"%[String(id),String(cam)]
			if root.get_texture().get_image().save_png(path)!=OK:_fail("lazy capture failed");return
			images[String(cam)]={"path":path,"sha256":FileAccess.get_sha256(path)}
		rows[id]={"frame_ms":frames,"gpu_render_ms":gpu,"elapsed_us":previous-start,"images":images,"shader":mat.shader.resource_path,"shader_sha256":FileAccess.get_sha256(mat.shader.resource_path),"parameters":Uniforms.material_values(mat),"tick":preview.completed_ticks,"visual_time_s":preview.visual_time_s}
	fields.clear();RenderingServer.call_on_render_thread(_read_fields)
	var deadline:=Time.get_ticks_msec()+10000
	while fields.size()<7:
		await process_frame
		if Time.get_ticks_msec()>deadline:_fail("lazy readback timeout");return
	var pairs:={}
	for name in fields:
		var ctx:=HashingContext.new();ctx.start(HashingContext.HASH_SHA256);ctx.update(fields[name])
		pairs[name]=ctx.finish().hex_encode()==before[name].sha256
		if not pairs[name]:_fail("lazy changed authority");return
	var file:=FileAccess.open(output+"/reflection_specialized.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"cases":rows,"authority_unchanged":pairs,"scope":"Same frozen common completed tick360; fixed geometry constant specialization only, not full cost/sequence/interaction acceptance."},"\t"));file.close()

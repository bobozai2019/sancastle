extends "res://tests/water_material_natural/optics_path_probe.gd"

func _lighting_sweep(before: Dictionary) -> void:
	var water:=preview.water_material as ShaderMaterial
	var fine: ShaderMaterial=preview.get_node("PrototypeFrontFoamDense").material_override
	var contact: ShaderMaterial=preview.get_node("ShoreContactOverlay").material_override
	var rows:={}
	for id in ["all_on","main_off","fine_off","contact_off","all_off","main_only","fine_only","contact_only"]:
		water.set_shader_parameter("natural_main_foam_gain",0.0 if id in ["main_off","all_off","fine_only","contact_only"] else 1.0)
		fine.set_shader_parameter("natural_fine_enabled",id not in ["fine_off","all_off","main_only","contact_only"])
		contact.set_shader_parameter("natural_contact_enabled",id not in ["contact_off","all_off","main_only","fine_only"])
		var images:={}
		for camera in [&"oblique",&"close",&"grazing"]:
			preview.set_fixture_camera(camera)
			for i in range(8):await process_frame
			await RenderingServer.frame_post_draw
			var path:String=output+"/%s_%s.png"%[id,String(camera)]
			root.get_texture().get_image().save_png(path)
			images[String(camera)]={"path":path,"sha256":FileAccess.get_sha256(path)}
		rows[id]={"images":images,"main_gain":water.get_shader_parameter("natural_main_foam_gain"),
			"fine_enabled":fine.get_shader_parameter("natural_fine_enabled"),"contact_enabled":contact.get_shader_parameter("natural_contact_enabled")}
	fields.clear();RenderingServer.call_on_render_thread(_read_fields)
	var deadline:=Time.get_ticks_msec()+10000
	while fields.size()<7:
		await process_frame
		if Time.get_ticks_msec()>deadline:_fail("foam layers readback timeout");return
	var same:={}
	for field in fields:
		var ctx:=HashingContext.new();ctx.start(HashingContext.HASH_SHA256);ctx.update(fields[field])
		same[field]=ctx.finish().hex_encode()==before[field].sha256
		if not same[field]:_fail("foam authority changed");return
	var file:=FileAccess.open(output+"/foam_layers.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"cases":rows,"fields_unchanged":same,"effective_foam":preview.effective_foam},"\t"));file.close()

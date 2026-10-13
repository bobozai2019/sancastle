extends "res://tests/water_material_natural/optics_path_probe.gd"

func _lighting_sweep(before: Dictionary) -> void:
	var water:=preview.water_material as ShaderMaterial
	var fine:ShaderMaterial=preview.get_node("PrototypeFrontFoamDense").material_override
	var contact:ShaderMaterial=preview.get_node("ShoreContactOverlay").material_override
	var zero_bytes:=PackedByteArray();zero_bytes.resize(256*256*4)
	var zero_image:=Image.create_from_data(256,256,false,Image.FORMAT_RF,zero_bytes)
	var zero:=ImageTexture.create_from_image(zero_image)
	var materials:=[water,fine,contact]
	var saved:=[]
	for material in materials:saved.append(_bindings(material))
	var rows:={}
	for id in ["baseline","static_inputs","fully_dry"]:
		for i in range(materials.size()):_restore(materials[i],saved[i])
		var replaced:=[]
		if id!="baseline":
			replaced=["foam_state","foam_previous_state","local_front_state","rise_front_state","momentum_x_state","momentum_z_state"]
			if id=="fully_dry":replaced.append("water_state")
			for material in materials:
				var names:=[]
				for u in material.shader.get_shader_uniform_list():names.append(String(u.name))
				for name in replaced:
					if name in names:material.set_shader_parameter(name,zero)
		var images:={}
		for mode in ["foam_on","foam_off"]:
			water.set_shader_parameter("natural_main_foam_gain",1. if mode=="foam_on" else 0.)
			fine.set_shader_parameter("natural_fine_enabled",mode=="foam_on")
			contact.set_shader_parameter("natural_contact_enabled",mode=="foam_on")
			for camera in [&"oblique",&"close",&"grazing"]:
				preview.set_fixture_camera(camera)
				for i in range(8):await process_frame
				await RenderingServer.frame_post_draw
				var path:String=output+"/%s_%s_%s.png"%[id,mode,String(camera)]
				root.get_texture().get_image().save_png(path)
				images["%s_%s"%[mode,String(camera)]]={"path":path,"sha256":FileAccess.get_sha256(path)}
		rows[id]={"images":images,"replaced_samplers":replaced,"water_uniforms":Uniforms.material_values(water),
			"fine_uniforms":Uniforms.material_values(fine),"contact_uniforms":Uniforms.material_values(contact)}
	for i in range(materials.size()):_restore(materials[i],saved[i])
	fields.clear();RenderingServer.call_on_render_thread(_read_fields)
	var deadline:=Time.get_ticks_msec()+10000
	while fields.size()<7:
		await process_frame
		if Time.get_ticks_msec()>deadline:_fail("negative input readback timeout");return
	var same:={}
	for name in fields:
		var ctx:=HashingContext.new();ctx.start(HashingContext.HASH_SHA256);ctx.update(fields[name])
		same[name]=ctx.finish().hex_encode()==before[name].sha256
		if not same[name]:_fail("input fixture changed authority");return
	var ctx:=HashingContext.new();ctx.start(HashingContext.HASH_SHA256);ctx.update(zero_bytes)
	var file:=FileAccess.open(output+"/foam_input_negatives.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"cases":rows,"fields_unchanged":same,"zero_texture_sha256":ctx.finish().hex_encode(),
		"zero_texture_format":"256x256 RF float32 zero; RG reads also zero",
		"scope":"Read-only renderer fixture replaces sampled fields, not a new solver state; does not prove physical static-water equilibrium."},"\t"));file.close()

extends "res://tests/water_material_natural/foam_sequence_probe.gd"

func _lighting_sweep(before: Dictionary) -> void:
	var water:=preview.water_material as ShaderMaterial
	var bed:=preview.terrain_material as ShaderMaterial
	var fine:ShaderMaterial=preview.get_node("PrototypeFrontFoamDense").material_override
	var contact:ShaderMaterial=preview.get_node("ShoreContactOverlay").material_override
	var rows:={}
	for id in ["all_on","caustics_off","glint_off","foam_off","reflection_off","all_features_off",
			"caustics_only","glint_only","foam_only","reflection_only","bed_only","depth_labels"]:
		var caustics:bool=id not in ["caustics_off","all_features_off","glint_only","foam_only","reflection_only"]
		var glint:bool=id in ["all_on","caustics_off","foam_off","reflection_off","glint_only"]
		var foam:bool=id in ["all_on","caustics_off","glint_off","reflection_off","foam_only"]
		var reflect:bool=id in ["all_on","caustics_off","glint_off","foam_off","reflection_only"]
		bed.set_shader_parameter("natural_caustic_enabled",caustics)
		water.set_shader_parameter("natural_glint_gain",preview.style_profile.glint.gain if glint else 0.)
		water.set_shader_parameter("natural_main_foam_gain",1. if foam else 0.)
		fine.set_shader_parameter("natural_fine_enabled",foam)
		contact.set_shader_parameter("natural_contact_enabled",foam)
		water.set_shader_parameter("natural_reflection_gain",1. if reflect else 0.)
		water.set_shader_parameter("natural_optics_debug",1 if id=="depth_labels" else 0)
		preview.get_node("GpuWaterSurface").visible=id!="bed_only"
		var images:={}
		for camera in [&"oblique",&"close",&"grazing"]:
			preview.set_fixture_camera(camera)
			for i in range(8):await process_frame
			await RenderingServer.frame_post_draw
			var path:String=output+"/%s_%s.png"%[id,String(camera)]
			root.get_texture().get_image().save_png(path)
			images[String(camera)]={"path":path,"sha256":FileAccess.get_sha256(path)}
		rows[id]={"images":images,"water_uniforms":Uniforms.material_values(water),"bed_uniforms":Uniforms.material_values(bed),
			"fine_enabled":fine.get_shader_parameter("natural_fine_enabled"),"contact_enabled":contact.get_shader_parameter("natural_contact_enabled")}
	var after:=await _hash_state();var same:={}
	for name in after:
		same[name]=after[name]==before[name].sha256
		if not same[name]:_fail("style layer authority changed");return
	var file:=FileAccess.open(output+"/style_layers.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"cases":rows,"fields_unchanged":same,"effective_style":preview.effective_style,
		"effective_reflection":preview.effective_reflection,"scope":"Four feature contributions at identical completed state; all_features_off retains ordinary water transmission/scatter and bed shading."},"\t"));file.close()

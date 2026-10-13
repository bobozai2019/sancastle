extends "res://tests/water_material_natural/foam_sequence_probe.gd"

func _lighting_sweep(before: Dictionary) -> void:
	var water:=preview.water_material as ShaderMaterial
	var fine:ShaderMaterial=preview.get_node("PrototypeFrontFoamDense").material_override
	var contact:ShaderMaterial=preview.get_node("ShoreContactOverlay").material_override
	var boxes:=[preview.get_node("ShadowOccluder"),preview.get_node("FoamShadowOccluder")]
	var material:StandardMaterial3D=boxes[0].material_override
	var original:=material.albedo_color
	var rows:={}
	for id in ["present_on","present_off","mask","hidden_on","hidden_off"]:
		var on:bool=id.ends_with("_on")
		for box in boxes:box.visible=not id.begins_with("hidden")
		material.albedo_color=Color(.9,.02,.7,1.) if id=="mask" else original
		water.set_shader_parameter("natural_main_foam_gain",1. if on else 0.)
		fine.set_shader_parameter("natural_fine_enabled",on)
		contact.set_shader_parameter("natural_contact_enabled",on)
		var images:={}
		for camera in [&"oblique",&"close",&"grazing"]:
			preview.set_fixture_camera(camera)
			for i in range(8):await process_frame
			await RenderingServer.frame_post_draw
			var path:String=output+"/%s_%s.png"%[id,String(camera)]
			root.get_texture().get_image().save_png(path)
			images[String(camera)]={"path":path,"sha256":FileAccess.get_sha256(path)}
		rows[id]=images
	var after:=await _hash_state()
	var same:={}
	for name in after:
		same[name]=after[name]==before[name].sha256
		if not same[name]:_fail("occluder authority changed");return
	var file:=FileAccess.open(output+"/foam_occluder.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"cases":rows,"fields_unchanged":same,"scope":"Two pre-saved opaque sand-colored 5m boxes; renderer high-occluder surrogate, no physical sand editing or collision changes."},"\t"));file.close()

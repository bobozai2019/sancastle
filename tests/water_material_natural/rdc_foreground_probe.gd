extends "res://tests/water_material_natural/foam_sequence_probe.gd"

func _lighting_sweep(before: Dictionary) -> void:
	var water:ShaderMaterial=preview.water_material
	var boxes:=[preview.get_node("ShadowOccluder"),preview.get_node("FoamShadowOccluder")]
	var marker:StandardMaterial3D=boxes[0].material_override
	var original:=marker.albedo_color
	var gain:float=water.get_shader_parameter("rdc_surface_gain")
	var rows:={}
	for id in ["present_on","present_off","mask","hidden_on","hidden_off"]:
		for box in boxes:box.visible=not id.begins_with("hidden")
		marker.albedo_color=Color(.9,.02,.7,1.) if id=="mask" else original
		water.set_shader_parameter("rdc_surface_gain",1. if id.ends_with("_on") else 0.)
		water.set_shader_parameter("natural_main_foam_gain",0.)
		preview.get_node("PrototypeFrontFoamDense").visible=false
		preview.get_node("ShoreContactOverlay").visible=false
		var images:={}
		for cam in [&"close",&"oblique",&"grazing"]:
			preview.set_fixture_camera(cam)
			for frame in range(6):await process_frame
			await RenderingServer.frame_post_draw
			var path:String=output+"/%s_%s.png"%[id,String(cam)]
			root.get_texture().get_image().save_png(path)
			images[String(cam)]={"path":path,"sha256":FileAccess.get_sha256(path)}
		rows[id]=images
	var after:=await _hash_state();var same:={}
	for name in after:
		same[name]=after[name]==before[name].sha256
		if not same[name]:_fail("RDC foreground changed authority");return
	water.set_shader_parameter("rdc_surface_gain",gain)
	var file:=FileAccess.open(output+"/reflection_foreground.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"cases":rows,"fields_unchanged":same,"scope":"New RDC surface gain only, actual occluding opaque boxes; seven authority fields unchanged. Existing foreground audit applies."},"\t"));file.close()

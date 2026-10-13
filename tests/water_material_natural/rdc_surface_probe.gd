extends "res://tests/water_material_natural/rdc_factor_probe.gd"

func _lighting_sweep(_before: Dictionary) -> void:
	preview.playing=false;preview.replay_target_tick=-1
	var before:=await _hash_state()
	var water:ShaderMaterial=preview.water_material
	var color:Vector3=water.get_shader_parameter("rdc_surface_color")
	var gain:float=water.get_shader_parameter("rdc_surface_gain")
	var env:Environment=preview.get_node("WorldEnvironment").environment
	var background:=env.background_color.srgb_to_linear()
	var sky:=Vector3(background.r,background.g,background.b)
	var rows:=[]
	for id in ["captured_color","sky_color","half_surface","sky_half_surface"]:
		water.set_shader_parameter("rdc_surface_color",sky if id.begins_with("sky") else color)
		water.set_shader_parameter("rdc_surface_gain",.5 if "half" in id else gain)
		var images:={}
		for cam in [&"close",&"oblique",&"grazing"]:
			preview.set_fixture_camera(cam)
			for frame in range(6):await process_frame
			await RenderingServer.frame_post_draw
			var path:String=output+"/%s_%s.png"%[id,String(cam)]
			root.get_texture().get_image().save_png(path)
			images[String(cam)]={"path":path,"sha256":FileAccess.get_sha256(path)}
		rows.append({"id":id,"color":var_to_str(water.get_shader_parameter("rdc_surface_color")),"gain":water.get_shader_parameter("rdc_surface_gain"),"images":images})
	water.set_shader_parameter("rdc_surface_color",color);water.set_shader_parameter("rdc_surface_gain",gain)
	var after:=await _hash_state()
	if before!=after:_fail("surface comparison changed authority");return
	preview._seal_test1_effective_profile()
	var file:=FileAccess.open(output+"/surface_cases.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"cases":rows,"authority_unchanged":true,"before":before,"after":after,"sky_linear":var_to_str(sky)},"\t"));file.close()

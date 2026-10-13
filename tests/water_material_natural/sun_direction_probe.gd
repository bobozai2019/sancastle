extends "res://tests/water_material_natural/capture.gd"

func _lighting_sweep(before: Dictionary) -> void:
	var water:=preview.water_material as ShaderMaterial
	var original0:Vector4=water.get_shader_parameter("natural_layer0")
	var original1:Vector4=water.get_shader_parameter("natural_layer1")
	var cases:={"azimuth35":{"azimuth":35.},"azimuth145":{"azimuth":145.},
		"azimuth215":{"azimuth":215.},"azimuth285":{"azimuth":285.}}
	var rows:={}
	for id in cases:
		var c:Dictionary=cases[id]
		preview.get_node("SandFixtureSun").rotation_degrees=Vector3(-52.,c.azimuth,0.)
		preview._sync_sun()
		water.set_shader_parameter("natural_glint_enabled",c.get("enabled",true))
		water.set_shader_parameter("natural_glint_gain",c.get("gain",.32))
		water.set_shader_parameter("natural_glint_exponent",c.get("exponent",42.))
		var layer0:=original0;var layer1:=original1
		layer0.z*=c.get("detail_multiplier",1.)
		layer1.z*=c.get("detail_multiplier",1.)
		water.set_shader_parameter("natural_layer0",layer0)
		water.set_shader_parameter("natural_layer1",layer1)
		var images:={}
		for debug in [0,1]:
			water.set_shader_parameter("natural_lighting_debug",debug)
			preview.get_node("PrototypeFrontFoamDense").visible=debug==0
			preview.get_node("ShoreContactOverlay").visible=debug==0
			for camera in [&"oblique",&"close",&"grazing",&"sunward"]:
				if camera==&"sunward":
					var marker:Camera3D=preview.get_node("CameraAnchors/LightFacing")
					preview.overview_camera.global_transform=marker.global_transform
					preview.overview_camera.fov=marker.fov
				else:preview.set_fixture_camera(camera)
				for i in range(8):await process_frame
				await RenderingServer.frame_post_draw
				var path:String=output+"/%s_debug%d_%s.png"%[id,debug,String(camera)]
				root.get_texture().get_image().save_png(path)
				images["%d_%s"%[debug,String(camera)]]={"path":path,"sha256":FileAccess.get_sha256(path),
					"camera_transform":var_to_str(preview.overview_camera.global_transform),"fov":preview.overview_camera.fov}
		rows[id]={"images":images,"changes":c,"uniforms":Uniforms.material_values(water)}
	fields.clear();RenderingServer.call_on_render_thread(_read_fields)
	var deadline:=Time.get_ticks_msec()+10000
	while fields.size()<7:
		await process_frame
		if Time.get_ticks_msec()>deadline:_fail("glint factor readback timeout");return
	var same:={}
	for name in fields:
		var ctx:=HashingContext.new();ctx.start(HashingContext.HASH_SHA256);ctx.update(fields[name])
		same[name]=ctx.finish().hex_encode()==before[name].sha256
		if not same[name]:_fail("glint factor authority changed");return
	var file:=FileAccess.open(output+"/sun_direction_factors.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"cases":rows,"fields_unchanged":same,"sun_transform":var_to_str(preview.get_node("SandFixtureSun").global_transform),
		"scope":"Sun gain/exponent and fine-normal gain separately; sunward diagnostic camera is additional to the three acceptance cameras."},"\t"));file.close()

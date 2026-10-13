extends "res://tests/water_material_natural/capture.gd"

func _lighting_sweep(before: Dictionary) -> void:
	var cases := {}
	for enabled in [false,true]:
		preview.set_shadow_proxy(enabled)
		preview.get_node("PrototypeFrontFoamDense").visible = false
		var images := {}
		for debug in [0,2]:
			preview.water_material.set_shader_parameter("natural_lighting_debug",debug)
			for camera in [&"oblique", &"close", &"grazing", &"sunward"]:
				preview.set_fixture_camera(camera)
				for i in range(8): await process_frame
				await RenderingServer.frame_post_draw
				var path: String = output + "/%s_debug%d_%s.png" % ["proxy" if enabled else "native",debug,String(camera)]
				if root.get_texture().get_image().save_png(path)!=OK:
					_fail("proxy shadow capture failure")
					return
				images["%d_%s" % [debug,String(camera)]]={"path":path,"sha256":FileAccess.get_sha256(path)}
		cases["proxy" if enabled else "native"]={"images":images,"terrain_cast_mode":preview.get_node("GpuSandTerrain").cast_shadow,
			"proxy_cast_mode":preview.get_node("TerrainShadowProxy").cast_shadow,
			"proxy_transform":str(preview.get_node("TerrainShadowProxy").global_transform),
			"visible_terrain_transform":str(preview.get_node("GpuSandTerrain").global_transform)}
	var file := FileAccess.open(output+"/proxy_ablation.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"cases":cases,"tick":preview.completed_ticks,
		"revision":preview.solver.state_revision,"generation":preview.generation,
		"clock":preview.visual_time_s,"mesh_sha256":FileAccess.get_sha256(preview.lighting_profile.shadow_proxy_mesh),
		"scope":"native directional shadows; only terrain shadow caster mesh density changed"},"\t"))
	file.close()

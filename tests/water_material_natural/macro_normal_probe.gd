extends "res://tests/water_material_natural/foam_sequence_probe.gd"

func _lighting_sweep(before: Dictionary) -> void:
	var water: ShaderMaterial = preview.water_material
	water.shader = load("res://assets/water_material_natural_candidate/water_macro.gdshader")
	var rows := {}
	for mode in [0,4]:
		water.set_shader_parameter("natural_macro_normal_mode",mode)
		for detail in [true,false]:
			water.set_shader_parameter("use_detail_normals",detail)
			for debug in [0,1]:
				water.set_shader_parameter("natural_normal_debug",debug)
				var id: String = "mode%d_detail%d_debug%d" % [mode,int(detail),debug]
				var images := {}
				for camera in [&"oblique",&"close",&"grazing"]:
					preview.set_fixture_camera(camera)
					for i in range(8): await process_frame
					await RenderingServer.frame_post_draw
					var path: String = output + "/%s_%s.png" % [id,String(camera)]
					root.get_texture().get_image().save_png(path)
					images[String(camera)] = {"path":path,"sha256":FileAccess.get_sha256(path)}
				rows[id] = {"images":images,"water_shader":water.shader.resource_path,
					"water_shader_sha256":FileAccess.get_sha256(water.shader.resource_path),
					"water_uniforms":Uniforms.material_values(water)}
	var after := await _hash_state()
	var same := {}
	for name in after:
		same[name] = after[name] == before[name].sha256
		if not same[name]: _fail("macro normal probe authority changed"); return
	var file := FileAccess.open(output + "/macro_normal_cases.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"cases":rows,"fields_unchanged":same,
		"scope":"One macro-normal algorithm and one detail toggle at a time. mode0 should match direct profile; all vertex code preserved."},"\t"));file.close()

extends "res://tests/water_material_natural/foam_sequence_probe.gd"

func _lighting_sweep(before: Dictionary) -> void:
	var water: ShaderMaterial = preview.water_material
	var saved := {}
	for name in ["natural_scatter_direct_fraction","natural_path_mode","prototype_refraction_scale","natural_reflection_gain"]:
		saved[name] = water.get_shader_parameter(name)
	var rows := {}
	for mode in ["all_on","scatter_emission","vertical_path","refraction_zero","reflection_zero","normal_debug","path_debug","path_flags"]:
		for name in saved: water.set_shader_parameter(name,saved[name])
		water.set_shader_parameter("natural_normal_debug",1 if mode == "normal_debug" else 0)
		water.set_shader_parameter("natural_optics_debug",2 if mode == "path_debug" else (3 if mode == "path_flags" else 0))
		water.set_shader_parameter("natural_scatter_direct_fraction",0. if mode == "scatter_emission" else saved.natural_scatter_direct_fraction)
		water.set_shader_parameter("natural_path_mode",0 if mode == "vertical_path" else saved.natural_path_mode)
		water.set_shader_parameter("prototype_refraction_scale",0. if mode == "refraction_zero" else saved.prototype_refraction_scale)
		water.set_shader_parameter("natural_reflection_gain",0. if mode == "reflection_zero" else saved.natural_reflection_gain)
		var images := {}
		for camera in [&"oblique",&"close",&"grazing"]:
			preview.set_fixture_camera(camera)
			for i in range(8): await process_frame
			await RenderingServer.frame_post_draw
			var path: String = output + "/%s_%s.png" % [mode,String(camera)]
			root.get_texture().get_image().save_png(path)
			images[String(camera)] = {"path":path,"sha256":FileAccess.get_sha256(path)}
		rows[mode] = {"images":images,"water_uniforms":Uniforms.material_values(water)}
	var after := await _hash_state()
	var same := {}
	for name in after:
		same[name] = after[name] == before[name].sha256
		if not same[name]: _fail("seam component authority changed"); return
	var file := FileAccess.open(output + "/seam_components.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"cases":rows,"fields_unchanged":same,
		"scope":"One visual factor at a time; debug shows actual final normals, reconstructed path and protection flags."},"\t"));file.close()

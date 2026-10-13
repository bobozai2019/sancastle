extends "res://tests/water_material_natural/foam_sequence_probe.gd"

func _lighting_sweep(before: Dictionary) -> void:
	var water: ShaderMaterial = preview.water_material
	var bed: ShaderMaterial = preview.terrain_material
	var fine: ShaderMaterial = preview.get_node("PrototypeFrontFoamDense").material_override
	var contact_node: MeshInstance3D = preview.get_node("ShoreContactOverlay")
	var contact: ShaderMaterial = contact_node.material_override
	var shader := water.shader
	var sun: DirectionalLight3D = preview.get_node("SandFixtureSun")
	var values := {}
	for u in shader.get_shader_uniform_list(): values[String(u.name)] = water.get_shader_parameter(u.name)
	var legacy: Shader = load("res://assets/test1_beach/test1_water_front.gdshader")
	var rows := {}
	for mode in ["all_on", "contact_no_cast", "shadow_off", "features_off", "detail_off", "legacy_water"]:
		water.shader = legacy if mode == "legacy_water" else shader
		for name in values:
			if values[name] != null: water.set_shader_parameter(name, values[name])
		contact_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if mode == "contact_no_cast" else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		sun.shadow_enabled = mode != "shadow_off"
		var features: bool = mode in ["all_on", "contact_no_cast", "shadow_off", "legacy_water"]
		bed.set_shader_parameter("natural_caustic_enabled", features)
		if mode != "legacy_water":
			water.set_shader_parameter("natural_glint_gain", preview.style_profile.glint.gain if features else 0.)
			water.set_shader_parameter("natural_reflection_gain", 1. if features else 0.)
			water.set_shader_parameter("natural_main_foam_gain", 1. if features else 0.)
			water.set_shader_parameter("use_detail_normals", mode != "detail_off")
		fine.set_shader_parameter("natural_fine_enabled", features)
		contact.set_shader_parameter("natural_contact_enabled", features)
		var images := {}
		for camera in [&"oblique", &"close", &"grazing"]:
			preview.set_fixture_camera(camera)
			for i in range(8): await process_frame
			await RenderingServer.frame_post_draw
			var path: String = output + "/%s_%s.png" % [mode,String(camera)]
			root.get_texture().get_image().save_png(path)
			images[String(camera)] = {"path":path,"sha256":FileAccess.get_sha256(path)}
		rows[mode] = {"images":images,"water_shader":water.shader.resource_path,
			"water_uniforms":Uniforms.material_values(water),"contact_cast_shadow":contact_node.cast_shadow,
			"sun_shadow_enabled":sun.shadow_enabled}
	var after := await _hash_state()
	var same := {}
	for name in after:
		same[name] = after[name] == before[name].sha256
		if not same[name]: _fail("seam probe authority changed"); return
	var file := FileAccess.open(output + "/seam_cases.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"cases":rows,"fields_unchanged":same,
		"scope":"Fixed completed state dark-line attribution. legacy_water changes only water shader, retaining candidate light/bed/fine/contact; not complete original-scene baseline."},"\t"));file.close()

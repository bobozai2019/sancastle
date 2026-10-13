extends "res://tests/water_material_natural/capture.gd"

func _lighting_sweep(before: Dictionary) -> void:
	var sun: DirectionalLight3D = preview.get_node("SandFixtureSun")
	var water: MeshInstance3D = preview.get_node("GpuWaterSurface")
	var dense: MeshInstance3D = preview.get_node("PrototypeFrontFoamDense")
	var foam: ShaderMaterial = dense.material_override
	var cases := {}
	for id in ["all_off", "scatter_only", "foam_only", "direct_only", "shadow_on", "shadow_off", "caster_hidden", "glint_only", "glint_shadow"]:
		sun.shadow_enabled = id in ["shadow_on", "caster_hidden", "glint_shadow"]
		for name in ["ShadowOccluder", "FoamShadowOccluder"]:
			preview.get_node(name).visible = id != "caster_hidden"
		var fraction: float = 0.0 if id in ["all_off", "glint_only", "glint_shadow", "foam_only"] else 0.45
		var foam_fraction: float = 0.0 if id in ["all_off", "glint_only", "glint_shadow", "scatter_only"] else 0.50
		preview.water_material.set_shader_parameter("natural_scatter_direct_fraction", fraction)
		preview.water_material.set_shader_parameter("natural_foam_direct_fraction", foam_fraction)
		preview.water_material.set_shader_parameter("natural_glint_enabled", id in ["glint_only", "glint_shadow"])
		foam.set_shader_parameter("natural_foam_direct_fraction", foam_fraction)
		var images := {}
		for layer in ["combined", "water_only", "foam_only", "fine_hidden"]:
			water.visible = layer in ["combined", "water_only"]
			dense.visible = layer in ["combined", "foam_only"]
			for debug in [0,1,2,3,4]:
				if layer == "combined" and debug != 0: continue
				if layer == "foam_only" and debug not in [0,2]: continue
				if layer == "fine_hidden" and debug != 0: continue
				preview.water_material.set_shader_parameter("natural_lighting_debug", debug)
				foam.set_shader_parameter("natural_lighting_debug", 2 if debug == 2 else 0)
				for camera in [&"oblique", &"close", &"grazing", &"sunward"]:
					preview.set_fixture_camera(camera)
					for i in range(8): await process_frame
					await RenderingServer.frame_post_draw
					var path: String = output + "/%s_%s_debug%d_%s.png" % [String(id), String(layer), debug, String(camera)]
					if root.get_texture().get_image().save_png(path) != OK:
						_fail("shadow sweep capture failure")
						return
					images["%s_%d_%s" % [String(layer), debug, String(camera)]] = {"path":path,"sha256":FileAccess.get_sha256(path)}
		cases[id] = {"images":images,"water_uniforms":Uniforms.material_values(preview.water_material),
			"foam_uniforms":Uniforms.material_values(foam),"shadow_enabled":sun.shadow_enabled,
			"casters_visible":id != "caster_hidden","sun_direction":str(sun.global_basis.z.normalized())}
	fields.clear()
	RenderingServer.call_on_render_thread(_read_fields)
	var deadline := Time.get_ticks_msec() + 10000
	while fields.size() < 7:
		await process_frame
		if Time.get_ticks_msec() > deadline:
			_fail("shadow sweep readback timeout")
			return
	var identical := {}
	for field in fields:
		var ctx := HashingContext.new()
		ctx.start(HashingContext.HASH_SHA256);ctx.update(fields[field])
		identical[field] = ctx.finish().hex_encode() == before[field].sha256
		if not identical[field]:
			_fail("shadow sweep authority changed")
			return
	var file := FileAccess.open(output + "/shadow_ablation.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"cases":cases,"authority_identical":identical,
		"tick":preview.completed_ticks,"generation":preview.generation,"revision":preview.solver.state_revision,
		"clock":preview.visual_time_s,"scope":"engine light shader, actual directional shadow attenuation and independent layer contributions"},"\t"))
	file.close()

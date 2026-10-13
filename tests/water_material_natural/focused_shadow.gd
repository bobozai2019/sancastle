extends "res://tests/water_material_natural/capture.gd"

func _lighting_sweep(before: Dictionary) -> void:
	var sun: DirectionalLight3D = preview.get_node("SandFixtureSun")
	var water: MeshInstance3D = preview.get_node("GpuWaterSurface")
	var dense: MeshInstance3D = preview.get_node("PrototypeFrontFoamDense")
	var foam: ShaderMaterial = dense.material_override
	var cases := {}
	preview.set_fixture_camera(&"grazing")
	water.visible = false
	for id in ["shadow_off", "shadow_on", "caster_hidden"]:
		sun.shadow_enabled = id != "shadow_off"
		for name in ["ShadowOccluder", "FoamShadowOccluder"]: preview.get_node(name).visible = id != "caster_hidden"
		var images := {}
		for layer in ["foam_only", "fine_hidden"]:
			dense.visible = layer == "foam_only"
			for debug in [0,2]:
				if layer == "fine_hidden" and debug != 0: continue
				foam.set_shader_parameter("natural_lighting_debug",debug)
				for i in range(8): await process_frame
				await RenderingServer.frame_post_draw
				var path: String = output + "/%s_%s_debug%d_grazing.png" % [String(id),String(layer),debug]
				if root.get_texture().get_image().save_png(path) != OK:
					_fail("grazing shadow capture failure")
					return
				images["%s_%d_grazing" % [String(layer),debug]] = {"path":path,"sha256":FileAccess.get_sha256(path)}
		cases[id] = {"images":images,"shadow_enabled":sun.shadow_enabled,"foam_uniforms":Uniforms.material_values(foam)}
	var file := FileAccess.open(output + "/shadow_ablation.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"cases":cases,"tick":preview.completed_ticks,
		"revision":preview.solver.state_revision,"generation":preview.generation,
		"scope":"grazing fine-foam core; only strengthened opaque caster fixture, no material or authority change"},"\t"))
	file.close()

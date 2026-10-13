extends "res://tests/water_material_natural/optics_path_probe.gd"

func _lighting_sweep(before: Dictionary) -> void:
	# Reuse the native/legacy/reconstructed regression and diagnostics first.
	# Restore the selected unbent path explicitly after this diagnostic helper.
	var water := preview.water_material as ShaderMaterial
	var shader := water.shader
	var values := _bindings(water)
	await super._lighting_sweep(before)
	water.shader = shader
	_restore(water,values)
	water.set_shader_parameter("natural_optics_debug",0)
	var rows := {}
	for id in ["selected","bed_only"]:
		preview.get_node("GpuWaterSurface").visible = id == "selected"
		preview.get_node("PrototypeFrontFoamDense").visible = id == "selected"
		preview.get_node("ShoreContactOverlay").visible = id == "selected"
		var images := {}
		for camera in [&"oblique",&"close",&"grazing"]:
			preview.set_fixture_camera(camera)
			for i in range(8): await process_frame
			await RenderingServer.frame_post_draw
			var path: String = output + "/%s_%s.png" % [id,String(camera)]
			root.get_texture().get_image().save_png(path)
			images[String(camera)]={"path":path,"sha256":FileAccess.get_sha256(path)}
		rows[id]=images
	var file := FileAccess.open(output+"/optics_final.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"images":rows,"effective_optics":preview.effective_optics,"selected_uniforms":values},"\t"));file.close()

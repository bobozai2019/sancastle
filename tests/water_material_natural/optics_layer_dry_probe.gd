extends "res://tests/water_material_natural/optics_path_probe.gd"

func _lighting_sweep(before: Dictionary) -> void:
	var water := preview.water_material as ShaderMaterial
	var rows := {}
	for id in ["all_on","water_only","foam_only","contact_only","bed_only","depth_labels"]:
		preview.get_node("GpuWaterSurface").visible = id in ["all_on","water_only","depth_labels"]
		preview.get_node("PrototypeFrontFoamDense").visible = id in ["all_on","foam_only"]
		preview.get_node("ShoreContactOverlay").visible = id in ["all_on","contact_only"]
		water.set_shader_parameter("natural_optics_debug",1 if id == "depth_labels" else 0)
		var images := {}
		for camera in [&"oblique",&"close",&"grazing"]:
			preview.set_fixture_camera(camera)
			for i in range(8): await process_frame
			await RenderingServer.frame_post_draw
			var path: String = output + "/%s_%s.png" % [id,String(camera)]
			root.get_texture().get_image().save_png(path)
			images[String(camera)]={"path":path,"sha256":FileAccess.get_sha256(path)}
		rows[id]=images
	fields.clear();RenderingServer.call_on_render_thread(_read_fields)
	var deadline := Time.get_ticks_msec()+10000
	while fields.size()<7:
		await process_frame
		if Time.get_ticks_msec()>deadline: _fail("layer dry readback timeout"); return
	var same := {}
	for field in fields:
		var ctx := HashingContext.new();ctx.start(HashingContext.HASH_SHA256);ctx.update(fields[field])
		same[field]=ctx.finish().hex_encode()==before[field].sha256
		if not same[field]: _fail("layer dry authority changed"); return
	var file := FileAccess.open(output+"/layer_dry.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"images":rows,"effective_optics":preview.effective_optics,"fields_unchanged":same},"\t"));file.close()

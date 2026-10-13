extends "res://tests/water_material_natural/reflection_foreground_probe.gd"

func _lighting_sweep(before: Dictionary) -> void:
	await super._lighting_sweep(before)
	if probe_failed:return
	var water:ShaderMaterial=preview.water_material
	var mesh:MeshInstance3D=preview.get_node("GpuWaterSurface")
	for name in ["ShadowOccluder","FoamShadowOccluder"]:preview.get_node(name).visible=true
	preview.get_node("ShadowOccluder").material_override.albedo_color=Color(.9,.02,.7,1.)
	water.set_shader_parameter("natural_glint_enabled",false)
	var rows:={}
	for id in ["marker_water_on","marker_water_hidden","water_normal_coverage"]:
		mesh.visible=id!="marker_water_hidden"
		water.set_shader_parameter("natural_normal_debug",1 if id=="water_normal_coverage" else 0)
		var images:={}
		for cam in [&"close",&"oblique",&"grazing"]:
			preview.set_fixture_camera(cam)
			for frame in range(8):await process_frame
			await RenderingServer.frame_post_draw
			var path:String=output+"/%s_%s.png"%[id,String(cam)]
			root.get_texture().get_image().save_png(path)
			images[String(cam)]={"path":path,"sha256":FileAccess.get_sha256(path)}
		rows[id]=images
	var after:=await _hash_state()
	for key in after:
		if after[key]!=before[key].sha256:_fail("foreground coverage changed authority");return
	var file:=FileAccess.open(output+"/foreground_coverage.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"cases":rows,"fields_unchanged":true,"scope":"Supplement old RGB surrogate mask with actual water visibility and normal-debug raster coverage. Diagnose pixel599,718; do not relax original FAIL."},"\t"));file.close()

extends "res://tests/water_material_natural/foam_sequence_probe.gd"

func _lighting_sweep(_before: Dictionary) -> void:
	preview.playing=false;preview.replay_target_tick=-1
	var before:=await _hash_state()
	var water:ShaderMaterial=preview.water_material
	var bed:ShaderMaterial=preview.terrain_material
	var cases:=[{"id":"selected","material":"water","values":{}},
		{"id":"refracted_path","material":"water","values":{"rdc_refracted_path":true}},
		{"id":"no_refraction","material":"water","values":{"rdc_refraction_scale":0.}},
		{"id":"half_absorption","material":"water","values":{"rdc_distance_scale":0.5}},
		{"id":"old_optics","material":"water","values":{"rdc_optics_enabled":false}},
		{"id":"old_normal","material":"water","values":{"rdc_normal_enabled":false}},
		{"id":"no_caustics","material":"bed","values":{"natural_caustic_enabled":false}},
		{"id":"old_caustics","material":"bed","values":{"rdc_caustics_enabled":false}},
		{"id":"no_surface","material":"water","values":{"rdc_surface_gain":0.}},
		{"id":"no_glint","material":"water","values":{"natural_glint_enabled":false}},
		{"id":"depth_tags","material":"water","values":{"natural_optics_debug":1}},
		{"id":"transmission_rgb","material":"water","values":{"natural_optics_debug":4}}]
	var rows:=[]
	for item in cases:
		var material:ShaderMaterial=bed if item.material=="bed" else water
		var saved:={}
		for key in item.values:saved[key]=material.get_shader_parameter(key);material.set_shader_parameter(key,item.values[key])
		var images:={}
		for cam in [&"close",&"oblique",&"grazing"]:
			preview.set_fixture_camera(cam)
			for frame in range(6):await process_frame
			await RenderingServer.frame_post_draw
			var path:String=output+"/%s_%s.png"%[item.id,String(cam)]
			if root.get_texture().get_image().save_png(path)!=OK:_fail("RDC factor capture failed");return
			images[String(cam)]={"path":path,"sha256":FileAccess.get_sha256(path)}
		rows.append({"id":item.id,"changed_uniforms":item.values,"images":images})
		for key in saved:material.set_shader_parameter(key,saved[key])
	var after:=await _hash_state()
	if before!=after:_fail("RDC display changed authority");return
	preview._seal_test1_effective_profile()
	if not preview.last_error.is_empty():_fail("RDC controls did not restore");return
	var file:=FileAccess.open(output+"/rdc_factors.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"cases":rows,"before":before,"after":after,"authority_unchanged":true,"tick":preview.completed_ticks,"generation":preview.generation,"visual_time_s":preview.visual_time_s,"effective_rdc":preview.effective_style.rdc_material},"\t"));file.close()

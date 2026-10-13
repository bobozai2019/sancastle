extends "res://tests/water_material_natural/foam_sequence_probe.gd"

func _lighting_sweep(_before: Dictionary) -> void:
	preview.playing=false;preview.replay_target_tick=-1
	var before:=await _hash_state();var rows:={}
	var water:ShaderMaterial=preview.water_material;var bed:ShaderMaterial=preview.terrain_material
	for id in ["normal_zero","detail_off","caustic_zero","caustic_off","selected"]:
		water.set_shader_parameter("rdc_normal_gain",0. if id=="normal_zero" else 1.)
		water.set_shader_parameter("use_detail_normals",id!="detail_off")
		bed.set_shader_parameter("natural_caustic_strength",0. if id=="caustic_zero" else .8)
		bed.set_shader_parameter("natural_caustic_enabled",id!="caustic_off")
		var images:={}
		for cam in [&"close",&"oblique",&"grazing"]:
			preview.set_fixture_camera(cam)
			for frame in range(6):await process_frame
			await RenderingServer.frame_post_draw
			var path:String=output+"/%s_%s.png"%[id,String(cam)]
			root.get_texture().get_image().save_png(path);images[String(cam)]={"path":path,"sha256":FileAccess.get_sha256(path)}
		rows[id]=images
	var after:=await _hash_state()
	if before!=after:_fail("RDC zero controls changed authority");return
	preview._seal_test1_effective_profile()
	if not preview.last_error.is_empty():_fail("RDC zero controls did not restore");return
	var f:=FileAccess.open(output+"/rdc_zero.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"cases":rows,"authority_unchanged":true,"before":before,"after":after},"\t"));f.close()

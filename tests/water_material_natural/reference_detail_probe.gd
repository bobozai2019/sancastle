extends "res://tests/water_material_natural/foam_sequence_probe.gd"

func _lighting_sweep(_before: Dictionary) -> void:
	preview.playing=false;preview.replay_target_tick=-1
	var before:=await _hash_state()
	var water:ShaderMaterial=preview.water_material
	var layers:=[water.get_shader_parameter("natural_layer0"),water.get_shader_parameter("natural_layer1")]
	var sun:DirectionalLight3D=preview.get_node("SandFixtureSun")
	var rotation:=sun.rotation_degrees
	var fine:Node3D=preview.get_node("PrototypeFrontFoamDense")
	var contact:Node3D=preview.get_node("ShoreContactOverlay")
	var fine_visible:=fine.visible;var contact_visible:=contact.visible
	var rows:=[]
	for id in _cases():
		sun.rotation_degrees=Vector3(rotation.x,_azimuth(id,rotation.y),rotation.z)
		preview._sync_sun()
		for i in range(2):
			var layer:Vector4=layers[i]
			layer.x*=_frequency(id)
			water.set_shader_parameter("natural_layer%d"%i,layer)
		var original_exponent:float=water.get_shader_parameter("natural_glint_exponent")
		var original_gain:float=water.get_shader_parameter("natural_glint_gain")
		water.set_shader_parameter("natural_glint_exponent",_exponent(id,original_exponent))
		water.set_shader_parameter("natural_glint_gain",_gain(id,original_gain))
		var images:={}
		for debug in [0,1]:
			water.set_shader_parameter("natural_lighting_debug",debug)
			fine.visible=fine_visible and debug==0;contact.visible=contact_visible and debug==0
			for cam in [&"close",&"oblique",&"grazing"]:
				preview.set_fixture_camera(cam)
				for frame in range(8):await process_frame
				await RenderingServer.frame_post_draw
				var path:String=output+"/%s_debug%d_%s.png"%[id,debug,String(cam)]
				if root.get_texture().get_image().save_png(path)!=OK:_fail("reference detail capture failed");return
				images["%d_%s"%[debug,String(cam)]]={"path":path,"sha256":FileAccess.get_sha256(path)}
		rows.append({"id":id,"sun_rotation":var_to_str(sun.rotation_degrees),"images":images,"uniforms":Uniforms.material_values(water)})
		water.set_shader_parameter("natural_glint_exponent",original_exponent)
		water.set_shader_parameter("natural_glint_gain",original_gain)
	for i in range(2):water.set_shader_parameter("natural_layer%d"%i,layers[i])
	sun.rotation_degrees=rotation;preview._sync_sun()
	water.set_shader_parameter("natural_lighting_debug",0)
	fine.visible=fine_visible;contact.visible=contact_visible
	var after:=await _hash_state()
	if before!=after:_fail("reference detail display changed authority");return
	if not preview._validate_compiled_inputs():_fail("reference detail did not restore compiled inputs");return
	var file:=FileAccess.open(output+"/reference_detail.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"cases":rows,"before":before,"after":after,"tick":preview.completed_ticks,"visual_time_s":preview.visual_time_s,"scope":"Declared cases alter sun azimuth, normal frequency, exponent or gain. Compare successive cases differing in one factor; combinations are additional candidates, not proof of individual causes. No color/geometry/physics change. Debug1 isolates directional glint; original controls restored."},"\t"));file.close()

func _cases() -> Array:
	return ["baseline","frequency2","frequency4","sun145"]

func _azimuth(id: String,original: float) -> float:
	return 145.0 if id=="sun145" else original

func _frequency(id: String) -> float:
	return 2.0 if id=="frequency2" else (4.0 if id=="frequency4" else 1.0)

func _exponent(_id: String,original: float) -> float:
	return original

func _gain(_id: String,original: float) -> float:
	return original

extends "res://tests/visual_water_alignment/foam_authority_switch_probe.gd"

func _advance(count: int) -> void:
	for i in count:
		var before: int=scene.runtime.current.completed_tick
		check("tick_admitted_"+str(checks.size()),scene.runtime.request_tick(1.0/30.0).is_empty())
		await _wait_tick()
		check("tick_completed_once_"+str(checks.size()),scene.runtime.current.completed_tick==before+1)

func _swap(material: ShaderMaterial, shader: Shader, defaults: Dictionary) -> void:
	var current:={}
	for uniform in material.shader.get_shader_uniform_list():current[uniform.name]=material.get_shader_parameter(uniform.name)
	material.shader=shader
	for uniform in shader.get_shader_uniform_list():
		if current.has(uniform.name):material.set_shader_parameter(uniform.name,current[uniform.name])
		elif defaults.has(uniform.name):material.set_shader_parameter(uniform.name,defaults[uniform.name])

func _run() -> void:
	orphan_baseline=int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	DisplayServer.window_set_size(Vector2i(1280,720))
	scene=load("res://scenes/main.tscn").instantiate()
	scene.playing=false;scene.generation=1001;root.add_child(scene);current_scene=scene
	var deadline:=Time.get_ticks_msec()+90000
	while (not scene.ready_for_ticks or scene._booting) and scene.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	check("entry_ready",scene.ready_for_ticks and scene.last_error.is_empty())
	if not scene.ready_for_ticks:await _close();return
	check("props_hold",(await scene._props_hold(true,&"user")).is_empty())
	var material: ShaderMaterial=scene.get_node("GpuWaterSurface").material_override
	var formal: Shader=material.shader
	var defaults:={}
	for uniform in formal.get_shader_uniform_list():defaults[uniform.name]=material.get_shader_parameter(uniform.name)
	var original:=Shader.new()
	original.code=FileAccess.get_file_as_string("res://task/water_foam_visual/验收/G4/before_integration/assets/water_material_natural_candidate/async_rdc_water.gdshader")
	check("original_shader_identity",original.code.sha256_text()=="26a503bd375f88e43f7b1a7fdac1812fd2d7da4ad4217423aa5ae6d398ed0a61")
	_swap(material,original,defaults)
	scene.get_node("ShoreContactOverlay").material_override.set_shader_parameter("natural_contact_gain",1.0)
	await _advance(30)
	await _snapshot("start")
	var cases:=[]
	observations.variants=[]
	observations.engine=Engine.get_version_info()
	observations.configuration=scene.configuration.duplicate(true)
	for index in 3:
		check("restore_"+str(index),(await scene.restore_gpu_checkpoint(output+"/start.sandue")).is_empty())
		await process_frame;await _idle()
		check("props_held_"+str(index),(await scene._props_hold(true,&"user")).is_empty())
		_swap(material,formal if index==2 else original,defaults)
		if index==2:material.set_shader_parameter("foam_detail_mode",1)
		scene.get_node("ShoreContactOverlay").material_override.set_shader_parameter("natural_contact_gain",0.55 if index==2 else 1.0)
		observations.variants.append({"case":index,"shader_sha256":material.shader.code.sha256_text(),"contact_gain":scene.get_node("ShoreContactOverlay").material_override.get_shader_parameter("natural_contact_gain"),"material":_material(material)})
		for tool in [&"place_sand",&"remove_sand"]:
			check("admit_%d_%s"%[index,tool],scene.input.begin(tool,Vector2(3,0),{},0.1,3,0.25).accepted)
			check("finish_%d_%s"%[index,tool],scene.input.finish().accepted)
			await _idle()
			check("end_empty_%d_%s"%[index,tool],scene.input.end_requested.is_empty())
			await _advance(30)
		cases.append(await _snapshot("case"+str(index)+"_final"))
	_same("exact_original_AA",cases[0],cases[1])
	_same("original_vs_formal_AB",cases[1],cases[2])
	observations.scope="Exact pre-integration water shader/contact1 AA, then formal shader/contact0.55 AB. Same restored checkpoint and admitted input/ticks; no middle captures or numerical changes. This is a diagnostic, not performance acceptance."
	await _close()

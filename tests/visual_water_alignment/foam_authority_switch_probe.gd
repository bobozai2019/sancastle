extends "res://docs/competitor/tools/probe_foam_comparison.gd"

func _snapshot(label: String) -> Dictionary:
	var path:=output+"/"+label+".sandue"
	await process_frame
	var error: StringName=await scene.save_gpu_checkpoint(path)
	observations[label+"_save_error"]=String(error)
	check(label+"_save",error.is_empty())
	var result:=Codec.load(path,scene.configuration)
	check(label+"_load",result.error.is_empty())
	await process_frame
	return result.checkpoint if result.error.is_empty() else {}

func _advance(count: int) -> void:
	for i in count:
		check("tick_request_"+str(checks.size()),scene.runtime.request_tick(1.0/30.0).is_empty())
		await _wait_tick()

func _same(label: String, a: Dictionary, b: Dictionary) -> void:
	check(label+"_tick_time",a.sim_tick==b.sim_tick and a.advanced_time_s==b.advanced_time_s)
	for key in a.native.fields:check(label+"_authority_"+key,a.native.fields[key]==b.native.fields[key])
	for key in a.native.foam:
		if a.native.foam[key] is PackedByteArray:check(label+"_history_"+key,a.native.foam[key]==b.native.foam[key])
	check(label+"_front",a.native.histories==b.native.histories)

func _run() -> void:
	orphan_baseline=int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	DisplayServer.window_set_size(Vector2i(1280,720))
	scene=load("res://scenes/main.tscn" if scene_key=="main" else "res://scenes/playable/test1_geometry.tscn").instantiate()
	scene.playing=false;scene.generation=1001;root.add_child(scene);current_scene=scene
	var deadline:=Time.get_ticks_msec()+90000
	while (not scene.ready_for_ticks or scene._booting) and scene.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	check("entry_ready",scene.ready_for_ticks and scene.last_error.is_empty())
	if not scene.ready_for_ticks:await _close();return
	check("props_hold",(await scene._props_hold(true,&"user")).is_empty())
	await _advance(30)
	await _snapshot("start")
	var results:=[]
	for mode in [0,0,1]:
		check("restore_start_"+str(mode),(await scene.restore_gpu_checkpoint(output+"/start.sandue")).is_empty())
		await process_frame
		await _idle()
		check("held_after_restore_"+str(results.size()),(await scene._props_hold(true,&"user")).is_empty())
		scene.get_node("GpuWaterSurface").material_override.set_shader_parameter("foam_detail_mode",mode)
		for tool in [&"place_sand",&"remove_sand"]:
			check("admit_"+str(mode)+String(tool),scene.input.begin(tool,Vector2(3,0),{},0.1,3,0.25).accepted)
			scene.input.finish();await _idle();await _advance(30)
		results.append(await _snapshot("case"+str(results.size())+"_mode"+str(mode)))
	_same("mode0_AA",results[0],results[1])
	_same("mode0_vs_mode1",results[1],results[2])
	var service=root.get_node("BeachScenes")
	service.session_directory=output+"/switch_sessions"
	DirAccess.make_dir_recursive_absolute(service.session_directory)
	service.attach(scene)
	var expected:={scene.scene_key:results[2]}
	for index in 5:
		var key: String="test1_geometry" if scene.scene_key=="main" else "main"
		var old_id: int=scene.get_instance_id()
		check("switch_admitted_"+str(index),service.request_switch(key))
		check("switch_duplicate_refused_"+str(index),not service.request_switch(key))
		deadline=Time.get_ticks_msec()+120000
		while service.busy and Time.get_ticks_msec()<deadline:await process_frame
		scene=service.active_scene
		check("switch_ready_"+str(index),not service.busy and service.last_error.is_empty() and is_instance_valid(scene) and scene.scene_key==key and scene.ready_for_ticks)
		observations["switch_error_"+str(index)]=service.last_error
		if not is_instance_valid(scene):quit(1);return
		if not service.last_error.is_empty() or scene.scene_key!=key:await _close();return
		check("previous_scene_freed_"+str(index),not is_instance_id_valid(old_id))
		check("switch_new_mode_"+str(index),scene.get_node("GpuWaterSurface").material_override.get_shader_parameter("foam_detail_mode")==1)
		check("switch_texture_"+str(index),scene.get_node("GpuWaterSurface").material_override.get_shader_parameter("foam_detail_texture").resource_path=="res://assets/water_foam/foam_detail.png")
		check("switch_props_hold_"+str(index),(await scene._props_hold(true,&"user")).is_empty())
		var actual:=await _snapshot("switch"+str(index))
		if expected.has(key):_same("switch"+str(index),expected[key],actual)
		else:expected[key]=actual
		await _capture("switch"+str(index))
	observations.release_records=service.release_records.duplicate(true)
	observations.scope="Same checkpoint, same fill/dig and 60 ticks: mode0/mode1 native authority and histories exact. Five formal scene switches, saved per-scene state and release. No performance claim."
	await _close()

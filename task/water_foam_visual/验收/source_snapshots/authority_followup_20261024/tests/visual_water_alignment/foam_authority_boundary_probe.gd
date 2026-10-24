extends "res://tests/visual_water_alignment/foam_authority_switch_probe.gd"

# Keep each exact checkpoint, but use the already validated capture in memory
# instead of decoding/validating the same container again in the UI thread.
func _snapshot(label: String) -> Dictionary:
	await process_frame
	var error: StringName=await scene.save_gpu_checkpoint(output+"/"+label+".sandue")
	check(label+"_save",error.is_empty())
	await process_frame
	return scene._saved.checkpoint if error.is_empty() else {}

func _advance(count: int) -> void:
	for i in count:
		var before: int=scene.runtime.current.completed_tick
		check("tick_admitted_"+str(checks.size()),scene.runtime.request_tick(1.0/30.0).is_empty())
		await _wait_tick()
		check("tick_completed_once_"+str(checks.size()),scene.runtime.current.completed_tick==before+1)

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
	var cases:=[]
	for index in 3:
		check("restore_"+str(index),(await scene.restore_gpu_checkpoint(output+"/start.sandue")).is_empty())
		await process_frame;await _idle()
		check("props_held_"+str(index),(await scene._props_hold(true,&"user")).is_empty())
		scene.get_node("GpuWaterSurface").material_override.set_shader_parameter("foam_detail_mode",1 if index==2 else 0)
		var stages:={"restored":await _snapshot("case%d_restored"%index)}
		for tool in [&"place_sand",&"remove_sand"]:
			check("admit_%d_%s"%[index,tool],scene.input.begin(tool,Vector2(3,0),{},0.1,3,0.25).accepted)
			scene.input.finish();await _idle()
			check("input_end_empty_%d_%s"%[index,tool],scene.input.end_requested.is_empty())
			observations["receipts_%d_%s"%[index,tool]]=scene.input.terminal.duplicate(true)
			stages[String(tool)+"_0"]=await _snapshot("case%d_%s_0"%[index,tool])
			await _advance(1)
			stages[String(tool)+"_1"]=await _snapshot("case%d_%s_1"%[index,tool])
			await _advance(29)
			stages[String(tool)+"_30"]=await _snapshot("case%d_%s_30"%[index,tool])
		cases.append(stages)
	for label in cases[0]:
		_same("AA_"+label,cases[0][label],cases[1][label])
		_same("AB_"+label,cases[1][label],cases[2][label])
	observations.scope="Exact boundary snapshots distinguish restore/edit/first tick/accumulation; no tolerances or physics changes."
	await _close()

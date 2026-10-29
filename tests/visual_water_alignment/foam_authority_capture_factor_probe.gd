extends "res://tests/visual_water_alignment/foam_authority_switch_probe.gd"

# Single factor: retain the original Codec.load snapshot path and identical
# completion assertions in both groups; only add/remove intermediate saves.
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
	observations.configuration=scene.configuration.duplicate(true)
	observations.engine=Engine.get_version_info()
	await _advance(30)
	await _snapshot("start")
	for middle in [false,true]:
		var label: String="with_middle" if middle else "end_only"
		var cases:=[]
		for index in 3:
			var prefix: String=label+"_case"+str(index)
			check(prefix+"_restore",(await scene.restore_gpu_checkpoint(output+"/start.sandue")).is_empty())
			await process_frame;await _idle()
			check(prefix+"_held",(await scene._props_hold(true,&"user")).is_empty())
			scene.get_node("GpuWaterSurface").material_override.set_shader_parameter("foam_detail_mode",1 if index==2 else 0)
			if middle:await _snapshot(prefix+"_restored")
			for tool in [&"place_sand",&"remove_sand"]:
				check(prefix+String(tool)+"_admit",scene.input.begin(tool,Vector2(3,0),{},0.1,3,0.25).accepted)
				var finish: Dictionary=scene.input.finish()
				check(prefix+String(tool)+"_finish",finish.accepted)
				await _idle()
				check(prefix+String(tool)+"_end_empty",scene.input.end_requested.is_empty())
				if middle:await _snapshot(prefix+String(tool)+"_0")
				await _advance(1)
				if middle:await _snapshot(prefix+String(tool)+"_1")
				await _advance(29)
				if middle:await _snapshot(prefix+String(tool)+"_30")
			observations[prefix+"_receipts"]=scene.input.terminal.duplicate(true)
			cases.append(await _snapshot(prefix+"_final"))
		_same(label+"_AA",cases[0],cases[1])
		_same(label+"_AB",cases[1],cases[2])
		for group in cases[0].native:
			check(label+"_AA_all_native_"+group,cases[0].native[group]==cases[1].native[group])
			check(label+"_AB_all_native_"+group,cases[1].native[group]==cases[2].native[group])
	check("runtime_healthy",scene.last_error.is_empty() and scene.runtime.current.fault_reason().is_empty())
	observations.scope="One factor: extra intermediate checkpoint saves. Original decoder and completion assertions identical in both groups; no production or tolerance changes, no performance claim."
	await _close()

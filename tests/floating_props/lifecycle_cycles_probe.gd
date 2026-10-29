extends "res://tests/floating_props/scene_reentry_probe.gd"

var rounds: Array=[]

func _run() -> void:
	orphan_baseline=int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT));DisplayServer.window_set_size(Vector2i(1280,720))
	scene=load("res://scenes/main.tscn").instantiate();scene.playing=false;root.add_child(scene);current_scene=scene;hub=root.get_node("BeachScenes");hub.attach(scene)
	hub.session_directory=output.get_base_dir()+"/sessions";DirAccess.make_dir_recursive_absolute(hub.session_directory)
	var deadline:=Time.get_ticks_msec()+90000
	while (scene._booting or not scene.ready_for_ticks) and scene.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	props=scene.floating_props;check("cycles_main_ready",not scene._booting and scene.ready_for_ticks and props.active)
	if scene._booting:await _close();return
	var owner_baseline: Dictionary=scene.runtime.current.ownership_counts()
	for index in 10:
		await _run_for(0.2)
		var path:=output.get_base_dir()+"/round_"+str(index+1)+".sandue"
		check("round_save_"+str(index+1),(await scene.save_gpu_checkpoint(path)).is_empty())
		check("round_failed_save_"+str(index+1),not (await scene.save_gpu_checkpoint(path)).is_empty() and props.holds.has(&"user") and not props.holds.has(&"save"))
		var before:=_poses();var owner: int=props.owner_token;var generation: int=props.generation
		scene.runtime.inject_commit_validation_failure=true
		var error: StringName=await scene.restore_gpu_checkpoint(path)
		check("round_failed_restore_preserves_"+str(index+1),not error.is_empty() and _poses()==before and props.owner_token==owner and props.generation==generation and not props.holds.has(&"restore"))
		scene.runtime.inject_commit_validation_failure=false
		deadline=Time.get_ticks_msec()+30000
		while (scene.runtime.candidate!=null or not scene.runtime.retired.is_empty()) and Time.get_ticks_msec()<deadline:await process_frame
		var old=scene.runtime.current
		error=await scene.restore_gpu_checkpoint(path)
		check("round_success_restore_resets_"+str(index+1),error.is_empty() and props.owner_token==owner+1 and props.generation>generation and props.admitted_time_s==0.0 and props.actual_time.values().all(func(v):return v==0.0))
		deadline=Time.get_ticks_msec()+30000
		while not scene.runtime.retired.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
		check("round_retired_owners_zero_"+str(index+1),old.released and old.ownership_counts().values().all(func(v):return v==0))
		check("round_active_resource_baseline_"+str(index+1),scene.runtime.current.ownership_counts()==owner_baseline and props.last_error.is_empty() and props.holds.has(&"user") and not props.holds.has(&"save") and not props.holds.has(&"restore"))
		if index in [2,5,8]:
			await _switch("test1_capture");check("round_capture_no_props_"+str(index+1),scene.floating_props==null)
			await _switch("main")
			check("round_main_reentry_baseline_"+str(index+1),props!=null and props.registry.size()==3 and props.admitted_time_s==0.0 and scene.runtime.current.ownership_counts()==owner_baseline)
		rounds.append({"round":index+1,"generation":props.generation,"owner":props.owner_token,"ownership":scene.runtime.current.ownership_counts(),"orphan_nodes":int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),"release_records":hub.release_records.duplicate(true)})
		print("LIFECYCLE_CYCLES ",index+1," / 10")
		if not props.last_error.is_empty():break
	check("ten_rounds_completed",rounds.size()==10)
	check("all_scene_disposals_released",hub.release_records.all(func(row):return row.gpu_released and row.node_freed))
	check("no_orphan_accumulation_between_rounds",rounds.all(func(row):return row.orphan_nodes<=orphan_baseline))
	observations.rounds=rounds;observations.resource_baseline=owner_baseline;observations.sources=scene.configuration.sources.duplicate(true)
	props.set_physics_process(false)
	while props.pending:await process_frame
	scene.runtime.current.views.probe.inject_readback_failure_once=true;props._request_sample()
	deadline=Time.get_ticks_msec()+15000
	while not scene.runtime.current.views.probe.unknown and Time.get_ticks_msec()<deadline:await process_frame
	check("cycles_final_unknown_close_setup",props.pending and scene.runtime.current.views.probe.unknown)
	await _close()

func finish() -> void:
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"pass":not failed,"checks":checks,"observations":observations,"scope":"G6 ten repeated save/failed-save/failed-restore/successful-restore rounds; real capture/main round-trips in rounds3/6/9; retired resources, active allocation baseline, orphan drift and final unknown-reader exit."},"\t"));quit(1 if failed else 0)

extends "res://tests/floating_props/lifecycle_probe.gd"

var hub

func _switch(key: String, failure: bool=false) -> void:
	# Successful restore returns before the next root process notification
	# refreshes ready_for_ticks. Respect the public source-entry precondition,
	# rather than requesting a switch inside that same completion callback.
	var ready_deadline:=Time.get_ticks_msec()+5000
	while (scene._booting or not scene.ready_for_ticks) and scene.last_error.is_empty() and Time.get_ticks_msec()<ready_deadline:await process_frame
	check("switch_source_ready_"+str(checks.size()),not scene._booting and scene.ready_for_ticks and scene.last_error.is_empty())
	hub.inject_target_failure_once=failure
	check("switch_admitted_"+key+str(checks.size()),hub.request_switch(key))
	check("duplicate_switch_rejected_"+str(checks.size()),not hub.request_switch(key))
	var deadline:=Time.get_ticks_msec()+180000
	while hub.busy and Time.get_ticks_msec()<deadline:await process_frame
	scene=hub.active_scene
	ready_deadline=Time.get_ticks_msec()+5000
	while scene!=null and (scene._booting or not scene.ready_for_ticks) and scene.last_error.is_empty() and Time.get_ticks_msec()<ready_deadline:await process_frame
	check("switch_returns_ready_entry_"+str(checks.size()),not hub.busy and scene!=null and not scene._booting and scene.ready_for_ticks)
	check("switch_result_"+str(checks.size()),not hub.last_error.is_empty() if failure else hub.last_error.is_empty() and scene.scene_key==key)
	if scene!=null:props=scene.floating_props

func _run() -> void:
	orphan_baseline=int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT));DisplayServer.window_set_size(Vector2i(1280,720))
	scene=load("res://scenes/main.tscn").instantiate();scene.playing=false;root.add_child(scene);current_scene=scene;hub=root.get_node("BeachScenes");hub.attach(scene)
	hub.session_directory=output.get_base_dir()+"/sessions";DirAccess.make_dir_recursive_absolute(hub.session_directory)
	var deadline:=Time.get_ticks_msec()+90000
	while (scene._booting or not scene.ready_for_ticks) and scene.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	props=scene.floating_props;check("initial_formal_main_ready",not scene._booting and props.active)
	if scene._booting:await _close();return
	await _wait_paused()
	var first_body: int=props.registry[0].body.get_instance_id();props.registry[0].body.position.x+=0.25
	var original_x: float=props.layout[1].origin.x
	await _switch("test1_capture")
	check("capture_has_no_default_props",scene.floating_props==null and not is_instance_id_valid(first_body))
	await _switch("main")
	check("main_reentry_recreates_fixed_three",props!=null and props.registry.size()==3 and props.registry[0].body.get_instance_id()!=first_body)
	check("main_reentry_resets_props_not_saved_poses",absf(props.registry[0].body.global_position.x-original_x)<1e-6 and props.admitted_time_s==0.0 and props.actual_time.values().all(func(v):return v==0.0) and props.generation==scene.runtime.generation())
	await _switch("test1_capture",true)
	check("failed_target_rolls_back_ready_main_with_props",scene.scene_key=="main" and props!=null and props.active and props.last_error.is_empty() and props.admitted_time_s==0.0)
	check("every_disposed_scene_released_and_freed",hub.release_records.all(func(row):return row.gpu_released and row.node_freed))
	observations.release_records=hub.release_records.duplicate(true);observations.runtime_events=scene.runtime.events.duplicate(true);observations.sources=scene.configuration.sources.duplicate(true)
	await _close()

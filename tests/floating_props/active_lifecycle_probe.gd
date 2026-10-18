extends "res://tests/floating_props/lifecycle_probe.gd"

func _run() -> void:
	orphan_baseline=int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT));DisplayServer.window_set_size(Vector2i(1280,720))
	scene=load("res://scenes/main.tscn").instantiate();root.add_child(scene);props=scene.get_node("FloatingProps/Service")
	var deadline:=Time.get_ticks_msec()+90000
	while (scene._booting or not scene.ready_for_ticks) and scene.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	check("direct_running_main_props_ready",not scene._booting and scene.ready_for_ticks and props.active and scene.playing)
	if scene._booting:await _close();return
	var target: float=scene.runtime.current.advanced_time_s+1.0
	while scene.runtime.current.advanced_time_s<target and props.last_error.is_empty():await process_frame
	check("activation_has_no_initialization_catchup_history",props.origin_time_s>=0 and props.admitted_time_s<=scene.runtime.current.advanced_time_s-props.origin_time_s+1e-6 and props.actual_time[1]>0)
	var path:=output.get_base_dir()+"/active.sandue"
	check("save_while_running_succeeds",(await scene.save_gpu_checkpoint(path)).is_empty())
	check("save_preserves_running_intent",scene.playing and not props.holds.has(&"user") and not props.holds.has(&"save"))
	var time: float=props.actual_time[1]
	for frame in 15:await process_frame
	check("movement_resumes_after_active_save",props.actual_time[1]>time and props.last_error.is_empty())
	check("active_save_existing_file_rejected",not (await scene.save_gpu_checkpoint(path)).is_empty())
	check("failed_save_releases_own_running_hold",scene.playing and not props.holds.has(&"save"))
	# Quiesce real bodies and suspend the entry's periodic retry only while
	# establishing the injected unknown state. Keep the running user intent.
	scene.set_process(false)
	check("fault_setup_body_hold",(await props.set_paused(true,&"save")).error.is_empty())
	props.set_physics_process(false)
	while props.pending:await process_frame
	var old=scene.runtime.current;var old_owner: int=props.owner_token;var old_generation: int=props.generation
	old.views.probe.inject_readback_failure_once=true;props._request_sample()
	deadline=Time.get_ticks_msec()+15000
	while not old.views.probe.unknown and Time.get_ticks_msec()<deadline:await process_frame
	check("restore_starts_with_unknown_live_probe",props.pending and old.views.probe.unknown)
	props.set_physics_process(true)
	check("fault_setup_hold_released",(await props.set_paused(false,&"save")).error.is_empty())
	var error: StringName=await scene.restore_gpu_checkpoint(path);observations.active_restore_error=error
	scene.set_process(true)
	check("active_restore_drains_unknown_reader_and_succeeds",error.is_empty() and scene.playing and props.generation>old_generation and props.owner_token==old_owner+1 and not props.pending)
	check("active_restore_starts_fresh_local_clock",props.admitted_time_s==0.0 and props.actual_time[1]==0.0 and props.last_error.is_empty() and not props.holds.has(&"restore"))
	target=scene.runtime.current.advanced_time_s+0.5
	while scene.runtime.current.advanced_time_s<target and props.last_error.is_empty():await process_frame
	check("active_restore_resumes_new_body_integration",props.actual_time[1]>0 and props.last_error.is_empty())
	old_owner=props.owner_token;old_generation=props.generation;scene.runtime.inject_commit_validation_failure=true
	error=await scene.restore_gpu_checkpoint(path)
	check("failed_active_restore_keeps_generation_owner_and_intent",not error.is_empty() and props.generation==old_generation and props.owner_token==old_owner and scene.playing and not props.holds.has(&"restore") and props.last_error.is_empty())
	scene.runtime.inject_commit_validation_failure=false
	scene.playing=false;await _wait_paused()
	var actual: float=props.actual_time[1];var pose: Transform3D=props.registry[0].body.global_transform
	for frame in 10:await physics_frame
	check("final_user_pause_no_hidden_integration",props.actual_time[1]==actual and props.registry[0].body.global_transform==pose)
	observations.sources=scene.configuration.sources.duplicate(true);observations.generation=props.generation;observations.owner=props.owner_token;observations.actual=props.actual_time.duplicate();observations.events=props.events.duplicate(true)
	await _close()

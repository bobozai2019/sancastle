extends "res://tests/integration/unified_edit_playable_probe.gd"

func _run() -> void:
	orphan_baseline=int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	DisplayServer.window_set_size(Vector2i(1280,720))
	scene=load(_entry_path("main")).instantiate();scene.playing=false;scene.generation=1001;root.add_child(scene)
	var start:=Time.get_ticks_msec()
	while not scene.ready_for_ticks and scene.last_error.is_empty() and Time.get_ticks_msec()-start<90000:await process_frame
	check("scene_service_entry_ready",scene.ready_for_ticks and scene.last_error.is_empty())
	if not scene.ready_for_ticks:await _close();return
	var service=root.get_node("BeachScenes")
	service.session_directory=output+"/sessions";DirAccess.make_dir_recursive_absolute(service.session_directory)
	check("common_service_attached",service.active_scene==scene)
	check("initial_edit",scene.input.begin(&"place_sand",Vector2(3,0),{},0.1,3,0.25).accepted);scene.input.finish();await _idle()
	scene.panel.get_node("Margin/Controls/Tools/Wall").pressed.emit()
	scene.hide_hud=true;scene.player_camera.position+=Vector3(0.2,0.1,0)
	var camera: Transform3D=scene.player_camera.transform
	var old=scene;var saved_seq: int=old.runtime.current.completed_state_seq
	service.inject_target_failure_once=true
	check("failure_switch_admitted",service.request_switch("test1_capture"))
	await _wait_switch(service)
	scene=service.active_scene
	check("failed_target_rollback_in_same_family",scene!=null and scene.scene_key=="main" and scene.get_script().resource_path=="res://scripts/beach/unified_playable_entry.gd" and not service.last_error.is_empty())
	check("rollback_keeps_exact_entry_path",scene.scene_file_path==_entry_path("main"))
	check("rollback_released_previous_node",not is_instance_valid(old))
	check("rollback_keeps_native_progress_and_controls",scene.runtime.current.completed_state_seq==saved_seq and scene.selected_sand_tool==&"wall_v1" and scene.hide_hud and scene.player_camera.transform.is_equal_approx(camera))
	observations.main_sources=scene.configuration.sources.duplicate(true)
	check("real_switch_admitted",service.request_switch("test1_capture"))
	await _wait_switch(service);scene=service.active_scene
	check("real_switch_new_family_capture",scene.scene_key=="test1_capture" and scene.get_script().resource_path=="res://scripts/beach/unified_playable_entry.gd" and service.last_error.is_empty())
	check("capture_keeps_exact_entry_path",scene.scene_file_path==_entry_path("test1_capture"))
	check("shared_brush_controls_preserved",scene.selected_sand_tool==&"wall_v1" and scene.hide_hud and not scene.playing)
	observations.capture_sources=scene.configuration.sources.duplicate(true)
	check("return_switch_admitted",service.request_switch("main"))
	await _wait_switch(service);scene=service.active_scene
	check("return_main_restores_state_and_camera",scene.scene_key=="main" and scene.runtime.current.completed_state_seq==saved_seq and scene.player_camera.transform.is_equal_approx(camera) and service.last_error.is_empty())
	var releases:=true
	for row in service.release_records:releases=releases and row.gpu_released and row.node_freed
	check("all_replaced_roots_released",releases and service.release_records.size()>=3)
	observations.release_records=service.release_records.duplicate(true)
	observations.saved=service.saved.duplicate(true)
	observations.sources=observations.main_sources.duplicate(true);observations.sources.merge(observations.capture_sources,true)
	await _close()

func _wait_switch(service) -> void:
	var start:=Time.get_ticks_msec()
	while service.busy and Time.get_ticks_msec()-start<180000:await process_frame
	check("bounded_switch_"+str(checks.size()),not service.busy)

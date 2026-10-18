extends "res://tests/integration/unified_edit_scene_service_probe.gd"

const Routes=preload("res://scripts/beach/unified_scene_routes.gd")
func _entry_path(key: String) -> String:return Routes.FORMAL[key]

func _run() -> void:
	orphan_baseline=int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	DisplayServer.window_set_size(Vector2i(1280,720))
	scene=load(_entry_path("main")).instantiate();scene.playing=false;scene.generation=1001;root.add_child(scene)
	var start:=Time.get_ticks_msec()
	while not scene.ready_for_ticks and scene.last_error.is_empty() and Time.get_ticks_msec()-start<90000:await process_frame
	check("formal_service_ready",scene.ready_for_ticks and scene.last_error.is_empty())
	if not scene.ready_for_ticks:await _close();return
	var service=root.get_node("BeachScenes")
	service.session_directory=output+"/sessions";DirAccess.make_dir_recursive_absolute(service.session_directory)
	observations.sources={};_sources()
	var foreign:=Node3D.new();service.attach(foreign);check("unknown_factory_cannot_replace_active",service.active_scene==scene);foreign.free()
	var candidate=load(Routes.CANDIDATE.main).instantiate()
	check("candidate_cache_is_separate_identity",service._cache_key(candidate,"main")=="candidate:main" and service._cache_key(scene,"main")=="formal:main");candidate.free()
	check("unknown_scene_rejected",not service.request_switch("unknown"))
	check("formal_initial_edit",scene.input.begin(&"place_sand",Vector2(3,0),{},0.1,3,0.25).accepted);scene.input.finish();await _idle()
	scene.panel.get_node("Margin/Controls/Tools/Wall").pressed.emit()
	scene.hide_hud=true;scene.player_camera.position+=Vector3(0.2,0.1,0)
	var camera: Transform3D=scene.player_camera.transform
	var saved_seq: int=scene.runtime.current.completed_state_seq
	var old=scene
	service.inject_target_failure_once=true
	check("formal_failure_switch_admitted",service.request_switch("test1_capture"));await _wait_switch(service);scene=service.active_scene
	check("formal_rollback_exact_path",scene.scene_file_path==Routes.FORMAL.main and scene.playable_scene_family()=="formal" and not service.last_error.is_empty())
	check("formal_rollback_freed_old_root",not is_instance_valid(old))
	check("formal_rollback_preserves_progress_and_controls",scene.runtime.current.completed_state_seq==saved_seq and scene.selected_sand_tool==&"wall_v1" and scene.hide_hud and scene.player_camera.transform.is_equal_approx(camera));_sources()
	for key in ["test1_capture","test1_backwash","test1_geometry","main"]:
		check("formal_switch_admitted_"+key,service.request_switch(key));await _wait_switch(service);scene=service.active_scene
		check("formal_exact_target_"+key,scene.scene_key==key and scene.scene_file_path==Routes.FORMAL[key] and scene.playable_scene_family()=="formal" and service.last_error.is_empty())
		check("formal_no_legacy_root_"+key,scene.get_script().resource_path==service.ENTRY and not "solver" in scene and not "async_pipeline_enabled" in scene)
		check("formal_controls_"+key,scene.selected_sand_tool==&"wall_v1" and scene.hide_hud and not scene.playing);_sources()
	check("formal_return_main_native_and_camera",scene.runtime.current.completed_state_seq==saved_seq and scene.player_camera.transform.is_equal_approx(camera))
	var clean:=true
	for row in service.release_records:clean=clean and row.gpu_released and row.node_freed
	check("all_formal_roots_released",clean and service.release_records.size()>=5)
	check("all_four_formal_progress_files_retained",service.saved.size()==4)
	for key in service.saved:check("cache_family_"+key,String(key).begins_with("formal:"))
	observations.saved=service.saved.duplicate(true);observations.release_records=service.release_records.duplicate(true)
	await _close()

func _sources() -> void:
	var consistent:=true
	for path in scene.configuration.sources:
		if observations.sources.has(path):consistent=consistent and observations.sources[path]==scene.configuration.sources[path]
		observations.sources[path]=scene.configuration.sources[path]
	check("factory_sources_consistent_"+scene.scene_key+"_"+str(scene.generation),consistent)

func finish() -> void:
	FileAccess.open(output+"/probe.json",FileAccess.WRITE).store_string(JSON.stringify({"pass":not failed,"checks":checks,"observations":observations,"scope":"Formal four-entry routing, family-separated native progress, failed target rollback, controls/camera and unified release; G7 and full final lifecycle/cost remain"},"\t"))
	quit(1 if failed else 0)

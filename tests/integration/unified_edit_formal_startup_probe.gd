extends "res://tests/integration/unified_edit_playable_probe.gd"

func _run() -> void:
	orphan_baseline=int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	DisplayServer.window_set_size(Vector2i(1280,720))
	var path: String=ProjectSettings.get_setting("application/run/main_scene")
	check("actual_project_entry_is_formal_main",path=="res://scenes/main.tscn")
	scene=load(path).instantiate();root.add_child(scene)
	var start:=Time.get_ticks_msec()
	while (not scene.ready_for_ticks or scene.runtime.current.completed_tick<3) and scene.last_error.is_empty() and Time.get_ticks_msec()-start<90000:await process_frame
	check("unmodified_startup_defaults_reach_real_water_ticks",scene.ready_for_ticks and scene.last_error.is_empty() and scene.generation==1 and scene.playing and scene.runtime.current.completed_tick>=3)
	if not scene.ready_for_ticks:await _close();return
	observations.sources=scene.configuration.sources.duplicate(true)
	check("formal_family_is_actual_scene_identity",scene.playable_scene_family()=="formal" and scene.scene_file_path==path)
	check("no_legacy_execution_switch_or_shadow_solver",not "async_pipeline_enabled" in scene and not "solver" in scene and not scene.has_node("GpuCollisionProxy") and scene.get_script().get_base_script()==null)
	for key in scene.SceneRoutes.KEYS:check("formal_route_"+key,scene.playable_scene_path(key)==scene.SceneRoutes.FORMAL[key])
	check("unknown_route_is_not_fallback",scene.playable_scene_path("unknown").is_empty())
	observations.tick=scene.runtime.current.completed_tick;observations.time=scene.runtime.current.advanced_time_s
	await RenderingServer.frame_post_draw
	check("startup_render",root.get_texture().get_image().save_png(output+"/startup.png")==OK)
	await _close()

func finish() -> void:
	FileAccess.open(output+"/probe.json",FileAccess.WRITE).store_string(JSON.stringify({"pass":not failed,"checks":checks,"observations":observations,"scope":"Actual ProjectSettings entry instantiated with unmodified root defaults, real water clock, formal family identity, render and common shutdown; OS main-loop launch not separately asserted"},"\t"))
	quit(1 if failed else 0)

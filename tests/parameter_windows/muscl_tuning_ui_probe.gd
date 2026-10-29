extends SceneTree

var mode:="save"
var scene_key:="main"
var output:="res://test_output/muscl_gui_tuning/ui"
var checks: Array=[]

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--mode="):mode=arg.trim_prefix("--mode=")
		if arg.begins_with("--scene-key="):scene_key=arg.trim_prefix("--scene-key=")
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	call_deferred("run")

func check(label: String, passed: bool) -> void:
	checks.append({"name":label,"pass":passed});print("MUSCL_UI ",label," ",passed)

func run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	var scene_path:="res://scenes/main.tscn" if scene_key=="main" else "res://scenes/playable/test1_geometry.tscn"
	var beach=load(scene_path).instantiate();beach.playing=false;root.add_child(beach);current_scene=beach
	var deadline:=Time.get_ticks_msec()+90000
	while (not beach.ready_for_ticks or beach._booting) and beach.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	check("boot",beach.ready_for_ticks and beach.last_error.is_empty())
	if beach.ready_for_ticks:
		var service=root.get_node("Parameters")
		for id in service.MUSCL_PARAMETERS:
			check("water_control_"+id,service.has_node("water/Margin/Rows/Scroll/Fields/"+id+"/Line/Value") and service.describe(id).available)
		if mode=="save":
			check("defaults",service.effective.muscl_cfl==0.2 and service.effective.muscl_max_attempts==64)
			check("edit_cfl",service.set_value("muscl_cfl",0.3).is_empty())
			check("edit_budget",service.set_value("muscl_max_attempts",32).is_empty())
			check("not_hot_applied",beach.runtime.current.state.muscl_cfl==0.2 and beach.runtime.current.state.muscl_max_attempts==64)
			check("invalid_values_rejected",not service.set_value("muscl_cfl",0.0).is_empty() and not service.set_value("muscl_max_attempts",65).is_empty() and not service.set_value("muscl_max_attempts",1.5).is_empty())
			check("first_order_selection",service.set_value("wave_retention",0.0).is_empty() and service.set_value("solver",0).is_empty())
			check("first_order_disabled",not service.describe("muscl_cfl").available and not service.describe("muscl_max_attempts").available)
			check("muscl_reenabled",service.set_value("solver",1).is_empty() and service.describe("muscl_cfl").available)
			service.save_parameters()
			check("saved",service.saved[scene_key].muscl_cfl==0.3 and service.saved[scene_key].muscl_max_attempts==32)
			check("pending_restart",service.describe("muscl_cfl").status.contains("待重启生效（已保存）"))
			check("startup_snapshot_unchanged",not service.boot_values(scene_key).has("muscl_cfl"))
		else:
			check("cold_restart_consumed",beach.runtime.current.state.muscl_cfl==0.3 and beach.runtime.current.state.muscl_max_attempts==32 and service.effective.muscl_cfl==0.3 and service.effective.muscl_max_attempts==32)
			check("schema3_frozen",beach.configuration.environment.water_numerics.schema==3)
			var tick: int=beach.runtime.current.completed_tick
			check("tick_admitted",beach.runtime.request_tick(1.0/30.0).is_empty())
			while beach.runtime.current.completed_tick<=tick and Time.get_ticks_msec()<deadline:await process_frame
			check("tick_complete",beach.runtime.current.completed_tick>tick and beach.last_error.is_empty())
			var path:=output.path_join("state.sandue")
			var error: StringName=await beach.save_gpu_checkpoint(path)
			check("checkpoint_save",error.is_empty())
			if error.is_empty():check("checkpoint_restore",(await beach.restore_gpu_checkpoint(path)).is_empty())
			check("restore_keeps_tuning",beach.runtime.current.state.muscl_cfl==0.3 and beach.runtime.current.state.muscl_max_attempts==32)
			var changed: Dictionary=beach.configuration.duplicate(true)
			changed.environment.water_numerics.cfl=0.4;changed.configuration_hash=beach.Config.stable_hash(changed)
			check("restore_rejects_cfl_mismatch",beach.CheckpointRouter.load_file(path,changed,true).error==&"numerics_tuning_mismatch")
			changed=beach.configuration.duplicate(true)
			changed.environment.water_numerics.max_attempts=48;changed.configuration_hash=beach.Config.stable_hash(changed)
			check("restore_rejects_budget_mismatch",beach.CheckpointRouter.load_file(path,changed,true).error==&"numerics_tuning_mismatch")
			deadline=Time.get_ticks_msec()+15000
			while not beach.ready_for_ticks and Time.get_ticks_msec()<deadline:await process_frame
			error=await beach.set_wave_retention(0.5)
			if not error.is_empty():print("RETENTION_ERROR ",error)
			check("retention_api",error.is_empty())
			check("retention_keeps_tuning",beach.runtime.current.state.muscl_cfl==0.3 and beach.runtime.current.state.muscl_max_attempts==32)
		service.open_window("water");await process_frame;await RenderingServer.frame_post_draw
		service.get_node("water").get_texture().get_image().save_png(output.path_join("water.png"))
	await beach.shutdown();check("released",beach.gpu_release_done);beach.queue_free();await process_frame
	var passed:=checks.all(func(row):return row.pass)
	FileAccess.open(output.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"pass":passed,"checks":checks},"\t"))
	quit(0 if passed else 1)

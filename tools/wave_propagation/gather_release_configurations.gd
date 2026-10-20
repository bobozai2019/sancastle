extends SceneTree
const Routes=preload("res://scripts/beach/unified_scene_routes.gd")
var output:=""
var checks: Array=[]
var rows: Array=[]
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	call_deferred("run")
func run() -> void:
	if output.is_empty() or DirAccess.dir_exists_absolute(output):quit(2);return
	DirAccess.make_dir_recursive_absolute(output);DisplayServer.window_set_size(Vector2i(1280,720))
	for key in ["main","test1_capture","test1_backwash","test1_geometry"]:
		var scene=load(Routes.FORMAL[key]).instantiate()
		scene.playing=false;scene.generation=1001;scene.water_solver_id="muscl_mc_ssprk2_v1";root.add_child(scene)
		var began:=Time.get_ticks_msec()
		while (not scene.ready_for_ticks or scene._booting) and scene.last_error.is_empty() and Time.get_ticks_msec()-began<120000:await process_frame
		var okay: bool=scene.ready_for_ticks and not scene._booting and scene.last_error.is_empty()
		checks.append({"scene":key,"ready":okay,"error":String(scene.last_error)})
		if okay:rows.append({"scene":key,"configuration":scene.configuration.duplicate(true)})
		await scene.shutdown();checks[-1].released=scene.unified_release_complete()
		var service=root.get_node("BeachScenes")
		if service.active_scene==scene:service.active_scene=null
		scene.queue_free();await process_frame
		if not okay:break
	var path:=output.path_join("targets.variant");FileAccess.open(path,FileAccess.WRITE).store_buffer(var_to_bytes(rows))
	var passed:=rows.size()==4
	for row in checks:passed=passed and row.ready and row.released
	FileAccess.open(output.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"outcome":"pass" if passed else "fail","checks":checks,"targets_path":path,"targets_sha256":FileAccess.get_sha256(path),"scope":"Actual formal scene configuration and candidate boot; no restore acceptance"},"\t"))
	quit(0 if passed else 1)

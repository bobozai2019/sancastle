extends SceneTree
const Routes=preload("res://scripts/beach/unified_scene_routes.gd")
const Codec=preload("res://scripts/simulation/unified_edit/checkpoint_codec.gd")
var scene
var output:=""
var checks: Array=[]
var failed:=false
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	call_deferred("run")
func check(label: String,okay: bool) -> void:
	checks.append({"label":label,"pass":okay});failed=failed or not okay
	if not okay:push_error(label)
func ready() -> void:
	var start:=Time.get_ticks_msec()
	while (not scene.ready_for_ticks or scene._booting or not scene.runtime.retired.is_empty()) and scene.last_error.is_empty() and Time.get_ticks_msec()-start<90000:await process_frame
	check("ready",scene.ready_for_ticks and scene.last_error.is_empty())
func capture(name: String) -> Dictionary:
	await ready()
	var error: StringName=await scene.save_gpu_checkpoint(output.path_join(name+".sandue"))
	check("save_"+name,error.is_empty())
	if not error.is_empty():return {}
	return Codec.read_container(output.path_join(name+".sandue")).checkpoint
func same_fields(a: Dictionary,b: Dictionary,label: String) -> void:
	for key in ["fields","spare","material","foam","histories"]:check(label+"_"+key,a.native[key]==b.native[key])
	for key in ["ledger","advanced_time_s","sim_tick","revision","wave_requests","wave_start_times"]:check(label+"_"+key,a[key]==b[key])
func run() -> void:
	if output.is_empty() or DirAccess.dir_exists_absolute(output):quit(2);return
	DirAccess.make_dir_recursive_absolute(output);DisplayServer.window_set_size(Vector2i(1280,720))
	for key in Routes.KEYS:
		var preview=load(Routes.FORMAL[key]).instantiate()
		var control=preview.get_node_or_null("Interface/EditPanel/Margin/Controls/WaveSettings/Row/WaveRetention")
		check("authored_ui_"+key,control is SpinBox and control.min_value==0.0 and control.max_value==1.0 and is_equal_approx(control.step,0.1))
		preview.free()
	scene=load(Routes.FORMAL.main).instantiate();scene.playing=false;root.add_child(scene);await ready()
	if failed:await finish();return
	var before:=await capture("before")
	await ready()
	var epoch: int=scene.generation
	var control=scene.get_node("Interface/EditPanel/Margin/Controls/WaveSettings/Row/WaveRetention")
	control.value=1.0
	await ready()
	check("ui_changes_generation",scene.generation>epoch)
	check("ui_parameter_actual_gpu_owner",scene.wave_retention==1.0 and scene.runtime.current.state.wave_retention==1.0)
	var after:=await capture("after")
	if not before.is_empty() and not after.is_empty():same_fields(before,after,"retune")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("panel.png"))
	var error: StringName=await scene.set_wave_retention(0.0)
	check("return_default",error.is_empty() and scene.wave_retention==0.0)
	await ready()
	error=await scene.restore_gpu_checkpoint(output.path_join("after.sandue"))
	check("restore_parameter",error.is_empty() and scene.wave_retention==1.0 and scene.runtime.current.state.wave_retention==1.0)
	var restored:=await capture("restored")
	if not after.is_empty() and not restored.is_empty():same_fields(after,restored,"restored")
	check("reject_negative",await scene.set_wave_retention(-0.1)==&"invalid_wave_retention")
	check("reject_nan",await scene.set_wave_retention(NAN)==&"invalid_wave_retention")
	await ready();epoch=scene.generation
	scene.runtime.inject_candidate_initialization_after=&"water"
	error=await scene.set_wave_retention(0.5)
	check("failed_candidate_keeps_owner",not error.is_empty() and scene.generation==epoch and scene.wave_retention==1.0 and scene.runtime.current.state.wave_retention==1.0)
	scene.runtime.inject_candidate_initialization_after=&""
	await ready()
	for index in 6:
		check("continue_tick",scene.runtime.request_tick(1.0/30.0).is_empty())
		while scene.runtime.current.active_count()>0 or scene.runtime.current.pending_count()>0:await process_frame
	check("continue_after_tuning",scene.runtime.current.advanced_time_s>0.19 and scene.runtime.current.fault_reason().is_empty())
	await ready()
	var old_path:="res://test_output/wave_propagation/g6_release_validation_01/default_boot/main.sandue"
	var original:=Codec.read_container(old_path)
	error=await scene.restore_gpu_checkpoint(old_path)
	check("previous_release_restore",error.is_empty() and scene.wave_retention==0.0)
	var historical:=await capture("historical")
	if not original.error.is_empty() or historical.is_empty():check("historical_readable",false)
	else:same_fields(original.checkpoint,historical,"historical")
	await ready()
	for tool in [&"wall_v1",&"shovel_v1"]:
		scene._on_tool_changed(tool)
		await process_frame;await process_frame;await RenderingServer.frame_post_draw
		var rect: Rect2=scene.panel.get_global_rect()
		check("panel_fits_720p_"+String(tool),rect.end.y<=720.0 and rect.position.y>=0.0)
		var water_rect: Rect2=scene.get_node("Interface/EditPanel").get_global_rect()
		check("water_panel_above_props_"+String(tool),water_rect.end.y<=448.0)
		root.get_texture().get_image().save_png(output.path_join(String(tool)+"_panel.png"))
	await finish()
func finish() -> void:
	if scene!=null:
		await scene.shutdown();check("release",scene.unified_release_complete())
		var service=root.get_node("BeachScenes")
		if service.active_scene==scene:service.active_scene=null
		scene.queue_free();await process_frame
	FileAccess.open(output.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"outcome":"fail" if failed else "pass","checks":checks},"\t"));quit(1 if failed else 0)

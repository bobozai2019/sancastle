extends SceneTree

var beach
var frames: Array=[]
var phase:=""
var previous_us:=0
var output:="res://test_output/parameter_function_profile"
var scene_path:="res://scenes/main.tscn"

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
		if arg.begins_with("--scene="):scene_path=arg.trim_prefix("--scene=")
	call_deferred("run")

func _process(_delta: float) -> bool:
	if not phase.is_empty():
		var now:=Time.get_ticks_usec()
		frames.append({"phase":phase,"frame":Engine.get_process_frames(),"us":now,"ms":(now-previous_us)/1000.0,"tick":beach.runtime.current.completed_tick,"focused":root.has_focus()})
		previous_us=now
	return false

func run() -> void:
	if not EngineDebugger.is_active():push_error("Function profiling requires --remote-debug tcp://127.0.0.1:16017");quit(1);return
	beach=load(scene_path).instantiate();root.add_child(beach);current_scene=beach
	var deadline:=Time.get_ticks_msec()+90000
	while (not beach.ready_for_ticks or beach._booting) and beach.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	if not beach.ready_for_ticks:push_error(str(beach.last_error));quit(1);return
	var service=root.get_node("Parameters")
	for group in service.GROUPS:service.get_node(group).hide()
	root.grab_focus()
	await create_timer(5.0).timeout
	var metadata={"engine":Engine.get_version_info(),"adapter":RenderingServer.get_video_adapter_name(),"driver":RenderingServer.get_current_rendering_driver_name(),"window":DisplayServer.window_get_size(),"vsync":DisplayServer.window_get_vsync_mode(),"config":beach.configuration,"profiler":"Godot built-in servers/scripts; native call tracking enabled; 16384 function output limit","phases":[]}
	metadata.scene=scene_path
	for name in ["live_idle","paused_idle"]:
		beach.playing=name=="live_idle"
		await create_timer(2.0).timeout
		phase=name;previous_us=Time.get_ticks_usec()
		EngineDebugger.send_message("function_probe:begin",[name,previous_us,Engine.get_process_frames()])
		EngineDebugger.profiler_enable("servers",true,[16384,true])
		var started:=Time.get_ticks_usec()
		print("FUNCTION_PROFILE_BEGIN ",name)
		await create_timer(20.0 if name=="live_idle" else 10.0).timeout
		EngineDebugger.profiler_enable("servers",false)
		metadata.phases.append({"name":name,"wall_s":(Time.get_ticks_usec()-started)/1000000.0})
		EngineDebugger.send_message("function_probe:end",[name,Time.get_ticks_usec(),Engine.get_process_frames()])
		phase=""
		print("FUNCTION_PROFILE_END ",name)
	DirAccess.make_dir_recursive_absolute(output)
	metadata.last_error=beach.last_error;metadata.source_drift=[]
	for path in beach.configuration.sources:
		if FileAccess.get_sha256(path)!=beach.configuration.sources[path]:metadata.source_drift.append(path)
	var f:=FileAccess.open(output.path_join("frames.json"),FileAccess.WRITE)
	f.store_string(JSON.stringify({"metadata":metadata,"frames":frames},"",true,true));f.close()
	await beach.shutdown()
	EngineDebugger.send_message("function_probe:done",[])
	await create_timer(1.0).timeout
	quit()

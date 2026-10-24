extends SceneTree

# Visible production scene; no input, edits, saves, or alternate simulation.
var beach
var rows: Array=[]
var gpu_rows: Array=[]
var phase:=""
var previous_us:=0
var collecting:=false
var seen_gpu:=-1
var output:="res://test_output/parameter_idle_profile"
var diagnostic

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	call_deferred("run")

func _process(_delta: float) -> bool:
	if phase.is_empty():return false
	var now:=Time.get_ticks_usec()
	var p=beach.runtime.current
	rows.append({"phase":phase,"us":now,"frame_ms":(now-previous_us)/1000.0,"process_ms":Performance.get_monitor(Performance.TIME_PROCESS)*1000.0,"physics_ms":Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0,"render_cpu_ms":RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()),"render_gpu_ms":RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()),"setup_cpu_ms":RenderingServer.get_frame_setup_time_cpu(),"tick":p.completed_tick,"sim_s":p.advanced_time_s,"pending":p.pending_count(),"active":p.active_count(),"ready":beach.ready_for_ticks,"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)})
	previous_us=now
	if not collecting:
		collecting=true
		RenderingServer.call_on_render_thread(collect_gpu.bind(phase))
	return false

func collect_gpu(case_name: String) -> void:
	var rd: RenderingDevice=beach.runtime.current.state.rd
	var frame:=rd.get_captured_timestamps_frame()
	var marks: Array=[]
	if frame!=seen_gpu:
		seen_gpu=frame
		for i in rd.get_captured_timestamps_count():
			marks.append({"name":rd.get_captured_timestamp_name(i),"gpu_ns":rd.get_captured_timestamp_gpu_time(i),"cpu_us":rd.get_captured_timestamp_cpu_time(i)})
	call_deferred("gpu_received",case_name,frame,marks)

func gpu_received(case_name: String, frame: int, marks: Array) -> void:
	collecting=false
	if not marks.is_empty():gpu_rows.append({"phase":case_name,"frame":frame,"marks":marks})

func run() -> void:
	beach=load("res://scenes/main.tscn").instantiate()
	root.add_child(beach);current_scene=beach
	var deadline:=Time.get_ticks_msec()+90000
	while (not beach.ready_for_ticks or beach._booting) and beach.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	if not beach.ready_for_ticks:push_error("PROFILE_BOOT: "+str(beach.last_error));quit(1);return
	var service=root.get_node("Parameters")
	# Hide without persisting layout changes.
	for group in service.GROUPS:service.get_node(group).hide()
	root.grab_focus()
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	for node in root.find_children("*","SubViewport",true,false):RenderingServer.viewport_set_measure_render_time(node.get_viewport_rid(),true)
	var p=beach.runtime.current
	diagnostic=load("res://scripts/simulation/unified_edit/diagnostics.gd").new()
	p.diagnostics=diagnostic;p.heights.diagnostics=diagnostic
	RenderingServer.call_on_render_thread(func():p.state.profile_passes=true)
	await create_timer(5.0).timeout
	var metadata={"engine":Engine.get_version_info(),"adapter":RenderingServer.get_video_adapter_name(),"driver":RenderingServer.get_current_rendering_driver_name(),"window":DisplayServer.window_get_size(),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"configuration":beach.configuration,"camera":beach.player_camera.global_transform,"pid":OS.get_process_id(),"scene":"res://scenes/main.tscn","note":"GPU timestamp collection enabled; windows hidden; no input; sequential phases evolve simulation"}
	for name in ["live_parameters_on","live_parameters_off","live_parameters_on_repeat","paused_parameters_on"]:
		phase=""
		service.set_process(name!="live_parameters_off")
		beach.playing=name!="paused_parameters_on"
		await create_timer(2.0).timeout
		phase=name;previous_us=Time.get_ticks_usec()
		print("IDLE_PROFILE_BEGIN ",phase)
		await create_timer(12.0).timeout
		phase=""
		print("IDLE_PROFILE_END ",name)
	while collecting:await process_frame
	DirAccess.make_dir_recursive_absolute(output)
	var f:=FileAccess.open(output.path_join("capture.json"),FileAccess.WRITE)
	f.store_string(JSON.stringify({"metadata":metadata,"frames":rows,"gpu":gpu_rows,"timeline":diagnostic.snapshot()},"",true,true));f.close()
	service.set_process(true)
	await beach.shutdown()
	print("IDLE_PROFILE_SAVED ",output)
	quit()

extends "res://tools/muscl_performance/cost_scene.gd"

# Developer-only supply probe. Feed the production accumulator; the scene's
# original pending<4 admission and transport ownership remain authoritative.
var supply:=false
var duration_s:=20.0
var started_supply:=false
var focus_lost:=false

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg=="--backlog":supply=true
		if arg.begins_with("--duration="):duration_s=float(arg.trim_prefix("--duration="))
	super._initialize()

func _process(delta: float) -> bool:
	if started_supply and phase=="live" and not root.has_focus():focus_lost=true
	if started_supply and supply and beach!=null and beach.ready_for_ticks:
		beach._accumulator=0.25
	return super._process(delta)

func run() -> void:
	var service=root.get_node("Parameters")
	var expected:=""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--parameter-config="):expected=arg.trim_prefix("--parameter-config=")
	if expected.is_empty() or service._file_path!=expected:
		push_error("EFFICIENCY_PARAMETER_ISOLATION");quit(1);return
	DirAccess.make_dir_recursive_absolute(output)
	beach=load(scene_path).instantiate();root.add_child(beach);current_scene=beach
	var deadline:=Time.get_ticks_msec()+90000
	while (not beach.ready_for_ticks or beach._booting) and beach.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	if not beach.ready_for_ticks:push_error("EFFICIENCY_BOOT");quit(1);return
	for group in service.GROUPS:service.get_node(group).hide()
	root.grab_focus()
	deadline=Time.get_ticks_msec()+60000
	while not root.has_focus() and Time.get_ticks_msec()<deadline:await process_frame
	if not root.has_focus():push_error("EFFICIENCY_FOCUS_TIMEOUT");await beach.shutdown();quit(1);return
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	viewports=root.find_children("*","SubViewport",true,false)
	for viewport in viewports:RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(),true)
	var p=beach.runtime.current
	diagnostic=load("res://scripts/simulation/unified_edit/diagnostics.gd").new()
	p.diagnostics=diagnostic;p.heights.diagnostics=diagnostic
	RenderingServer.call_on_render_thread(func():p.state.profile_passes=true)
	started_supply=true
	await create_timer(7.0).timeout
	phase="live";previous_us=Time.get_ticks_usec()
	var interval:={"phase":"live","start_us":previous_us,"start_tick":p.completed_tick,"start_sim_s":p.advanced_time_s}
	await create_timer(duration_s).timeout
	interval.merge({"end_us":Time.get_ticks_usec(),"end_tick":p.completed_tick,"end_sim_s":p.advanced_time_s})
	started_supply=false;beach.playing=false
	phase="drain"
	await create_timer(2.0).timeout
	phase=""
	while collecting:await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("scene.png"))
	var drift: Array=[]
	for path in beach.configuration.sources:
		if FileAccess.get_sha256(path)!=beach.configuration.sources[path]:drift.append(path)
	var metadata:={"engine":Engine.get_version_info(),"adapter":RenderingServer.get_video_adapter_name(),"driver":RenderingServer.get_current_rendering_driver_name(),"window":DisplayServer.window_get_size(),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"configuration":beach.configuration,"camera":beach.player_camera.global_transform,"pid":OS.get_process_id(),"scene":scene_path,"intervals":[interval],"last_error":beach.last_error,"source_drift":drift,"supply":supply,"queue_limit":4,"parameter_path":service._file_path,"parameter_sha256":FileAccess.get_sha256(expected),"gpu_full_frame_ms":null,"U_busy":null,"G_idle":null,"hardware_counters":null,"note":"Production accumulator supplied each frame, unchanged pending<4 and transport limits. Full visible scene; no state readback. Viewport GPU is partial. Shader TIME remains production presentation time; throughput is diagnostic, not ordinary FPS or a fixed presentation-clock proof."}
	FileAccess.open(output.path_join("capture.json"),FileAccess.WRITE).store_string(JSON.stringify({"metadata":metadata,"frames":rows,"gpu":gpu_rows,"timeline":diagnostic.snapshot()},"",true,true))
	await beach.shutdown()
	if focus_lost:push_error("EFFICIENCY_FOCUS_LOST: invalid measurement, raw rows retained")
	quit(0 if drift.is_empty() and metadata.last_error.is_empty() and not focus_lost else 1)

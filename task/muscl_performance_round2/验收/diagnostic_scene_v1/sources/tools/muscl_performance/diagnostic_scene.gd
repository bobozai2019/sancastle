extends "res://tools/muscl_performance/scene_baseline.gd"

const Observer=preload("res://tools/muscl_performance/diagnostic.gd")
var observer
var installed:=false
var diagnostic_report: Dictionary={}
var report_ready:=false

func install() -> void:
	var p=beach.runtime.current
	observer=Observer.new()
	if observer.initialize(p.state.rd):p.water.muscl.diagnostic=observer
	else:observer=null
	installed=true

func set_enabled(value: bool) -> void:
	if observer!=null:observer.enabled=value

func report() -> void:
	diagnostic_report=observer.snapshot() if observer!=null else {"error":"diagnostic_initialization"}
	report_ready=true

func run() -> void:
	# This tool uses the same formal scene boot; only the developer observer and
	# CPU timeline are attached. Standard coupling and tail Callables are kept.
	var service=root.get_node("Parameters")
	var expected:=""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--parameter-config="):expected=arg.trim_prefix("--parameter-config=")
	if expected.is_empty() or service._file_path!=expected:
		push_error("ROUND2_PARAMETER_ISOLATION_FAILED");quit(1);return
	DirAccess.make_dir_recursive_absolute(output)
	FileAccess.open(output.path_join("isolation.json"),FileAccess.WRITE).store_string(JSON.stringify({"parameter_path":service._file_path,"layout_path":service._layout_path,"startup_sha256":FileAccess.get_sha256(expected)},"\t"))
	beach=load(scene_path).instantiate();root.add_child(beach);current_scene=beach
	var deadline:=Time.get_ticks_msec()+90000
	while (not beach.ready_for_ticks or beach._booting) and beach.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	if not beach.ready_for_ticks:push_error("DIAGNOSTIC_BOOT "+str(beach.last_error));quit(1);return
	for group in service.GROUPS:service.get_node(group).hide()
	root.grab_focus()
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	viewports=root.find_children("*","SubViewport",true,false)
	for viewport in viewports:RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(),true)
	var p=beach.runtime.current
	diagnostic=load("res://scripts/simulation/unified_edit/diagnostics.gd").new()
	p.diagnostics=diagnostic;p.heights.diagnostics=diagnostic
	RenderingServer.call_on_render_thread(install)
	while not installed:await process_frame
	if observer==null:push_error("DIAGNOSTIC_INSTALL");await beach.shutdown();quit(1);return
	await create_timer(5.0).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("scene.png"))
	await create_timer(2.0).timeout
	phase="diagnostic";previous_us=Time.get_ticks_usec()
	var started:=previous_us
	var start_tick: int=p.completed_tick
	var start_sim_s: float=p.advanced_time_s
	RenderingServer.call_on_render_thread(set_enabled.bind(true))
	await create_timer(40.0).timeout
	RenderingServer.call_on_render_thread(set_enabled.bind(false))
	var interval:={"phase":phase,"start_us":started,"end_us":Time.get_ticks_usec(),"start_tick":start_tick,"end_tick":p.completed_tick,"start_sim_s":start_sim_s,"end_sim_s":p.advanced_time_s}
	beach.playing=false
	# Continue collecting timestamp frames while queued work/readbacks drain.
	await create_timer(2.0).timeout
	RenderingServer.call_on_render_thread(report)
	while not report_ready:await process_frame
	phase=""
	while collecting:await process_frame
	var metadata:={"engine":Engine.get_version_info(),"adapter":RenderingServer.get_video_adapter_name(),"driver":RenderingServer.get_current_rendering_driver_name(),"window":DisplayServer.window_get_size(),"vsync":DisplayServer.window_get_vsync_mode(),"configuration":beach.configuration,"camera":beach.player_camera.global_transform,"intervals":[interval],"last_error":beach.last_error,"source_drift":[],"note":"Diagnostic FPS is not an optimization result; standard coupling retained; copied control is before work_seal, completed state_seq must match settle_end timeline."}
	for path in beach.configuration.sources:
		if FileAccess.get_sha256(path)!=beach.configuration.sources[path]:metadata.source_drift.append(path)
	FileAccess.open(output.path_join("capture.json"),FileAccess.WRITE).store_string(JSON.stringify({"metadata":metadata,"frames":rows,"gpu":gpu_rows,"timeline":diagnostic.snapshot(),"diagnostic":diagnostic_report},"",true,true))
	await beach.shutdown()
	var failed: bool=not metadata.last_error.is_empty() or not metadata.source_drift.is_empty() or diagnostic_report.get("samples",[]).is_empty() or diagnostic_report.get("pending",-1)!=0
	observer=null
	quit(1 if failed else 0)

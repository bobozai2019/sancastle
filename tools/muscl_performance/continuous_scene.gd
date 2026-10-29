extends "res://tools/muscl_performance/scene_baseline.gd"

var memory: Array=[]
var memory_done:=false
var duration:=120.0

func sample_memory() -> void:
	var p=beach.runtime.current
	var rd: RenderingDevice=p.state.rd
	memory.append({"us":Time.get_ticks_usec(),"textures":rd.get_memory_usage(RenderingDevice.MEMORY_TEXTURES),"buffers":rd.get_memory_usage(RenderingDevice.MEMORY_BUFFERS),"total":rd.get_memory_usage(RenderingDevice.MEMORY_TOTAL)})
	memory_done=true

func run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	beach=load(scene_path).instantiate();root.add_child(beach);current_scene=beach
	var deadline:=Time.get_ticks_msec()+90000
	while (not beach.ready_for_ticks or beach._booting) and beach.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	if not beach.ready_for_ticks:push_error("CONTINUOUS_BOOT "+str(beach.last_error));quit(1);return
	var service=root.get_node("Parameters")
	for group in service.GROUPS:service.get_node(group).hide()
	root.grab_focus()
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	viewports=root.find_children("*","SubViewport",true,false)
	for viewport in viewports:RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(),true)
	var p=beach.runtime.current
	await create_timer(7.0).timeout
	var frozen: Dictionary=beach.configuration.duplicate(true)
	phase="live";previous_us=Time.get_ticks_usec()
	var started:=previous_us
	var start_sim: float=p.advanced_time_s
	var start_tick: int=p.completed_tick
	for index in 24:
		await create_timer(5.0).timeout
		memory_done=false;RenderingServer.call_on_render_thread(sample_memory)
		while not memory_done:await process_frame
		print("CONTINUOUS_SAMPLE ",index," tick=",p.completed_tick," pending=",p.pending_count()," active=",p.active_count())
		if not beach.last_error.is_empty():break
	phase=""
	var ended:=Time.get_ticks_usec()
	var end_sim: float=p.advanced_time_s
	var end_tick: int=p.completed_tick
	beach.playing=false
	await create_timer(2.0).timeout
	var paused_sim: float=p.advanced_time_s
	await create_timer(2.0).timeout
	var pause_ok: bool=p.advanced_time_s==paused_sim and p.pending_count()==0 and p.active_count()==0
	beach.playing=true
	await create_timer(2.0).timeout
	var resume_ok: bool=p.advanced_time_s>paused_sim
	beach.playing=false
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("scene.png"))
	while collecting:await process_frame
	var drift: Array=[]
	for path in frozen.sources:
		if FileAccess.get_sha256(path)!=frozen.sources[path]:drift.append(path)
	var error: String=beach.last_error
	await beach.shutdown()
	var passed: bool=error.is_empty() and drift.is_empty() and memory.size()==24 and ended-started>=120000000 and end_tick>start_tick and pause_ok and resume_ok and p.released
	FileAccess.open(output.path_join("capture.json"),FileAccess.WRITE).store_string(JSON.stringify({"pass":passed,"metadata":{"engine":Engine.get_version_info(),"adapter":RenderingServer.get_video_adapter_name(),"driver":RenderingServer.get_current_rendering_driver_name(),"window":DisplayServer.window_get_size(),"vsync":DisplayServer.window_get_vsync_mode(),"configuration":frozen,"source_drift":drift,"last_error":error,"scene":scene_path,"start_tick":start_tick,"end_tick":end_tick,"start_sim_s":start_sim,"end_sim_s":end_sim,"start_us":started,"end_us":ended,"pause_ok":pause_ok,"resume_ok":resume_ok,"released":p.released},"frames":rows,"gpu":gpu_rows,"memory":memory},"",true,true))
	quit(0 if passed else 1)

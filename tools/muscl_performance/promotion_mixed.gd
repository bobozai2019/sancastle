extends "res://tools/muscl_performance/cost_scene.gd"

const Brush=preload("res://scripts/simulation/brushes/brush_protocol.gd")
var workload:="mixed"
var input_events: Array=[]
var input_failed:=false
var memory: Array=[]
var memory_done:=true
var next_memory_us:=0

func sample_memory() -> void:
	var rd: RenderingDevice=beach.runtime.current.state.rd
	memory.append({"us":Time.get_ticks_usec(),"textures":rd.get_memory_usage(RenderingDevice.MEMORY_TEXTURES),"buffers":rd.get_memory_usage(RenderingDevice.MEMORY_BUFFERS)})
	memory_done=true

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--case="):workload=arg.trim_prefix("--case=")
	super._initialize()

func apply_input(completed_tick: int) -> void:
	var cycle:=completed_tick/300
	var tick:=completed_tick%300
	var p=beach.runtime.current
	if tick==10:
		var request:={"domain_id":beach._domain_id(),"generation":beach.generation,"request_id":cycle+1,"start_tick":completed_tick+2,"profile_id":&"test_packet","amplitude_m":0.1,"duration_s":1.0,"seed":48}
		var result: Dictionary=beach.runtime.request_wave(request)
		input_events.append({"tick":tick,"kind":"wave","request":request,"accepted":result.accepted})
		input_failed=input_failed or not result.accepted
	if tick not in [40,70]:return
	var stroke:=7001+completed_tick
	var command_id:=cycle*6+(1 if tick==40 else 4)
	var identity:={"domain_id":beach._domain_id(),"generation":beach.generation,"command_id":command_id,"sim_tick":completed_tick,"stroke_id":stroke,"baseline_token":stroke}
	var begin: Dictionary=p.submit_control("begin",identity)
	var command=Brush.make_command(&"shovel_v1",{"trench_width_m":0.5,"depth_m":0.15,"shoulder_width_m":0.5},Vector2(0,-0.5),Vector2(0,0.5),beach._domain_id(),beach.generation,command_id+1,stroke,0,completed_tick,stroke)
	command.material_profile_id=&"plain_sand_v1";command.water_policy=2;command.speed_m_s=0.25
	var sample: Dictionary=p.submit_legacy(command,2,0.25)
	identity.command_id=command_id+2
	var end: Dictionary=p.submit_control("end",identity)
	var deadline:=Time.get_ticks_msec()+30000
	while (p.pending_count()>0 or p.active_count()>0) and p.fault_reason().is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	var applied: bool=p.result(command_id+1).get("outcome",-1)==p.L.Outcome.APPLIED
	input_events.append({"tick":tick,"kind":"shovel","begin":begin.accepted,"sample":sample.accepted,"end":end.accepted,"applied":applied,"stroke":stroke,"command_id":command_id+1})
	input_failed=input_failed or not (begin.accepted and sample.accepted and end.accepted and applied)

func run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	beach=load(scene_path).instantiate();beach.playing=false
	root.add_child(beach);current_scene=beach
	var deadline:=Time.get_ticks_msec()+90000
	while (not beach.ready_for_ticks or beach._booting) and beach.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	if not beach.ready_for_ticks:push_error("INPUT_COST_BOOT");quit(1);return
	var service=root.get_node("Parameters")
	for group in service.GROUPS:service.get_node(group).hide()
	root.grab_focus()
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	viewports=root.find_children("*","SubViewport",true,false)
	for viewport in viewports:RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(),true)
	var p=beach.runtime.current
	diagnostic=load("res://scripts/simulation/unified_edit/diagnostics.gd").new()
	pass # Keep production diagnostics disabled for functional endurance.
	RenderingServer.call_on_render_thread(func():p.state.profile_passes=false)
	await create_timer(7.0).timeout
	var frozen: Dictionary=beach.configuration.duplicate(true)
	phase="live";previous_us=Time.get_ticks_usec()
	var started:=previous_us
	var start_sim: float=p.advanced_time_s
	var start_tick: int=p.completed_tick
	while Time.get_ticks_usec()-started<120000000 and beach.last_error.is_empty():
		var tick: int=p.completed_tick
		if Time.get_ticks_usec()>=next_memory_us:
			next_memory_us=Time.get_ticks_usec()+5000000
			memory_done=false;RenderingServer.call_on_render_thread(sample_memory)
			while not memory_done:await process_frame
		await apply_input(tick)
		if not p.request_tick(1.0/30.0).is_empty():input_failed=true;break
		deadline=Time.get_ticks_msec()+30000
		while (p.pending_count()>0 or p.active_count()>0) and p.fault_reason().is_empty() and Time.get_ticks_msec()<deadline:await process_frame
		if not p.fault_reason().is_empty() or Time.get_ticks_msec()>=deadline:input_failed=true;break
	var interval:={"phase":"live","start_us":started,"end_us":Time.get_ticks_usec(),"start_sim_s":start_sim,"end_sim_s":p.advanced_time_s,"start_tick":start_tick,"end_tick":p.completed_tick}
	phase="paused";previous_us=Time.get_ticks_usec()
	await create_timer(2.0).timeout
	phase=""
	while collecting:await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("scene.png"))
	var drift: Array=[]
	for path in frozen.sources:
		if FileAccess.get_sha256(path)!=frozen.sources[path]:drift.append(path)
	var metadata:={"engine":Engine.get_version_info(),"adapter":RenderingServer.get_video_adapter_name(),"driver":RenderingServer.get_current_rendering_driver_name(),"window":DisplayServer.window_get_size(),"vsync":DisplayServer.window_get_vsync_mode(),"camera":beach.player_camera.global_transform,"configuration":frozen,"last_error":beach.last_error,"source_drift":drift,"intervals":[interval],"workload":workload,"inputs":input_events,"note":"Fixed tick public inputs, one outstanding manual water tick, full visible scene and consumers; 120s continuous manual fixed-tick wave and shovel sequence repeated every 300 completed ticks, no state readbacks; functional endurance, not ordinary realtime scheduling FPS"}
	var passed: bool=Time.get_ticks_usec()-started>=120000000 and not input_failed and drift.is_empty() and beach.last_error.is_empty() and input_events.size()>=6
	FileAccess.open(output.path_join("capture.json"),FileAccess.WRITE).store_string(JSON.stringify({"pass":passed,"metadata":metadata,"frames":rows,"gpu":gpu_rows,"timeline":diagnostic.snapshot(),"memory":memory},"",true,true))
	await beach.shutdown()
	quit(0 if passed else 1)

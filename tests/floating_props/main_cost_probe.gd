extends "res://tests/floating_props/lifecycle_probe.gd"

var count:=3
var mode: StringName=&"boot"
var frames: Array=[]
var recipe: Array=[]
var last_stamp:=0
var next_edit_s:=5.0
var next_wave_s:=8.0
var observed_error:=""

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
		if arg=="--case=zero":count=0
	call_deferred("_run")

func _process(delta: float) -> bool:
	if mode not in [&"warm",&"measure"] or scene==null:return false
	var stamp:=Time.get_ticks_usec();var time: float=scene.runtime.current.advanced_time_s
	if mode==&"measure" and last_stamp>0:
		frames.append({"stamp_us":stamp,"wall_frame_ms":float(stamp-last_stamp)/1000.0,"engine_frame_ms":delta*1000.0,"physics_cpu_ms":float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS))*1000.0,"physics_frame":Engine.get_physics_frames(),"water_time_s":time,"state_seq":scene.runtime.current.completed_state_seq,"sample_age_s":0.0 if props==null or props.sample.is_empty() else time-float(props.sample.captured_time_s),"prop_actual_time_s":0.0 if props==null else float(props.actual_time[1]),"prop_admitted_time_s":0.0 if props==null else props.admitted_time_s})
	last_stamp=stamp
	if props!=null and not props.last_error.is_empty():observed_error=String(props.last_error)
	if not scene.last_error.is_empty():observed_error=String(scene.last_error)
	if time>=next_edit_s:
		var selected: StringName=&"fill_v1" if int(next_edit_s/5.0)%2==1 else &"dig_v1";var profile: Dictionary=scene.registry.profile(selected)
		var request:={"domain_id":"main_beach","generation":scene.runtime.generation(),"command_id":scene.runtime.highwater()+1,"sim_tick":scene.runtime.current.completed_tick,"profile_id":selected,"profile_version":1,"profile_hash":profile.profile_hash,"start_xz_m":Vector2(0,4),"parameters":{"amount_m3":0.01,"radius_m":0.4},"features":{"water_policy":3}}
		var admitted: Dictionary=scene.runtime.submit_intent(request)
		recipe.append({"kind":"edit","at_sim_s":next_edit_s,"actual_sim_s":time,"request":request,"accepted":admitted.accepted});next_edit_s+=5.0
		if not admitted.accepted:observed_error="edit_rejected:"+String(admitted.error)
	if time>=next_wave_s:
		var request:={"domain_id":"main_beach","generation":scene.runtime.generation(),"request_id":scene.runtime.current.boundary.highwater+1,"start_tick":scene.runtime.current._scheduled_tick+scene.runtime.current.pending_count()+2,"profile_id":&"test_packet","amplitude_m":0.1,"duration_s":3.0,"seed":1042+int(next_wave_s)}
		var admitted: Dictionary=scene.runtime.request_wave(request)
		recipe.append({"kind":"wave","at_sim_s":next_wave_s,"actual_sim_s":time,"request":request,"accepted":admitted.accepted});next_wave_s+=10.0
		if not admitted.accepted:observed_error="wave_rejected:"+String(admitted.error)
	return false

func _run() -> void:
	orphan_baseline=int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT));DisplayServer.window_set_size(Vector2i(1280,720))
	scene=load("res://scenes/main.tscn").instantiate();scene.playing=false
	if count==0:scene.get_node("FloatingProps").free()
	root.add_child(scene);props=scene.floating_props
	var deadline:=Time.get_ticks_msec()+90000
	while (scene._booting or not scene.ready_for_ticks) and scene.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	check("cost_visible_full_main_ready",not scene._booting and scene.ready_for_ticks and DisplayServer.window_can_draw())
	if scene._booting:await _close();return
	check("cost_consumer_count_and_trace",props==null if count==0 else props.registry.size()==3 and not props.trace_enabled)
	scene.get_node("Interface/PerformancePanel/Margin/Rows/Header/Sampling").button_pressed=false
	observations.configuration=scene.configuration.duplicate(true)
	observations.environment={"engine":Engine.get_version_info(),"gpu":RenderingServer.get_video_adapter_name(),"driver":RenderingServer.get_current_rendering_driver_name(),"cpu":OS.get_processor_name(),"vsync":DisplayServer.window_get_vsync_mode(),"window_size":DisplayServer.window_get_size(),"output_size":root.get_texture().get_size(),"display":DisplayServer.get_name(),"count":count,"warm_wall_s":10.0,"measure_wall_s":30.0,"sampling":"main process boundary wall intervals; complete visible rendered workload; physics CPU is whole-world Performance monitor"}
	mode=&"warm";scene.playing=true;var warm_start:=Time.get_ticks_usec()
	while Time.get_ticks_usec()-warm_start<10000000:await process_frame
	var start:=Time.get_ticks_usec();var sim_start: float=scene.runtime.current.advanced_time_s
	observations.owners_before=scene.runtime.current.ownership_counts();mode=&"measure";last_stamp=0
	while Time.get_ticks_usec()-start<30000000:await process_frame
	mode=&"done";var end:=Time.get_ticks_usec();var sim_end: float=scene.runtime.current.advanced_time_s
	observations.measure={"start_us":start,"end_us":end,"wall_s":float(end-start)/1000000.0,"sim_start_s":sim_start,"sim_end_s":sim_end,"throughput_sim_s_per_wall_s":(sim_end-sim_start)/(float(end-start)/1000000.0),"frames":frames,"recipe":recipe,"consumer_error":observed_error,"owners_after":scene.runtime.current.ownership_counts()}
	check("cost_full_window_and_no_runtime_fault",frames.size()>100 and float(end-start)>=30000000 and observed_error.is_empty())
	scene.playing=false
	if props!=null:await _wait_paused()
	await RenderingServer.frame_post_draw
	check("cost_visible_output_capture",root.get_texture().get_image().save_png(output.get_base_dir()+"/cost.png")==OK)
	await _close()

extends "res://docs/competitor/tools/probe_foam_comparison.gd"

func _initialize() -> void:
	super._initialize()
	RenderingServer.frame_pre_draw.connect(func():
		if is_instance_valid(scene):
			for path in ["BrushIndicator","BrushPreview"]:scene.get_node(path).hide())

func _sample(start: int) -> Dictionary:
	var owner=scene.runtime.current
	return {"wall_s":(Time.get_ticks_msec()-start)/1000.0,"tick":owner.completed_tick,"time_s":owner.advanced_time_s,"error":String(scene.last_error),"owner_fault":String(owner.fault_reason()),"props_error":String(scene.floating_props.last_error) if scene.floating_props!=null else "","nodes":Performance.get_monitor(Performance.OBJECT_NODE_COUNT),"resources":Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),"orphans":Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),"video_bytes":Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED),"texture_bytes":Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED),"buffer_bytes":Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED)}

func _run() -> void:
	orphan_baseline=int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	DisplayServer.window_set_size(Vector2i(1280,720))
	scene=load("res://scenes/main.tscn" if scene_key=="main" else "res://scenes/playable/test1_geometry.tscn").instantiate()
	scene.playing=false;scene.generation=1001;root.add_child(scene);current_scene=scene
	var deadline:=Time.get_ticks_msec()+90000
	while (not scene.ready_for_ticks or scene._booting) and scene.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	check("entry_ready",scene.ready_for_ticks and scene.last_error.is_empty())
	if not scene.ready_for_ticks:await _close();return
	scene.hide_hud=true;scene.get_node("Interface").hide()
	for path in ["BrushIndicator","BrushPreview"]:scene.get_node(path).hide()
	var boundary: Dictionary=scene.configuration.environment.boundary
	var period: float=TAU/boundary.omega_rad_s if boundary.mode==0 else boundary.period_s
	observations.engine=Engine.get_version_info();observations.adapter=RenderingServer.get_video_adapter_name()
	observations.configuration=scene.configuration;observations.wave_period_s=period
	observations.water=_material(scene.get_node("GpuWaterSurface").material_override)
	scene.playing=true
	await create_timer(20.0).timeout
	var start:=Time.get_ticks_msec()
	var time0: float=scene.runtime.current.advanced_time_s
	var samples: Array=[]
	var serial:=0
	while Time.get_ticks_msec()-start<600000 or scene.runtime.current.advanced_time_s-time0<3.0*period:
		samples.append(_sample(start))
		FileAccess.open(output+"/trend.json",FileAccess.WRITE).store_string(JSON.stringify(samples))
		if serial%6==0:await _capture("live_"+str(serial))
		if not scene.last_error.is_empty() or not scene.runtime.current.fault_reason().is_empty():break
		if Time.get_ticks_msec()-start>1200000:break
		serial+=1
		await create_timer(10.0).timeout
	samples.append(_sample(start));observations.trend=samples
	check("wall_at_least_10min",samples[-1].wall_s>=600.0)
	check("at_least_three_wave_cycles",samples[-1].time_s-time0>=3.0*period)
	check("runtime_healthy",scene.last_error.is_empty() and scene.runtime.current.fault_reason().is_empty())
	check("node_count_stable",samples[-1].nodes==samples[0].nodes)
	check("no_orphan_growth",samples[-1].orphans==samples[0].orphans)
	scene.playing=false
	await _idle();check("props_held_for_pause",(await scene._props_hold(true,&"user")).is_empty())
	var clock: float=scene.runtime.current.advanced_time_s
	await _capture("final_pause_a");await create_timer(2.0).timeout;await _capture("final_pause_b")
	check("completed_clock_frozen",scene.runtime.current.advanced_time_s==clock)
	check("paused_picture_frozen",FileAccess.get_sha256(output+"/final_pause_a.png")==FileAccess.get_sha256(output+"/final_pause_b.png"))
	await _close()

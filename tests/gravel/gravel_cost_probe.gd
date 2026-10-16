extends "res://tests/water_material_natural/rdc_main_smoke.gd"

var rows := []
var cpu_samples := []
var gpu_samples := []
var phase_samples := []
var capture_frame := -1
var collecting := false
var frames := []

func _timestamps() -> void:
	var rd: RenderingDevice=preview.solver.rd
	var frame := rd.get_captured_timestamps_frame()
	if frame==capture_frame: return
	capture_frame=frame
	var begin := -1
	var measured := []
	for i in rd.get_captured_timestamps_count():
		var name := rd.get_captured_timestamp_name(i)
		if name=="sandcastle_gravel_start": begin=rd.get_captured_timestamp_gpu_time(i)
		elif name=="sandcastle_gravel_end" and begin>=0:
			measured.append(float(rd.get_captured_timestamp_gpu_time(i)-begin)/1000000.0)
			begin=-1
	if collecting and not measured.is_empty(): _accept_timestamps.call_deferred(measured)

func _accept_timestamps(values: Array) -> void:
	if collecting: gpu_samples.append_array(values)

func _stats(values: Array) -> Dictionary:
	if values.is_empty(): return {"n":0,"mean":null,"p50":null,"p95":null,"max":null}
	var sorted := values.duplicate()
	sorted.sort()
	var sum := 0.0
	for value in sorted: sum+=value
	return {"n":sorted.size(),"mean":sum/sorted.size(),"p50":sorted[sorted.size()/2],"p95":sorted[mini(sorted.size()-1,int(sorted.size()*0.95))],"max":sorted[-1]}

func _window(seconds: float, measure: bool) -> void:
	var start := Time.get_ticks_usec()
	var previous := start
	collecting=measure
	while Time.get_ticks_usec()-start < seconds*1000000.0:
		await process_frame
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		if measure:
			frames.append(float(now-previous)/1000.0)
			var viewport := root.get_viewport_rid()
			phase_samples.append({"main_cpu_ms":RenderingServer.viewport_get_measured_render_time_cpu(viewport),"main_gpu_ms":RenderingServer.viewport_get_measured_render_time_gpu(viewport),"reflection_gpu_ms":RenderingServer.viewport_get_measured_render_time_gpu(preview.reflection_viewport.get_viewport_rid()),"draw_calls":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)})
		RenderingServer.call_on_render_thread(_timestamps)
		previous=now
	collecting=false

func _run() -> void:
	if output.is_empty(): output="res://test_output/gpu_gravel/cost_"+str(Time.get_unix_time_from_system()).replace(".","_")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.size=Vector2i(1280,720)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	for count in [0,512,0,1024]:
		preview=load("res://scenes/main.tscn").instantiate()
		preview.playing=false
		preview.gravel_enabled=count>0
		preview.gravel_count=count
		root.add_child(preview)
		var deadline := Time.get_ticks_msec()+120000
		while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_msec()<deadline: await process_frame
		_check("cost_ready_%d" % count,preview.ready_for_ticks,preview.last_error)
		if not preview.ready_for_ticks: _finish();quit(1);return
		# Keep the full profile/HUD and editor/collision workload. Only disable
		# the panel's separate timestamp consumer; this probe collects its own.
		preview.get_node("Interface/PerformancePanel").sample_toggle.button_pressed=false
		await process_frame
		RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
		RenderingServer.viewport_set_measure_render_time(preview.reflection_viewport.get_viewport_rid(),true)
		preview.solver.profile_passes=true
		preview.playing=true
		print("GRAVEL_COST_WARMUP count=",count)
		await _window(10.0,false)
		frames.clear();gpu_samples.clear();phase_samples.clear()
		var before_ticks: int=preview.completed_ticks
		var before_cpu: int=preview.gravel_field.cpu_submission_us if preview.gravel_field!=null else 0
		var before_dispatch: int=preview.gravel_field.dispatches if preview.gravel_field!=null else 0
		var before_reads: int=preview.gravel_field.readback_requests if preview.gravel_field!=null else 0
		var start := Time.get_ticks_usec()
		print("GRAVEL_COST_MEASURE count=",count)
		await _window(30.0,true)
		var elapsed := Time.get_ticks_usec()-start
		var dispatch_count: int=preview.gravel_field.dispatches-before_dispatch if preview.gravel_field!=null else 0
		var cpu_us: int=preview.gravel_field.cpu_submission_us-before_cpu if preview.gravel_field!=null else 0
		var reads: int=preview.gravel_field.readback_requests-before_reads if preview.gravel_field!=null else 0
		var main_gpu := []
		var reflection_gpu := []
		var draws := []
		for sample in phase_samples:
			main_gpu.append(sample.main_gpu_ms)
			reflection_gpu.append(sample.reflection_gpu_ms)
			draws.append(sample.draw_calls)
		rows.append({"count":count,"warmup_wall_s":10,"measure_wall_s":elapsed/1000000.0,"completed_ticks":preview.completed_ticks-before_ticks,"ticks_per_wall_second":(preview.completed_ticks-before_ticks)*1000000.0/elapsed,"frame_ms":_stats(frames),"gravel_compute_gpu_ms":_stats(gpu_samples),"cpu_gravel_submission_us_per_dispatch":float(cpu_us)/dispatch_count if dispatch_count>0 else 0.0,"dispatches":dispatch_count,"diagnostic_gravel_readbacks":reads,"main_viewport_gpu_ms":_stats(main_gpu),"reflection_viewport_gpu_ms":_stats(reflection_gpu),"draw_calls_total":_stats(draws),"gravel_draw_gpu_ms":"unknown; paired viewport difference is an estimate, not isolated draw timestamp","profile":preview.gravel_profile.duplicate(true),"camera":str(preview.get_viewport().get_camera_3d().global_transform)})
		_check("cost_no_particle_readbacks_%d" % count,reads==0)
		print("GRAVEL_COST_PHASE ",JSON.stringify(rows[-1]))
		preview.playing=false
		await preview.shutdown()
		preview.queue_free()
		for i in 4: await process_frame
	FileAccess.open(output.path_join("cost.json"),FileAccess.WRITE).store_string(JSON.stringify({"rows":rows,"gpu":RenderingServer.get_video_adapter_name(),"driver":RenderingServer.get_current_rendering_driver_name(),"version":Engine.get_version_info(),"vsync_mode":DisplayServer.window_get_vsync_mode(),"window":[root.size.x,root.size.y],"visible_window":true,"gpu_timestamp_unit":"nanoseconds; existing project D3D12 convention","scope":"short full-load paired measurement; no formal project performance budget"},"\t"))
	_finish()
	print("GRAVEL_COST_OUTPUT ",output)
	quit()

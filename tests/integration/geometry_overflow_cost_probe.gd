extends "res://tests/integration/unified_edit_playable_probe.gd"

const Routes=preload("res://scripts/beach/unified_scene_routes.gd")
var capture_frame:=-1
var collecting:=false
var timings: Array=[]

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	orphan_baseline=int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	DisplayServer.window_set_size(Vector2i(1280,720))
	scene=load(Routes.FORMAL.test1_geometry).instantiate();scene.playing=false
	if "--first-order" in OS.get_cmdline_user_args():scene.water_solver_id=scene.Config.Numerics.FIRST_ORDER
	root.add_child(scene)
	var start:=Time.get_ticks_msec()
	while (not scene.ready_for_ticks or scene._booting) and scene.last_error.is_empty() and Time.get_ticks_msec()-start<90000:await process_frame
	check("geometry_ready",scene.ready_for_ticks and scene.last_error.is_empty())
	if not scene.ready_for_ticks:await _close();return
	observations.sources=scene.configuration.sources.duplicate(true)
	observations.solver=scene.Config.Numerics.solver_id(scene.configuration.environment)
	observations.device={"gpu":RenderingServer.get_video_adapter_name(),"driver":RenderingServer.get_current_rendering_driver_name(),"window":DisplayServer.window_get_size(),"vsync":DisplayServer.window_get_vsync_mode(),"engine":Engine.get_version_info().string}
	RenderingServer.call_on_render_thread(_profile.bind(true));collecting=true;scene.playing=true;start=Time.get_ticks_msec()
	while scene.runtime.current.advanced_time_s<10.0 and scene.last_error.is_empty() and Time.get_ticks_msec()-start<120000:
		RenderingServer.call_on_render_thread(_collect.bind(scene.runtime.current.advanced_time_s))
		await process_frame
	scene.playing=false;await _idle();collecting=false
	RenderingServer.call_on_render_thread(_profile.bind(false))
	check("completed_ten_seconds",scene.runtime.current.advanced_time_s>=10.0 and scene.last_error.is_empty())
	var path:=output+"/final.sandue";check("final_saved",(await scene.save_gpu_checkpoint(path)).is_empty())
	var saved:=Codec.load(path,scene.configuration)
	check("active_drain_measured",saved.error.is_empty() and saved.checkpoint.native.control.decode_u32(104)==1 and saved.checkpoint.native.control.decode_float(120)>0)
	observations.timings=timings
	for phase in ["all","draining_window"]:
		var durations: Array=[]
		for row in timings:
			if row.pass=="sandcastle_boundary" and (phase=="all" or row.observed_time_s>=7.0):durations.append(row.gpu_ns/1000000.0)
		durations.sort()
		check(phase+"_samples",durations.size()>30)
		if not durations.is_empty():observations[phase]={"count":durations.size(),"median_ms":durations[durations.size()/2],"p95_ms":durations[mini(durations.size()-1,ceili(durations.size()*.95)-1)],"max_ms":durations[-1]}
	observations.scope="Visible 1280x720 geometry with full authored rendering and default MUSCL load. GPU boundary interval includes tide, detection, drainage and synchronization; D3D12 timestamp units are ns. A component cost, not a whole-frame FPS claim or isolated device guarantee. Editor may remain open."
	await _close()

func _profile(enabled: bool) -> void:scene.runtime.current.state.profile_passes=enabled

func _collect(time: float) -> void:
	var rd:=RenderingServer.get_rendering_device();var frame:=rd.get_captured_timestamps_frame()
	if frame==capture_frame:return
	capture_frame=frame;var starts:={};var rows:=[]
	for index in rd.get_captured_timestamps_count():
		var name:=rd.get_captured_timestamp_name(index)
		if name not in ["sandcastle_boundary_start","sandcastle_boundary_end","sandcastle_async_water_tick_start","sandcastle_async_water_tick_end"]:continue
		var ns:=rd.get_captured_timestamp_gpu_time(index)
		if name.ends_with("_start"):starts[name.trim_suffix("_start")]=ns
		else:
			var key:=name.trim_suffix("_end")
			if starts.has(key):rows.append({"frame":frame,"pass":key,"gpu_ns":ns-starts[key],"observed_time_s":time});starts.erase(key)
	call_deferred("_receive",rows)

func _receive(rows: Array) -> void:
	if collecting:timings.append_array(rows)

extends "res://tools/parameter_windows/scene_profile.gd"

# Visible-window viewport timing only. Do not inherit the idle profiler's
# per-frame RenderingDevice timestamp polling: it is not used by these metrics.
func _process(_delta: float) -> bool:
	if phase.is_empty():return false
	var now:=Time.get_ticks_usec()
	var p=beach.runtime.current
	var viewport_times:={}
	for viewport in viewports:
		viewport_times[str(viewport.get_path())]={"cpu_ms":RenderingServer.viewport_get_measured_render_time_cpu(viewport.get_viewport_rid()),"gpu_ms":RenderingServer.viewport_get_measured_render_time_gpu(viewport.get_viewport_rid())}
	rows.append({"phase":phase,"us":now,"frame_ms":(now-previous_us)/1000.0,"process_ms":Performance.get_monitor(Performance.TIME_PROCESS)*1000.0,"physics_ms":Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0,"render_cpu_ms":RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()),"render_gpu_ms":RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()),"setup_cpu_ms":RenderingServer.get_frame_setup_time_cpu(),"tick":p.completed_tick,"sim_s":p.advanced_time_s,"pending":p.pending_count(),"active":p.active_count(),"ready":beach.ready_for_ticks,"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"focused":root.has_focus(),"viewports":viewport_times})
	previous_us=now
	return false

func _wall_wait(seconds: float) -> void:
	var deadline:=Time.get_ticks_usec()+int(seconds*1000000.0)
	while Time.get_ticks_usec()<deadline:await process_frame

func run() -> void:
	var size := Vector2i(1280,720)
	for arg in OS.get_cmdline_user_args():
		if arg == "--1080p": size=Vector2i(1920,1080)
	DisplayServer.window_set_size(size)
	root.content_scale_size=size
	beach=load(scene_path).instantiate()
	beach.playing=false
	root.add_child(beach)
	current_scene=beach
	var deadline:=Time.get_ticks_msec()+90000
	while (not beach.ready_for_ticks or beach._booting) and beach.last_error.is_empty() and Time.get_ticks_msec()<deadline: await process_frame
	if not beach.ready_for_ticks: push_error("G0_BOOT: "+str(beach.last_error));quit(1);return
	var water: ShaderMaterial=beach.get_node("GpuWaterSurface").material_override
	var variant:="candidate"
	if "--foam-baseline" in OS.get_cmdline_user_args():
		variant="baseline"
		var values:={}
		for u in water.shader.get_shader_uniform_list():values[u.name]=water.get_shader_parameter(u.name)
		var original:=Shader.new()
		original.code=FileAccess.get_file_as_string("res://task/water_foam_visual/验收/G4/before_integration/assets/water_material_natural_candidate/async_rdc_water.gdshader")
		if original.code.is_empty():push_error("G0_BASELINE_MISSING");quit(1);return
		water.shader=original
		for u in original.get_shader_uniform_list():
			if values.has(u.name):water.set_shader_parameter(u.name,values[u.name])
		beach.get_node("ShoreContactOverlay").material_override.set_shader_parameter("natural_contact_gain",1.0)
	var p=beach.runtime.current
	while p.completed_tick<240:
		var error: StringName=p.request_tick(1.0/30.0)
		if not error.is_empty():push_error(error);quit(1);return
		deadline=Time.get_ticks_msec()+30000
		while (p.pending_count()!=0 or p.active_count()!=0) and Time.get_ticks_msec()<deadline:await process_frame
		if Time.get_ticks_msec()>=deadline:push_error("G0_TICK_TIMEOUT");quit(1);return
	var service=root.get_node("Parameters")
	for group in service.GROUPS:service.get_node(group).hide()
	root.grab_focus()
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	viewports=root.find_children("*","SubViewport",true,false)
	for viewport in viewports:RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(),true)
	var metadata={"engine":Engine.get_version_info(),"adapter":RenderingServer.get_video_adapter_name(),"driver":RenderingServer.get_current_rendering_driver_name(),"window":DisplayServer.window_get_size(),"viewport":root.size,"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"configuration":beach.configuration,"camera":var_to_str(beach.player_camera.global_transform),"scene":scene_path,"intervals":[],"note":"Visible formal load; fixed completed tick 240 then live; viewport timing only; no screenshot, recording or synchronous readback during sampling; GPU viewport render time does not claim to include asynchronous simulation compute."}
	metadata.foam_variant=variant
	metadata.rd_timestamp_polling=false
	metadata.interval_clock="monotonic wall deadline; process-delta timer is not used"
	metadata.water_shader_sha256=water.shader.code.sha256_text()
	metadata.contact_gain=beach.get_node("ShoreContactOverlay").material_override.get_shader_parameter("natural_contact_gain")
	metadata.foam_uniforms={}
	for uniform in water.shader.get_shader_uniform_list():
		var uniform_name: String=uniform.name
		if uniform_name.begins_with("foam_"):
			var value: Variant=water.get_shader_parameter(uniform_name)
			metadata.foam_uniforms[uniform_name]=value.resource_path if value is Texture2D else value
	metadata.props_error_before=String(beach.floating_props.last_error) if beach.floating_props!=null else ""
	for name in ["paused","live"]:
		beach.playing=name=="live"
		await _wall_wait(10.0)
		phase=name;previous_us=Time.get_ticks_usec()
		var started:=previous_us
		var tick: int=p.completed_tick
		var sim: float=p.advanced_time_s
		print("G0_TIMING_BEGIN ",name)
		await _wall_wait(30.0)
		metadata.intervals.append({"phase":name,"start_us":started,"end_us":Time.get_ticks_usec(),"start_tick":tick,"end_tick":p.completed_tick,"start_sim_s":sim,"end_sim_s":p.advanced_time_s})
		phase=""
		print("G0_TIMING_END ",name)
	while collecting:await process_frame
	metadata.last_error=beach.last_error
	metadata.props_error_after=String(beach.floating_props.last_error) if beach.floating_props!=null else ""
	DirAccess.make_dir_recursive_absolute(output)
	FileAccess.open(output.path_join("capture.json"),FileAccess.WRITE).store_string(JSON.stringify({"metadata":metadata,"frames":rows,"gpu":gpu_rows},"",true,true))
	await beach.shutdown()
	quit()

extends "res://tools/parameter_windows/idle_profile.gd"

# Real visible formal scene, with unchanged production boot/configuration.
var scene_path:="res://scenes/playable/test1_geometry.tscn"
var viewports: Array=[]
var detailed_gpu:=false
var timing_off:=false
var coupled_callback: Callable
var tail_callback: Callable
var sampled_tick:=false
var diagnostic_tick:=0

var reference_root:="res://task/water_execution_optimization/baseline/"
var reference_coupled
var reference_done:=false
var reference_error:=""
var reference: GDScript
var owner

func reference_source(name: String) -> String:
	var base:=reference_root+"shaders/simulation/muscl/"
	var source:=FileAccess.get_file_as_string(base+name+".glsl").trim_prefix("#[compute]")
	for _pass in 4:
		for include in ["muscl_spatial.glslinc","muscl_math.glslinc","muscl_stats.glslinc"]:
			source=source.replace("#include \""+include+"\"",FileAccess.get_file_as_string(base+include))
	return source

func install_reference() -> void:
	var rd: RenderingDevice=owner.state.rd
	for name in ["rk_decide","rk_edge","rk_drain","rk_euler","rk_finalize","rk_normalize","rk_validate"]:
		var source:=RDShaderSource.new();source.source_compute=reference_source(name)
		var spirv:=rd.shader_compile_spirv_from_source(source)
		var error:=spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
		if not error.is_empty():reference_installed.call_deferred(error);return
		var shader: RID=owner.water._own(rd.shader_create_from_spirv(spirv))
		var pipeline: RID=owner.water._own(rd.compute_pipeline_create(shader))
		# All candidates preserve descriptor/push layouts. RD validates compatibility.
		owner.water.kernels[name].pipeline=pipeline
	var old=owner.water.muscl
	var recorder=reference.new()
	for name in ["water","rd","images","buffers","sets"]:recorder.set(name,old.get(name))
	owner.water.muscl=recorder;old.water=null
	if owner.water.coupled_recorder.is_valid():
		reference_coupled=load(reference_root+"scripts/simulation/unified_edit/coupled.gd").new()
		for name in ["water","state","rd","images","buffers","sets","kernels","_passes","_erosion_pushes","stage_transport"]:reference_coupled.set(name,owner.coupled.get(name))
		owner.water.coupled_recorder=reference_coupled.record
	reference_installed.call_deferred("")

func reference_installed(error: String) -> void:
	reference_error=error;reference_done=true

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--reference="):reference_root=arg.trim_prefix("--reference=")
		if arg.begins_with("--scene="):scene_path=arg.trim_prefix("--scene=")
		if arg=="--detail-gpu":detailed_gpu=true
		if arg=="--timing-off":timing_off=true
	super._initialize()

func record_coupled(decision: RID, indirect: RID, step: int, live: int) -> void:
	if step==0:
		diagnostic_tick+=1;sampled_tick=diagnostic_tick%16==0
	var rd: RenderingDevice=beach.runtime.current.state.rd
	if sampled_tick:rd.capture_timestamp("scene_profile_coupled_start")
	coupled_callback.call(decision,indirect,step,live)
	if sampled_tick:rd.capture_timestamp("scene_profile_coupled_end")

func record_tail(decision: RID) -> void:
	var rd: RenderingDevice=beach.runtime.current.state.rd
	if sampled_tick:rd.capture_timestamp("scene_profile_visuals_start")
	tail_callback.call(decision)
	if sampled_tick:rd.capture_timestamp("scene_profile_visuals_end")

func install_gpu_detail() -> void:
	var water=beach.runtime.current.water
	coupled_callback=water.coupled_recorder;tail_callback=water.tail_recorder
	if coupled_callback.is_valid():water.coupled_recorder=record_coupled
	if tail_callback.is_valid():water.tail_recorder=record_tail

func _process(delta: float) -> bool:
	super._process(delta)
	if not phase.is_empty():
		var row: Dictionary=rows[-1]
		row.focused=root.has_focus();row.water_record_us=beach.runtime.current.water.last_recording_us
		row.primitives=Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		row.viewports={}
		for viewport in viewports:
			row.viewports[str(viewport.get_path())]={"cpu_ms":RenderingServer.viewport_get_measured_render_time_cpu(viewport.get_viewport_rid()),"gpu_ms":RenderingServer.viewport_get_measured_render_time_gpu(viewport.get_viewport_rid())}
	return false

func run() -> void:
	beach=load(scene_path).instantiate();root.add_child(beach);current_scene=beach
	var deadline:=Time.get_ticks_msec()+90000
	while (not beach.ready_for_ticks or beach._booting) and beach.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	if not beach.ready_for_ticks:push_error("SCENE_PROFILE_BOOT: "+str(beach.last_error));quit(1);return
	var service=root.get_node("Parameters")
	for group in service.GROUPS:service.get_node(group).hide()
	root.grab_focus()
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	viewports=root.find_children("*","SubViewport",true,false)
	for viewport in viewports:RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(),true)
	var p=beach.runtime.current
	beach.playing=false
	while p.pending_count()>0 or p.active_count()>0:await process_frame
	owner=p;reference=load(reference_root+"scripts/simulation/unified_edit/water_muscl.gd")
	RenderingServer.call_on_render_thread(install_reference)
	while not reference_done:await process_frame
	if not reference_error.is_empty():push_error(reference_error);quit(1);return
	beach.playing=true
	diagnostic=load("res://scripts/simulation/unified_edit/diagnostics.gd").new()
	if not timing_off:p.diagnostics=diagnostic;p.heights.diagnostics=diagnostic
	RenderingServer.call_on_render_thread(func():p.state.profile_passes=not timing_off)
	if detailed_gpu:RenderingServer.call_on_render_thread(install_gpu_detail)
	await create_timer(5.0).timeout
	DirAccess.make_dir_recursive_absolute(output)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("scene.png"))
	var metadata={"engine":Engine.get_version_info(),"adapter":RenderingServer.get_video_adapter_name(),"driver":RenderingServer.get_current_rendering_driver_name(),"window":DisplayServer.window_get_size(),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"configuration":beach.configuration,"camera":beach.player_camera.global_transform,"pid":OS.get_process_id(),"scene":scene_path,"intervals":[],"note":"Visible formal scene; default boot and actual saved parameters; no tool input; CPU diagnostics and GPU timestamps enabled; sequential live/paused phases"}
	metadata.runtime_override={"root":reference_root,"sources":JSON.parse_string(FileAccess.get_file_as_string(reference_root+"identity.json")),"note":"Reference MUSCL pipelines and CPU recorders installed after draining boot; all other resources match production configuration."}
	metadata.detailed_gpu=detailed_gpu;metadata.detail_stride_ticks=16
	metadata.timing_off=timing_off
	if timing_off:metadata.note="Visible formal scene; default boot and actual saved parameters; no tool input; CPU diagnostics and simulation GPU timestamps disabled, viewport timing enabled; sequential live/paused phases"
	for name in ["live","paused"]:
		beach.playing=name=="live"
		await create_timer(2.0).timeout
		phase=name;previous_us=Time.get_ticks_usec()
		var started:=previous_us
		var start_tick: int=p.completed_tick
		var start_sim_s: float=p.advanced_time_s
		print("SCENE_PROFILE_BEGIN ",phase)
		await create_timer(20.0 if name=="live" else 10.0).timeout
		metadata.intervals.append({"phase":name,"start_us":started,"end_us":Time.get_ticks_usec(),"start_tick":start_tick,"end_tick":p.completed_tick,"start_sim_s":start_sim_s,"end_sim_s":p.advanced_time_s})
		phase="";print("SCENE_PROFILE_END ",name)
	while collecting:await process_frame
	metadata.last_error=beach.last_error
	metadata.source_drift=[]
	for path in beach.configuration.sources:
		if FileAccess.get_sha256(path)!=beach.configuration.sources[path]:metadata.source_drift.append(path)
	FileAccess.open(output.path_join("capture.json"),FileAccess.WRITE).store_string(JSON.stringify({"metadata":metadata,"frames":rows,"gpu":gpu_rows,"timeline":diagnostic.snapshot()},"",true,true))
	if detailed_gpu:
		RenderingServer.call_on_render_thread(func():p.water.coupled_recorder=coupled_callback;p.water.tail_recorder=tail_callback)
	await beach.shutdown()
	if reference_coupled!=null:reference_coupled.water=null;reference_coupled.state=null;reference_coupled=null
	owner=null
	coupled_callback=Callable();tail_callback=Callable()
	print("SCENE_PROFILE_SAVED ",output)
	quit()

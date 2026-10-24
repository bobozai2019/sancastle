extends "res://tools/parameter_windows/scene_profile.gd"

const REFERENCE="res://task/water_execution_optimization/step2/scripts/simulation/unified_edit/water_muscl.gd"
var original
var candidate
var swapped:=false

func switch_recorder(use_reference: bool) -> void:
	beach.runtime.current.water.muscl=original if use_reference else candidate
	swapped_received.call_deferred()

func swapped_received() -> void:swapped=true

func run() -> void:
	beach=load("res://scenes/playable/test1_geometry.tscn").instantiate();root.add_child(beach);current_scene=beach
	var deadline:=Time.get_ticks_msec()+90000
	while (not beach.ready_for_ticks or beach._booting) and beach.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	if not beach.ready_for_ticks:push_error("COST_BOOT "+str(beach.last_error));quit(1);return
	var service=root.get_node("Parameters")
	for group in service.GROUPS:service.get_node(group).hide()
	root.grab_focus()
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	var p=beach.runtime.current
	candidate=p.water.muscl;original=load(REFERENCE).new()
	for name in ["water","rd","images","buffers","sets"]:original.set(name,candidate.get(name))
	diagnostic=load("res://scripts/simulation/unified_edit/diagnostics.gd").new()
	p.diagnostics=diagnostic
	RenderingServer.call_on_render_thread(func():p.state.profile_passes=true)
	await create_timer(5.0).timeout
	var metadata={"engine":Engine.get_version_info(),"adapter":RenderingServer.get_video_adapter_name(),"driver":RenderingServer.get_current_rendering_driver_name(),"window":DisplayServer.window_get_size(),"vsync":DisplayServer.window_get_vsync_mode(),"configuration":beach.configuration,"camera":beach.player_camera.global_transform,"reference_sha256":FileAccess.get_sha256(REFERENCE),"candidate_sha256":FileAccess.get_sha256("res://scripts/simulation/unified_edit/water_muscl.gd"),"intervals":[],"note":"ABBA recorder comparison within one visible live scene, same resources; evolving state; profiler disabled, bounded CPU diagnostics and GPU timestamps enabled"}
	for name in ["before_1","after_1","after_2","before_2"]:
		swapped=false;RenderingServer.call_on_render_thread(switch_recorder.bind(name.begins_with("before")))
		while not swapped:await process_frame
		await create_timer(2.0).timeout
		phase=name;previous_us=Time.get_ticks_usec()
		var started:=previous_us
		print("MUSCL_COST_BEGIN ",name)
		await create_timer(12.0).timeout
		metadata.intervals.append({"phase":name,"start_us":started,"end_us":Time.get_ticks_usec()})
		phase="";print("MUSCL_COST_END ",name)
	while collecting:await process_frame
	metadata.last_error=beach.last_error
	metadata.source_drift=[]
	for path in beach.configuration.sources:
		if FileAccess.get_sha256(path)!=beach.configuration.sources[path]:metadata.source_drift.append(path)
	DirAccess.make_dir_recursive_absolute(output)
	FileAccess.open(output.path_join("capture.json"),FileAccess.WRITE).store_string(JSON.stringify({"metadata":metadata,"frames":rows,"gpu":gpu_rows,"timeline":diagnostic.snapshot()},"",true,true))
	await beach.shutdown()
	original.water=null;candidate.water=null
	print("MUSCL_COST_SAVED ",output)
	quit()

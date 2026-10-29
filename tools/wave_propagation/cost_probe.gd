extends SceneTree
var output:=""
var solver_id:="muscl_mc_ssprk2_v1"
var warmup_s:=10.0
var duration_s:=60.0
var checks: Array=[]
var failed:=false
var scene
var frames: Array=[]
var edits: Array=[]
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
		if arg.begins_with("--solver="):solver_id=arg.trim_prefix("--solver=")
	call_deferred("run")
func check(label: String,value: bool) -> void:
	checks.append({"label":label,"pass":value});failed=failed or not value
	if not value:push_error(label)
func state() -> Dictionary:
	var p=scene.runtime.current
	return {"at_us":Time.get_ticks_usec(),"advanced_time_s":p.advanced_time_s,"tick":str(p.completed_tick),"revision":str(p.completed_revision),"state_seq":str(p.completed_state_seq),"pending":p.pending_count(),"active":p.active_count(),"accumulator_s":scene._accumulator,"props_error":String(scene.floating_props.last_error),"props_sample_time_s":scene.floating_props.last_sample_time_s,"props_admitted_time_s":scene.floating_props.admitted_time_s,"props_holds":scene.floating_props.holds.duplicate(),"gravel_visible":scene.get_node("GravelLayer").multimesh.visible_instance_count}
func edit_stroke(index: int,elapsed: float) -> void:
	var x: float=[-.75,-.25,.25,.75][index%4]
	var params:={"trench_width_m":.5,"depth_m":.15,"shoulder_width_m":.5}
	var before:=Time.get_ticks_usec()
	var begin: Dictionary=scene.input.begin(&"shovel_v1",Vector2(x,-.5),params,.1,2,.25)
	var move: Dictionary=scene.input.move(Vector2(x,.5)) if begin.accepted else {}
	var end: Dictionary=scene.input.finish() if begin.accepted else {}
	edits.append({"index":index,"elapsed_wall_s":elapsed,"x_m":x,"begin":begin,"move":move,"end":end,"cpu_us":Time.get_ticks_usec()-before})
func run() -> void:
	if output.is_empty() or solver_id not in ["muscl_mc_ssprk2_v1","rusanov_first_order_v1"] or FileAccess.file_exists(output.path_join("result.json")):quit(2);return
	DirAccess.make_dir_recursive_absolute(output);DisplayServer.window_set_size(Vector2i(1280,720));DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED);DisplayServer.window_set_title("Wave propagation full main cost")
	var boot:=Time.get_ticks_usec()
	scene=load("res://scenes/main.tscn").instantiate();scene.playing=false;scene.water_solver_id=solver_id;root.add_child(scene)
	while (not scene.ready_for_ticks or scene._booting) and scene.last_error.is_empty() and Time.get_ticks_usec()-boot<120000000:await process_frame
	check("complete_boot",scene.ready_for_ticks and not scene._booting and scene.last_error.is_empty())
	if failed:quit(1);return
	check("normal_main_process",scene.is_processing())
	var owner=scene.runtime.current
	check("actual_solver",owner.state.water_solver_id==solver_id)
	check("full_visuals",owner.visuals.foam_enabled and owner.visuals.gravel_enabled and owner.visuals.active_count==512)
	check("erosion_enabled",scene.configuration.simulation.enable_erosion)
	check("visible_720p_vsync_off",DisplayServer.get_name()!="headless" and root.visible and DisplayServer.window_get_size()==Vector2i(1280,720) and DisplayServer.window_get_vsync_mode()==DisplayServer.VSYNC_DISABLED)
	var configuration: Dictionary=scene.configuration.duplicate(true)
	var presentation: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(scene.presentation_manifest))
	var hardware:={"engine":Engine.get_version_info(),"adapter":RenderingServer.get_video_adapter_name(),"driver":RenderingServer.get_current_rendering_driver_name(),"display":DisplayServer.get_name(),"window":DisplayServer.window_get_size(),"viewport":root.get_visible_rect().size,"vsync":DisplayServer.window_get_vsync_mode(),"camera":str(scene.player_camera.global_transform),"body_layout":"authored_default","render_subdivision":presentation.metadata.settings.render_subdivision,"diagnostics_enabled":owner.diagnostics!=null}
	scene.playing=true
	var warm_start:=Time.get_ticks_usec()
	while Time.get_ticks_usec()-warm_start<int(warmup_s*1000000):await process_frame
	var start:=state();var previous: int=start.at_us;var next_edit:=5.0;var index:=0
	while true:
		await process_frame
		var now:=Time.get_ticks_usec();var elapsed:=float(now-int(start.at_us))/1000000.0
		var sample:=state();sample.frame_interval_us=now-previous;sample.elapsed_wall_s=elapsed;sample.focused=root.has_focus();frames.append(sample);previous=now
		if elapsed>=duration_s:break
		if elapsed>=next_edit:edit_stroke(index,elapsed);index+=1;next_edit+=5.0
	var finish:=state()
	check("no_runtime_fault",scene.last_error.is_empty() and owner.fault_reason().is_empty())
	check("no_props_fault",scene.floating_props.last_error.is_empty())
	check("continued_ticks",int(finish.tick)>int(start.tick))
	var terminals: Array=scene.input.terminal.duplicate(true)
	var memory:={"static_bytes":int(Performance.get_monitor(Performance.MEMORY_STATIC)),"video_memory_bytes":int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)),"node_count":int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),"object_count":int(Performance.get_monitor(Performance.OBJECT_COUNT))}
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("frame_after_window.png"))
	scene.playing=false
	await scene.shutdown();check("released",scene.unified_release_complete())
	var drift: Array=[]
	for path in configuration.sources:
		if FileAccess.get_sha256(path)!=configuration.sources[path]:drift.append(path)
	check("source_integrity",drift.is_empty())
	FileAccess.open(output.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"schema":1,"outcome":"fail" if failed else "measured","checks":checks,"solver_id":solver_id,"configuration":configuration,"hardware":hardware,"boot_us":int(start.at_us)-boot-int(warmup_s*1000000),"warmup_wall_s":float(int(start.at_us)-warm_start)/1000000.0,"requested_window_s":duration_s,"start":start,"finish":finish,"frames":frames,"edits":edits,"terminals_observed_at_window_end":terminals,"memory_after_window":memory,"source_drift":drift,"limitations":"Normal main automatic tick admission, queue cap, all consumers and rendering retained. Frame intervals and CPU-completed water timestamps share the process monotonic clock; CPU publication endpoints are quantized. No per-pass GPU profiling or per-tick substep trace. Screenshot and shutdown are outside the measured window."},"\t"))
	quit(1 if failed else 0)

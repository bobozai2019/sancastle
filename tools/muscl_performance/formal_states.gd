extends "res://tools/muscl_performance/variant_states.gd"

var beach
var ticks:=120
var scene_path:="res://scenes/playable/test1_geometry.tscn"

func before_tick(_tick: int) -> void:
	pass

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--ticks="):ticks=int(arg.trim_prefix("--ticks="))
		if arg.begins_with("--scene="):scene_path=arg.trim_prefix("--scene=")
	super._initialize()

func run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	check("zip_open",state_zip.open(output.path_join("states.zip"))==OK)
	beach=load(scene_path).instantiate();beach.playing=false
	root.add_child(beach);current_scene=beach
	var deadline:=Time.get_ticks_msec()+90000
	while (not beach.ready_for_ticks or beach._booting) and beach.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	check("formal_boot",beach.ready_for_ticks and beach.last_error.is_empty())
	if not beach.ready_for_ticks:
		FileAccess.open(output.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"pass":false,"phase":"formal_boot","last_error":beach.last_error,"booting":beach._booting,"message":beach.action_message,"scene":scene_path,"runtime_state":beach.runtime.state if "state" in beach.runtime else null},"\t"))
		state_zip.close();quit(1);return
	owner=beach.runtime.current
	check("held_at_initial_tick",owner.completed_tick==0 and not beach.playing)
	var service=root.get_node("Parameters")
	for group in service.GROUPS:service.get_node(group).hide()
	case_name="formal_scene2";capture_index=0
	var frozen: Dictionary=beach.configuration.duplicate(true)
	FileAccess.open(output.path_join("formal_configuration.bin"),FileAccess.WRITE).store_buffer(var_to_bytes(frozen))
	for tick in ticks:
		await before_tick(tick)
		check("formal_tick_admitted",owner.request_tick(1.0/30.0).is_empty())
		deadline=Time.get_ticks_msec()+30000
		while (owner.pending_count()>0 or owner.active_count()>0) and owner.fault_reason().is_empty() and Time.get_ticks_msec()<deadline:await process_frame
		check("formal_tick_complete",owner.completed_tick==tick+1 and owner.fault_reason().is_empty())
		capture_done=false;RenderingServer.call_on_render_thread(capture_render)
		while not capture_done and Time.get_ticks_msec()<deadline:await process_frame
		check("formal_captured",capture_done)
		if failed:break
	check("zip_finish",state_zip.close()==OK)
	await RenderingServer.frame_post_draw
	check("formal_image_saved",root.get_texture().get_image().save_png(output.path_join("scene.png"))==OK)
	var drift: Array=[]
	for path in frozen.sources:
		if FileAccess.get_sha256(path)!=frozen.sources[path]:drift.append(path)
	check("formal_source_identity",drift.is_empty())
	await beach.shutdown()
	check("formal_released",owner.released)
	FileAccess.open(output.path_join("variant.json"),FileAccess.WRITE).store_string(JSON.stringify({"pass":not failed,"checks":checks,"observations":variant_rows,"injections":[],"configuration":frozen,"source_drift":drift,"engine":Engine.get_version_info(),"scope":"Formal scene boot held at tick zero, manual fixed public request_tick inputs, actual public double slots/control/audit and CPU completion/ledger every tick; not performance data"},"\t"))
	owner=null
	quit(1 if failed else 0)

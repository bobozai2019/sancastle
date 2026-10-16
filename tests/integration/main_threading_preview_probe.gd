extends SceneTree
const BrushProtocol=preload("res://scripts/simulation/brushes/brush_protocol.gd")

var preview
var output:=""
var checks:=[]
var failed:=false
var observations:=[]

func check(name: String, passed: bool) -> void:
	checks.append({"name":name,"pass":passed});failed=failed or not passed;print("MAIN_THREADING ",name," ",passed)

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):output=argument.trim_prefix("--output=")
	call_deferred("_run")

func idle() -> bool:
	var deadline:=Time.get_ticks_msec()+15000
	while Time.get_ticks_msec()<deadline and preview.last_error.is_empty():
		if not preview.busy and not preview.input_running and not preview.input_scheduler.pumping and preview.command_queue.pending.is_empty():return true
		await process_frame
	return false

func command(kind: StringName) -> Dictionary:
	return {"domain_id":preview.domain.domain_id,"generation":preview.generation,"sim_tick":preview.completed_ticks,
		"command_id":maxi(preview.input_serial,preview.command_queue.last_command_id)+1,"kind":kind,"shape":&"circle",
		"transform":{"position_m":Vector3(-2,0,0),"end_position_m":Vector3(-2,0,0)},"radius_m":0.3,"strength":1.0,"amount_m3":0.015,"seed":101}

func _run() -> void:
	root.size=Vector2i(1920,1080);DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	preview=load("res://scenes/main.tscn").instantiate();preview.playing=false;root.add_child(preview)
	var deadline:=Time.get_ticks_msec()+45000
	while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	check("main_ready",preview.ready_for_ticks and preview.last_error.is_empty())
	if not failed:
		check("scene_options",preview.edit_physics_wait_count==1 and preview.edit_tick_overlap_enabled and preview.gravel_enabled and preview.enable_brush_checkpoint_v4 and preview.enable_brush_native_material)
		check("initial_idle",await idle());preview.observe_gpu_wait_phases=true
		for kind in [&"remove_sand",&"place_sand"]:
			var result: Dictionary=await preview.apply_gpu_command(command(kind))
			check("paused_"+kind,result.get("status")==1 and preview.last_error.is_empty());observations.append(result)
		check("one_physics_boundary",preview.gpu_wait_phases.filter(func(row):return row.phase=="physics_one").size()==2 and preview.gpu_wait_phases.filter(func(row):return row.phase=="physics_two").is_empty())
		preview.playing=true;preview.accumulator=preview.SIM_DELTA
		for index in 5:
			while preview.tick_pending:await process_frame
			var result: Dictionary=await preview.apply_gpu_command(command(&"remove_sand"))
			check("live_edit_"+str(index),result.get("status")==1 and preview.last_error.is_empty())
			if failed:break
		preview.playing=false;check("live_drain",await idle());check("publication_overlap_exercised",preview.edit_overlap_ticks_started>0)
		check("real_execution_ticks",preview.gpu_prefix.all(func(row):return row.execution_tick<=preview.completed_ticks and row.result.applied_tick==row.execution_tick))
		check("font_resource",preview.get_node("Interface/EditPanel").theme.resource_path=="res://assets/ui/main_explicit_font.tres")
		check("shape_stroke_begin",(await preview.begin_shape_stroke(701)).is_empty())
		var brush:=BrushProtocol.make_command(&"wall_v1",{"height_m":0.2,"bottom_width_m":1.0,"top_width_m":0.5},Vector2(3,-0.25),Vector2(3,0.25),preview.domain.domain_id,preview.generation,preview.command_queue.last_command_id+1,701,0,preview.completed_ticks,preview.shape_baseline_token)
		check("shape_parameters_valid",not brush.is_empty())
		brush.material_profile_id=&"molded_v1"
		var brush_id: int=brush.get("command_id",-1)
		check("shape_admitted",preview.input_scheduler.submit(brush).is_empty())
		preview.input_running=true;preview.call_deferred("_drain_input")
		check("shape_drained",await idle())
		var applied: Array=preview.input_scheduler.terminal.filter(func(row):return row.command.command_id==brush_id)
		check("current_v2_shape_applied",applied.size()==1 and applied[0].result.get("status")==1)
		check("shape_stroke_end",(await preview.end_shape_stroke()).is_empty())
		var drop: Dictionary=await preview.drop_gravel(Vector2(1,1),2)
		check("current_gravel_drop",drop.get("ok",false) and drop.active_count==514)
	var error: String=preview.last_error
	await preview.shutdown();check("normal_release",preview.gpu_release_done and preview.solver.rd==null)
	var overlap: int=preview.edit_overlap_ticks_started;var tick: int=preview.completed_ticks
	preview.queue_free();await process_frame
	if not output.is_empty():
		var file:=FileAccess.open(output,FileAccess.WRITE);file.store_string(JSON.stringify({"pass":not failed and error=="","checks":checks,"observations":observations,"overlap_ticks":overlap,"completed_ticks":tick,"runtime_error":error,"scope":"Current main with gravel/brush retained; physics1 and ordinary edit publication overlap short smoke, no batch or formal performance claim"},"\t"));file.close()
	quit(1 if failed or error!="" else 0)

extends "res://tests/integration/unified_edit_playable_probe.gd"

const Presentation=preload("res://scripts/simulation/unified_edit/presentation.gd")
var mode:="suite"
var close_finished:=false

func _run() -> void:
	mode=scene_key.get_slice("_",0);scene_key=scene_key.trim_prefix(mode+"_")
	orphan_baseline=int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	DisplayServer.window_set_size(Vector2i(1280,720))
	scene=load(_entry_path(scene_key)).instantiate();scene.playing=false;scene.generation=1001;root.add_child(scene)
	var start:=Time.get_ticks_msec()
	while not scene.ready_for_ticks and scene.last_error.is_empty() and Time.get_ticks_msec()-start<_ready_timeout_ms():await process_frame
	observations.startup_ms=Time.get_ticks_msec()-start
	check("lifecycle_entry_ready",scene.ready_for_ticks and scene.last_error.is_empty())
	if not scene.ready_for_ticks:await _close();return
	observations.sources=scene.configuration.sources.duplicate(true)
	if mode=="suite":await _suite()
	elif mode=="save":await _save_saturated()
	elif mode=="close":await _close_recorded()
	else:check("known_mode",false)
	await _close()

func _suite() -> void:
	var owner=scene.runtime.current;owner.hold_completions=true
	var data:=Presentation.read(scene.presentation_manifest)
	var seed:=Presentation.initial_domain(data.metadata,1001)
	var wet:=Vector2.ZERO;var depth:=-1.0
	for z in range(32,224):
		for x in range(32,224):
			var water: float=seed.domain.water[z*256+x]
			if water>depth:depth=water;wet=Vector2((x+0.5)*0.125-16.0,(z+0.5)*0.125-16.0)
	observations.wet_point={"x":wet.x,"z":wet.y,"initial_depth":depth}
	check("actual_seed_suspended_target_depth_recorded",depth>=0.0)
	var tools:={&"remove_sand":"Dig",&"place_sand":"Fill",&"suspended_sand":"SuspendedSand",&"gravel_drop":"GravelDrop",&"castle_v1":"Castle",&"wall_v1":"Wall",&"shovel_v1":"Shovel"}
	for tool in tools:
		scene.panel.get_node("Margin/Controls/Tools/"+tools[tool]).pressed.emit()
		check(String(tool)+"_fixed_ui_selection",scene.selected_sand_tool==tool and scene.input.gesture.is_empty())
		var point:=wet if tool==&"suspended_sand" else Vector2(-4,-4)
		var parameters: Dictionary=scene.panel.parameters()
		check(String(tool)+"_begin",scene.input.begin(tool,point,parameters,0.1,3,0.25).accepted)
		if tool!=&"castle_v1":
			var delta:=Vector2(1.1,0.2) if tool in [&"suspended_sand",&"gravel_drop"] else Vector2(4.8,3.6)
			var moved: Dictionary=scene.input.move(point+delta)
			check(String(tool)+"_drag",moved.accepted)
			if not moved.accepted:print("TOOL_MOVE_ERROR ",tool," ",moved)
		# The next fixed tool signal closes the current gesture, including its
		# BEGIN/END when baseline/coverage is required.
	scene._finish_ui_stroke(false)
	for tool in [&"smooth_v1",&"compact_v1"]:
		var profile: Dictionary=scene.registry.profile(tool)
		check(String(tool)+"_public_input_begin",scene.input.begin(tool,Vector2(-3,-3),profile.defaults,0.1,0,0.0).accepted)
		check(String(tool)+"_public_input_move",scene.input.move(Vector2(-2.7,-3)).accepted)
		check(String(tool)+"_public_input_end",scene.input.finish().accepted)
	check("all_declarations_precede_cpu_receipts",scene.input.terminal.is_empty() and scene.input.waiting.size()>20)
	var declared:={}
	for work in owner._pending:
		var command: Dictionary=work.command
		if work.kind==L.WorkKind.EDIT:
			declared[str(command.command_id)]={"profile_id":command.profile_id,"profile_version":command.profile_version,"effective_hash":command.configuration.get("effective_hash","0".repeat(64)),"start":[command.start_xz_m.x,command.start_xz_m.y],"end":[command.end_xz_m.x,command.end_xz_m.y],"parameters":command.parameters.duplicate(true)}
		else:declared[str(command.command_id)]={"profile_id":"gravel_drop","profile_version":1,"effective_hash":command.effective_hash,"count":command.count}
	observations.declarations=declared
	owner.hold_completions=false;await _idle()
	observations.results=scene.input.terminal.duplicate(true)
	var outcomes:={};var profiles:={}
	for row in scene.input.terminal:
		var declaration: Dictionary=declared[str(row.command_id)]
		var name: String=declaration.profile_id
		outcomes[name]=outcomes.get(name,0)+1
		check("terminal_"+str(row.command_id),row.get("outcome",-1) in [L.Outcome.APPLIED,L.Outcome.NO_CHANGE])
		if row.get("profile_version",0)>0:
			if name!="gravel_drop":profiles[name]=true
			check("effective_declaration_"+str(row.command_id),row.effective_hash==declaration.effective_hash and row.profile_version==declaration.profile_version)
	observations.results=scene.input.terminal.duplicate(true);observations.outcomes=outcomes
	check("all_eleven_physical_profiles_reached_common_results",profiles.size()==11)
	check("tool_switches_leave_no_stroke",owner.accounting.stroke.is_empty() and scene.input.gesture.is_empty())
	check("paused_tool_suite_does_not_advance_water_clock",owner.completed_tick==0 and owner.advanced_time_s==0.0)
	await RenderingServer.frame_post_draw
	check("suite_render",root.get_texture().get_image().save_png(output+"/suite.png")==OK)

func _save_saturated() -> void:
	scene.panel.get_node("Margin/Controls/Tools/Wall").pressed.emit()
	var owner=scene.runtime.current
	check("open_wall_for_full_queue",scene.input.begin(&"wall_v1",Vector2(3,0),scene.panel.parameters(),0.1,3,0.25).accepted)
	var profile: Dictionary=scene.registry.profile(&"fill_v1")
	for index in 62:
		var next: Dictionary=scene.input._id()
		var request:={"domain_id":scene._domain_id(),"generation":scene.generation,"command_id":next.value,"sim_tick":0,"profile_id":&"fill_v1","profile_version":profile.version,"profile_hash":profile.profile_hash,"start_xz_m":Vector2(-4,-4),"end_xz_m":Vector2(-4,-4),"parameters":{"radius_m":0.25,"amount_m3":0.01,"strength":1.0,"speed_m_s":0.0},"features":{"water_policy":0},"source_context":"lifecycle_queue_fill","seed":index}
		check("fill_queue_"+str(index),scene.input._remember(scene.runtime.submit_intent(request)).accepted)
	check("actual_pending_queue_saturated",owner.pending_count()==64)
	scene._finish_ui_stroke(false)
	check("end_retained_under_real_queue_backpressure",scene.input.end_requested=="end" and not scene.input.gesture.is_empty() and scene.input.last_error==&"queue_full")
	var path:=output+"/saturated.sandue"
	check("save_waits_for_retained_end",(await scene.save_gpu_checkpoint(path)).is_empty())
	await _idle()
	var saved:=Codec.load(path,scene.configuration)
	check("saturated_native_container_valid",saved.error.is_empty())
	if saved.error.is_empty():
		var published:=0
		for row in scene.input.terminal:published=maxi(published,int(row.get("state_seq",0)))
		check("exact_all_accepted_work_and_one_end_in_save",saved.checkpoint.highwater_id==65 and saved.checkpoint.state_seq==published and published>0 and saved.checkpoint.sim_tick==0)
		check("saturated_save_preserves_selection",saved.checkpoint.selection.brush.tool==&"wall_v1")
		observations.saved={"path":path,"sha256":FileAccess.get_sha256(path),"state_seq":saved.checkpoint.state_seq,"highwater_id":saved.checkpoint.highwater_id,"sim_tick":saved.checkpoint.sim_tick}
	check("end_receipt_consumed_and_baseline_closed",scene.input.waiting.is_empty() and scene.input.gesture.is_empty() and scene.input.end_requested.is_empty() and owner.accounting.stroke.is_empty())
	check("all_65_results_consumed",scene.input.terminal.size()==65)
	for row in scene.input.terminal:check("saved_terminal_"+str(row.command_id),row.get("outcome",-1) in [L.Outcome.APPLIED,L.Outcome.NO_CHANGE])
	observations.results=scene.input.terminal.duplicate(true);observations.events=scene.runtime.events.duplicate(true)

func _close_recorded() -> void:
	var owner=scene.runtime.current;owner.hold_completions=true
	check("close_open_wall",scene.input.begin(&"wall_v1",Vector2(3,0),scene.registry.profile(&"wall_v1").defaults,0.1,3,0.25).accepted)
	check("close_water_queued",scene.runtime.request_tick(0.001).is_empty())
	var next: Dictionary=scene.input._id()
	check("close_display_queued",scene.input._remember(scene.runtime.submit_display_intent({"domain_id":scene._domain_id(),"generation":scene.generation,"command_id":next.value,"sim_tick":0,"point_xz_m":Vector2(3,0),"count":7})).accepted)
	var start:=Time.get_ticks_msec()
	while owner.active_count()<3 and Time.get_ticks_msec()-start<15000:await process_frame
	check("three_actual_work_slots_held",owner.active_count()==3 and scene.input.terminal.is_empty())
	call_deferred("_start_shutdown")
	while not scene.runtime.closing and Time.get_ticks_msec()-start<20000:await process_frame
	for frame in 3:await process_frame
	check("close_retains_recorded_owner",scene.runtime.current==null and scene.runtime.retired.size()==1 and not owner.released and not close_finished)
	owner.hold_completions=false
	start=Time.get_ticks_msec()
	while not close_finished and Time.get_ticks_msec()-start<30000:await process_frame
	check("close_finishes_after_real_receipts",close_finished and owner.released and scene.runtime.closed and scene.input.waiting.is_empty())
	check("all_three_input_results_retained_on_close",scene.input.terminal.size()==3)
	for row in scene.input.terminal:check("closed_terminal_"+str(row.command_id),row.get("outcome",-1) in [L.Outcome.APPLIED,L.Outcome.NO_CHANGE])
	observations.results=scene.input.terminal.duplicate(true);observations.events=scene.runtime.events.duplicate(true)

func _start_shutdown() -> void:
	await scene.shutdown();close_finished=true

func finish() -> void:
	FileAccess.open(output+"/probe.json",FileAccess.WRITE).store_string(JSON.stringify({"pass":not failed,"checks":checks,"observations":observations,"scope":"Candidate fixed tool declarations and API profiles, retained stroke END at queue capacity, recorded edit/water/display close; no formal cutover or performance claim"},"\t"))
	quit(1 if failed else 0)

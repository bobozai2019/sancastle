extends "res://tests/water_material_natural/rdc_main_smoke.gd"

var cases := []
var submitted := []

func settled() -> void:
	var deadline:=Time.get_ticks_msec()+60000
	while preview.busy or preview.input_running or not preview.command_queue.pending.is_empty() or preview.collision_proxy.staging_texture.is_valid() or not preview.collision_proxy.pending_revisions.is_empty() or preview.collision_proxy.has_prepare_in_flight():
		if Time.get_ticks_msec()>deadline:_check("drain_timeout",false);return
		await process_frame

func submit_command(kind: StringName, index: int, amount: float) -> void:
	preview.input_serial+=1
	var point:=Vector3(-2.0+float(index)*0.1,0.0,0.0)
	var command: Dictionary={"domain_id":preview.domain.domain_id,"generation":preview.generation,
		"sim_tick":preview.completed_ticks,"command_id":preview.input_serial,"kind":kind,"shape":&"circle",
		"transform":{"position_m":point,"end_position_m":point},"radius_m":0.3,"strength":1.0,
		"amount_m3":amount,"seed":101}
	var error: StringName=preview.input_scheduler.submit(command)
	submitted.append({"command":command,"error":String(error),"at_usec":Time.get_ticks_usec()})
	if error.is_empty() and not preview.input_running:
		preview.input_running=true;preview.call_deferred("_drain_input")

func run_case(name: String) -> void:
	var begin:=submitted.size()
	var tick: int=preview.completed_ticks
	var phase_rows := []
	var start:=Time.get_ticks_usec()
	preview.playing=true
	var index:=0
	while Time.get_ticks_usec()-start<10000000 and preview.last_error.is_empty():
		if index<30 and Time.get_ticks_usec()-start>=index*300000+100000:
			var kind: StringName=&"remove_sand" if name=="dig" or (name=="alternate" and index%2==0) else &"place_sand"
			submit_command(kind,index,[0.01,0.1,1.0][index%3]);index+=1
		for phase in preview.gpu_wait_phases:phase_rows.append(phase.duplicate(true))
		preview.gpu_wait_phases.clear()
		await process_frame
	var stop:=Time.get_ticks_usec();var stop_tick: int=preview.completed_ticks
	preview.playing=false
	await settled()
	for phase in preview.gpu_wait_phases:phase_rows.append(phase.duplicate(true))
	preview.gpu_wait_phases.clear()
	var accepted := {}
	for row in submitted.slice(begin):
		if row.error.is_empty():accepted[row.command.command_id]=true
	var completed := {}
	var valid:=true
	for row in preview.input_results:
		var id: int=row.command.command_id
		if not accepted.has(id):continue
		completed[id]=true
		valid=valid and row.result.get("status") in [1,2] and row.result.get("invalid_flags",-1)==0
	var paired:=true
	var physics_checked:=0
	for id in accepted:
		var phases := {}
		for row in phase_rows:
			if row.command_id==id:phases[row.phase]=row
		if phases.has("collision_ready"):
			physics_checked+=1
			paired=paired and phases.has("physics_one") and phases.has("physics_two") and phases.physics_two.physics_frame>=phases.physics_one.physics_frame+1
	_check(name+"_accepted_commands_terminal",accepted.size()>=10 and accepted==completed and valid,{"accepted":accepted.size(),"completed":completed.size(),"attempts":index})
	_check(name+"_two_physics_frames_preserved",paired and physics_checked>0,physics_checked)
	_check(name+"_ticks_progress_and_no_prepare_left",stop_tick>tick and not preview.collision_proxy.has_prepare_in_flight() and preview.last_error.is_empty())
	var path:=output.path_join(name+".scgpu")
	var saved: StringName=await preview.save_gpu_checkpoint(path)
	_check(name+"_complete_checkpoint",saved.is_empty(),saved)
	cases.append({"name":name,"start_usec":start,"stop_usec":stop,"start_tick":tick,"stop_tick":stop_tick,
		"commands":submitted.slice(begin),"terminals":preview.input_results.duplicate(true),"phases":phase_rows,
		"prepare_policy":preview.collision_proxy.prepare_policy,"reclaimed":preview.collision_proxy.prepare_scheduler.reclaimed_groups,
		"fallbacks":preview.collision_proxy.prepare_backpressure_fallbacks})

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	root.size=Vector2i(1280,720)
	preview=load("res://scenes/main.tscn").instantiate();preview.playing=false;root.add_child(preview)
	var deadline:=Time.get_ticks_msec()+90000
	while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	_check("main_ready",preview.ready_for_ticks and preview.last_error.is_empty())
	if not preview.ready_for_ticks:_finish();quit(1);return
	await settled()
	preview.observe_gpu_wait_phases=true
	for name in ["dig","fill","alternate"]:await run_case(name)
	await preview.shutdown()
	_check("clean_shutdown",preview.gpu_release_done and not preview.collision_proxy.has_prepare_in_flight())
	var file:=FileAccess.open(output.path_join("continuous.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"cases":cases,"engine":Engine.get_version_info(),
		"scope":"1280x720 short functional windows; serial GPU transactions; not formal 1080p costs"},"\t"));file.close()
	var passed:=true
	for row in checks:passed=passed and row.pass
	quit(0 if passed else 1)

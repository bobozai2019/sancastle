extends "res://tests/integration/collision_lifecycle_window_probe.gd"

func run_edit_case(stage: String, kind: String) -> void:
	var label: String="edit_"+stage+"_"+kind
	var folder: String=output.path_join(label);DirAccess.make_dir_recursive_absolute(folder)
	if not await fresh(folder):return
	var proxy=scene.collision_proxy
	var scheduler:=GatedScheduler.new()
	proxy.prepare_scheduler=scheduler;proxy.prepare_policy="worker1";proxy.set_process(false)
	scene.selected_sand_tool=&"remove_sand";scene.dig_amount_m3=0.005
	var screen: Vector2=scene.player_camera.unproject_position(Vector3(-2.0,0.0,0.0))
	var hit: Dictionary=scene.pick(screen)
	check(label+"_current_jolt_pick",not hit.is_empty() and scene._pick_current(hit))
	var before: int=scene.input_events.size()
	var click:=InputEventMouseButton.new();click.position=screen;click.button_index=MOUSE_BUTTON_LEFT;click.pressed=true
	scene._unhandled_input(click)
	click.pressed=false;scene._input(click)
	check(label+"_command_admitted",scene.input_events.size()==before+1)
	var deadline:=Time.get_ticks_msec()+30000
	while scheduler.active==null and Time.get_ticks_msec()<deadline:await process_frame
	if scheduler.active==null:check(label+"_prepare_started",false);return
	var job: RefCounted=scheduler.active
	var entered:=false
	while not entered and Time.get_ticks_msec()<deadline:
		entered=job.entered.try_wait()
		if not entered:await process_frame
	check(label+"_actual_edit_prepare",entered and scene.gpu_busy and scene.pending_gpu_command.command_id==scene.input_events[-1].command.command_id)
	if not entered:job.resume.post();proxy.set_process(true);return
	var group: int=scheduler.group_id
	if stage!="preparing":
		job.resume.post()
		while not WorkerThreadPool.is_group_task_completed(group) and Time.get_ticks_msec()<deadline:await process_frame
		check(label+"_prepared",WorkerThreadPool.is_group_task_completed(group))
	if stage=="submitted":proxy._process(0.0)
	var command_id: int=scene.input_events[-1].command.command_id
	var record: Dictionary={"stage":stage,"kind":kind,"command_id":command_id,
		"gpu_busy_at_action":scene.gpu_busy,"input_running_at_action":scene.input_running,
		"generation":job.request.generation,"captured_revision":job.request.captured_revision,
		"chunks":Array(job.request.chunks),"worker_thread_id":job.entered_thread_id,
		"slot_status":String(job.slots[0].status),"physics_frame_at_action":Engine.get_physics_frames()}
	action_done=false;action_error=""
	perform(kind,folder)
	for frame in 3:await process_frame
	if kind=="restore":check(label+"_busy_restore_rejected",action_done and action_error=="backend_unavailable")
	elif stage!="submitted":check(label+"_accepted_edit_not_abandoned",not action_done and scene.gpu_busy)
	if stage=="preparing":job.resume.post()
	proxy.set_process(true)
	deadline=Time.get_ticks_msec()+90000
	while not action_done and Time.get_ticks_msec()<deadline:await process_frame
	if kind!="restore":check(label+"_action_finished",action_done and action_error.is_empty(),action_error)
	if kind=="switch":
		var saved: Dictionary=Store.load(service.saved.main.path).checkpoint
		check(label+"_edit_completed_before_switch",saved.gpu_beach_edit.prefix[-1].command.command_id==command_id and saved.gpu_beach_edit.prefix[-1].result.status==1)
		check(label+"_old_owner_freed",service.release_records[-1].gpu_released and service.release_records[-1].node_freed)
		scene=service.active_scene
	else:
		while scene.input_running and Time.get_ticks_msec()<deadline:await process_frame
		check(label+"_accepted_edit_completed",not scene.input_running and scene.input_results[-1].result.status==1 and scene.input_results[-1].command.command_id==command_id)
		if kind=="save":
			var saved: Dictionary=Store.load(folder.path_join("saved.scgpu")).checkpoint
			check(label+"_saved_complete_prefix",saved.gpu_beach_edit.prefix[-1].command.command_id==command_id and saved.gpu_beach_edit.pending_count==0 and saved.gpu_beach_edit.reserved_m3==0.0)
		elif kind=="restore":
			var token: int=scene.generation
			var restored: StringName=await scene.restore_gpu_checkpoint(folder.path_join("origin.scgpu"))
			check(label+"_restore_after_edit_completed",restored.is_empty() and scene.generation>token)
		else:check(label+"_shutdown_released",scene.gpu_release_done and proxy.rd==null)
	check(label+"_all_groups_reclaimed",scheduler.group_id==-1 and not scheduler.has_in_flight() and scheduler.serial_retries==0)
	check(label+"_no_orphan",Scheduler.detached.is_empty())
	record.action_error=action_error;record.reclaimed_groups=scheduler.reclaimed_groups
	cases.append(record)
	await service._dispose_scene(scene);scene=null;service.active_scene=null;current_scene=null

func _run() -> void:
	if output.is_empty():quit(2);return
	DirAccess.make_dir_recursive_absolute(output)
	root.size=Vector2i(1280,720);service=root.get_node("BeachScenes")
	service.session_directory=output.path_join("switch_sessions");DirAccess.make_dir_recursive_absolute(service.session_directory)
	for stage in ["preparing","prepared","submitted"]:
		for kind in ["save","restore","switch","shutdown"]:
			await run_edit_case(stage,kind)
			if failed:break
		if failed:break
	var file:=FileAccess.open(output.path_join("result.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass":not failed,"checks":checks,"cases":cases,
		"engine":Engine.get_version_info(),"scope":"actual admitted GPU dig commands; 12 controlled preparation/publication lifecycle windows; no performance claim"},"\t"));file.close()
	quit(1 if failed else 0)

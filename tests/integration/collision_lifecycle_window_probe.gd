extends SceneTree

const Store = preload("res://scripts/simulation/checkpoint_store.gd")
const Scheduler = preload("res://scripts/collision/collision_prepare_scheduler.gd")

# Test-only worker barrier. Production preparation has no waits or test hooks.
class GatedJob extends "res://scripts/collision/collision_prepare_job.gd":
	var entered := Semaphore.new()
	var resume := Semaphore.new()
	var entered_thread_id := 0
	func prepare_slot(index: int) -> void:
		if index==0:
			entered_thread_id = OS.get_thread_caller_id()
			entered.post()
			resume.wait()
		super.prepare_slot(index)

class GatedScheduler extends "res://scripts/collision/collision_prepare_scheduler.gd":
	func _start_next() -> void:
		if active != null or waiting.is_empty(): return
		var queued: RefCounted = waiting.pop_front()
		active = GatedJob.new(queued.request)
		active.scheduled_usec = Time.get_ticks_usec()
		active.worker_count = 1
		group_id = WorkerThreadPool.add_group_task(active.prepare_slot, active.slots.size(), 1, false, "collision_lifecycle_barrier")

var output := ""
var scene
var service
var checks := []
var cases := []
var action_done := false
var action_error := ""
var failed := false

func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=")
	call_deferred("_run")

func check(name: String, passed: bool, details: Variant = null) -> void:
	checks.append({"name":name,"pass":passed,"details":details})
	failed = failed or not passed
	print("COLLISION_WINDOW_CHECK ",name," ",passed)

func idle() -> void:
	var deadline:=Time.get_ticks_msec()+30000
	while Time.get_ticks_msec()<deadline:
		var proxy=scene.collision_proxy
		if not scene.busy and not scene.input_running and not proxy.staging_texture.is_valid() and proxy.pending_revisions.is_empty() and not proxy.has_prepare_in_flight(): return
		await process_frame
	check("idle_timeout",false)

func fresh(folder: String) -> bool:
	service.saved.clear();service.shared_controls.clear();service.active_scene=null
	scene=load("res://scenes/main.tscn").instantiate();scene.playing=false
	root.add_child(scene);current_scene=scene
	var deadline:=Time.get_ticks_msec()+90000
	while not scene.ready_for_ticks and scene.last_error.is_empty() and Time.get_ticks_msec()<deadline: await process_frame
	check(folder+"_initialized",scene.ready_for_ticks and scene.last_error.is_empty())
	if not scene.ready_for_ticks:return false
	scene.get_node("Interface/PerformancePanel/Margin/Rows/Header/Sampling").button_pressed=false
	await idle()
	var error: StringName=await scene.save_gpu_checkpoint(folder.path_join("origin.scgpu"))
	check(folder+"_origin_save",error.is_empty(),error)
	return error.is_empty()

func perform(kind: String, folder: String) -> void:
	if kind=="save": action_error=String(await scene.save_gpu_checkpoint(folder.path_join("saved.scgpu")))
	elif kind=="restore": action_error=String(await scene.restore_gpu_checkpoint(folder.path_join("origin.scgpu")))
	elif kind=="switch":
		if not service.request_switch("test1_capture"):action_error="switch_rejected"
		else:
			while service.busy: await process_frame
			action_error=service.last_error
	elif kind=="shutdown": await scene.shutdown()
	action_done=true

func run_case(stage: String, kind: String) -> void:
	var label:=stage+"_"+kind
	var folder:=output.path_join(label);DirAccess.make_dir_recursive_absolute(folder)
	if not await fresh(folder): return
	var origin: Dictionary=Store.load(folder.path_join("origin.scgpu")).checkpoint
	var proxy=scene.collision_proxy
	var scheduler:=GatedScheduler.new()
	proxy.prepare_scheduler=scheduler;proxy.prepare_policy="worker1";proxy.set_process(false)
	var chunk: int=proxy.shapes.keys()[0]
	var raw: PackedByteArray=proxy.shapes[chunk].shape.map_data.to_byte_array()
	var apply_before: int=proxy.applied_usec[chunk]
	var token: int=proxy.generation
	var revision: int=scene.solver.state_revision
	var now:=Time.get_ticks_usec()
	proxy._apply_data(raw,PackedInt32Array([chunk]),revision,token,0.0,PackedInt64Array(),now,now)
	var job: RefCounted=scheduler.active
	var deadline:=Time.get_ticks_msec()+5000
	var entered:=false
	while not entered and Time.get_ticks_msec()<deadline:
		entered=job.entered.try_wait()
		if not entered:await process_frame
	check(label+"_worker_entered",entered and job.entered_thread_id!=OS.get_thread_caller_id())
	if not entered:job.resume.post();proxy.set_process(true);return
	var group: int=scheduler.group_id
	if stage!="preparing":
		job.resume.post()
		while not WorkerThreadPool.is_group_task_completed(group) and Time.get_ticks_msec()<deadline:await process_frame
		check(label+"_group_completed_before_action",WorkerThreadPool.is_group_task_completed(group))
	if stage=="submitted":
		proxy._process(0.0)
		check(label+"_shape_ack_before_action",not proxy.has_prepare_in_flight() and proxy.applied_usec[chunk]>=apply_before)
	else:
		check(label+"_not_published_before_action",proxy.applied_usec[chunk]==apply_before and proxy.has_prepare_in_flight())
	var action_start:=Time.get_ticks_usec()
	var stage_record: Dictionary={"stage":stage,"kind":kind,"generation":token,"revision":revision,
		"chunk":chunk,"worker_thread_id":job.entered_thread_id,"main_thread_id":OS.get_thread_caller_id(),
		"group_complete":WorkerThreadPool.is_group_task_completed(group) if stage!="submitted" else true,
		"slot_status":String(job.slots[0].status),"action_start_usec":action_start,
		"physics_frame_at_action":Engine.get_physics_frames(),"raw_hex":raw.hex_encode()}
	action_done=false;action_error=""
	perform(kind,folder)
	if stage!="submitted":
		for frame in 3:await process_frame
		if stage=="preparing" or kind!="shutdown":
			check(label+"_action_waits_for_prepare",not action_done)
		else:
			check(label+"_completed_group_collected_by_shutdown",scheduler.reclaimed_groups==1)
	if stage=="preparing":job.resume.post()
	proxy.set_process(true)
	deadline=Time.get_ticks_msec()+90000
	while not action_done and Time.get_ticks_msec()<deadline:await process_frame
	check(label+"_action_finished",action_done and action_error.is_empty(),action_error)
	stage_record.action_done_usec=Time.get_ticks_usec();stage_record.action_error=action_error
	check(label+"_group_reclaimed_once",scheduler.reclaimed_groups==1 and scheduler.group_id==-1 and not scheduler.has_in_flight())
	if kind=="save":
		var saved: Dictionary=Store.load(folder.path_join("saved.scgpu")).checkpoint
		check(label+"_ten_fields_exact",origin.gpu_beach_native.fields==saved.gpu_beach_native.fields)
		check(label+"_ledger_prefix_exact",origin.gpu_beach_edit.ledger==saved.gpu_beach_edit.ledger and origin.gpu_beach_edit.prefix==saved.gpu_beach_edit.prefix)
	elif kind=="restore":
		check(label+"_new_generation",scene.generation>token and scene.collision_proxy.generation==scene.generation)
		check(label+"_restore_native_verified",scene.beach_restore_verifications[-1].error=="" and scene.beach_restore_verifications[-1].expected==scene.beach_restore_verifications[-1].observed)
	elif kind=="switch":
		check(label+"_target_ready",service.active_scene.scene_key=="test1_capture" and service.active_scene.ready_for_ticks)
		check(label+"_old_scene_released",service.release_records[-1].gpu_released and service.release_records[-1].node_freed)
		scene=service.active_scene
	else:check(label+"_gpu_released",scene.gpu_release_done and scene.collision_proxy.rd==null)
	check(label+"_no_detached_tasks",Scheduler.detached.is_empty())
	cases.append(stage_record)
	await service._dispose_scene(scene)
	scene=null;service.active_scene=null;current_scene=null

func _run() -> void:
	if output.is_empty():quit(2);return
	DirAccess.make_dir_recursive_absolute(output)
	root.size=Vector2i(1280,720)
	service=root.get_node("BeachScenes")
	service.session_directory=output.path_join("switch_sessions")
	DirAccess.make_dir_recursive_absolute(service.session_directory)
	for stage in ["preparing","prepared","submitted"]:
		for kind in ["save","restore","switch","shutdown"]:
			await run_case(stage,kind)
			if failed:break
		if failed:break
	var file:=FileAccess.open(output.path_join("result.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass":not failed,"checks":checks,"cases":cases,
		"engine":Engine.get_version_info(),"detached_left":Scheduler.detached.size(),
		"scope":"12 actual main save/restore/scene-service/shutdown windows; test-only semaphore and process holds; no performance claim"},"\t"));file.close()
	quit(1 if failed else 0)

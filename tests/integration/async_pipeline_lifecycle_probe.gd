extends "res://tests/integration/async_pipeline_restore_probe.gd"

var tasks:={}
var shutdown_calls:=0
var lifecycle_events:=[]

func _save_task(key: String, path: String) -> void:
	tasks[key]={"error":await preview.save_gpu_checkpoint(path)}

func _restore_task(key: String, value: Dictionary) -> void:
	tasks[key]={"error":await preview.restore_gpu_checkpoint_data(value)}

func _drop_task(key: String) -> void:
	tasks[key]=await preview.drop_gravel(Vector2(1,1),2)

func _shutdown_task(key: String) -> void:
	await preview.shutdown()
	shutdown_calls+=1
	tasks[key]={"released":preview.gpu_release_done}

func wait_task(key: String, limit: int=90000) -> bool:
	var end:=Time.get_ticks_msec()+limit
	while not tasks.has(key) and Time.get_ticks_msec()<end:await process_frame
	return tasks.has(key)

func frames(count: int) -> void:
	for i in count:await process_frame

func enqueue(count: int) -> void:
	for i in count:check("lifecycle_enqueue_%d"%i,preview.input_scheduler.submit(command(2000+i)).is_empty())

func wait_slots(count: int) -> bool:
	var end:=Time.get_ticks_msec()+15000
	while preview.async_controller.slots.active_count()<count and Time.get_ticks_msec()<end and preview.last_error.is_empty():await process_frame
	return preview.async_controller.slots.active_count()>=count

func start_ui_stroke() -> void:
	preview._apply_brush_selection({"tool":"wall_v1","parameters":{"height_m":0.2,"bottom_width_m":1.0,"top_width_m":0.5},"dig_amount_m3":0.03,"fill_amount_m3":0.04})
	preview.ui_stroke_identity+=1
	check("lifecycle_ui_begin",preview.stroke_controller.begin_stroke(&"wall_v1",preview.brush_panel.parameters(),Vector2(-2,-0.25),preview.ui_stroke_identity,preview.generation).is_empty())
	check("lifecycle_ui_path",preview.stroke_controller.append_path_sample(Vector2(-2,0.25)).is_empty())
	preview.ui_pressed=true;preview.ui_pump_running=true
	preview.call_deferred("_pump_ui_stroke",preview.generation,preview.ui_stroke_identity)

func switch_scene(service, key: String, expected_error: bool=false) -> bool:
	check("lifecycle_switch_request_"+key,service.request_switch(key))
	var end:=Time.get_ticks_msec()+120000
	while service.busy and Time.get_ticks_msec()<end:await process_frame
	check("lifecycle_switch_terminated_"+key,not service.busy)
	if service.busy:return false
	preview=service.active_scene
	check("lifecycle_switch_result_"+key,not service.last_error.is_empty() if expected_error else service.last_error.is_empty())
	check("lifecycle_switch_new_pipeline_"+key,preview!=null and preview.async_pipeline_enabled and preview.async_backend_ready and preview.ready_for_ticks and preview.last_error.is_empty())
	return preview!=null and preview.ready_for_ticks

func _run() -> void:
	preview=load(scene_path).instantiate();preview.async_pipeline_enabled=true;preview.playing=false
	root.add_child(preview)
	var end:=Time.get_ticks_msec()+60000
	while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_msec()<end:await process_frame
	check("lifecycle_ready",preview.ready_for_ticks and preview.async_backend_ready and preview.last_error.is_empty())
	if preview.ready_for_ticks:
		var base:=output.get_basename()
		preview.playing=true;preview.async_controller.hold_completions=true
		check("lifecycle_running_water_inflight",await wait_slots(3))
		preview.playing=false
		var submitted_water: int=preview.async_controller.submitted_water
		await frames(6)
		check("lifecycle_pause_stops_new_water",preview.async_controller.submitted_water==submitted_water)
		preview.async_controller.hold_completions=false
		check("lifecycle_pause_drains_owned_water",await idle() and preview.completed_ticks>=3)
		var paused_tick: int=preview.completed_ticks
		await frames(4)
		check("lifecycle_pause_keeps_clock",preview.completed_ticks==paused_tick and (await read("clock")).decode_float(0)==preview.async_controller.actual_time)
		preview.async_controller.hold_completions=true
		enqueue(8)
		check("lifecycle_save_three_slots",await wait_slots(3))
		call_deferred("_save_task","overlap",base+"_overlap.sandgp")
		await frames(3)
		check("lifecycle_save_waits_owned_work",preview.async_checkpoint_running and not tasks.has("overlap") and preview.async_controller.slots.active_count()==3 and preview.solver.rd!=null)
		check("lifecycle_switch_rejected_during_save",not get_root().get_node("BeachScenes").request_switch("test1_capture"))
		preview.async_controller.hold_completions=false
		check("lifecycle_save_finishes",await wait_task("overlap") and tasks.overlap.error.is_empty())
		var stored:=Snapshot.load(base+"_overlap.sandgp",preview.source_signature)
		check("lifecycle_save_drains_all",stored.error.is_empty() and preview.command_queue.pending.is_empty() and preview.async_controller.idle())
		var target: int=preview.completed_ticks+2
		var future:=command(2100);future.sim_tick=target
		check("lifecycle_future_admitted",preview.input_scheduler.submit(future).is_empty())
		check("lifecycle_future_save",(await preview.save_gpu_checkpoint(base+"_future.sandgp")).is_empty())
		check("lifecycle_future_exact_due_tick",preview.completed_ticks==target and not preview.playing and preview.command_queue.pending.is_empty())
		var legacy_future:=command(2101,Vector3(-8,0,0));legacy_future.sim_tick=target+1;legacy_future.sand_destination="suspended_v1"
		check("lifecycle_legacy_future_admitted",preview.input_scheduler.submit(legacy_future).is_empty())
		check("lifecycle_legacy_future_save",(await preview.save_gpu_checkpoint(base+"_legacy_future.sandgp")).is_empty())
		check("lifecycle_legacy_future_drained",preview.completed_ticks==target+1 and preview.command_queue.pending.is_empty() and not preview.async_controller.legacy)
		start_ui_stroke()
		call_deferred("_save_task","ui_buffer",base+"_ui_buffer.sandgp")
		check("lifecycle_ui_buffer_save",await wait_task("ui_buffer") and tasks.ui_buffer.error.is_empty())
		check("lifecycle_ui_buffer_closed",not preview.ui_pump_running and preview.stroke_controller.buffer_points()==0 and preview.stroke_controller.outstanding==0 and preview.shape_stroke_id==0 and not preview.async_controller.legacy)
		start_ui_stroke()
		end=Time.get_ticks_msec()+30000
		while preview.stroke_controller.outstanding==0 and preview.ui_pump_running and Time.get_ticks_msec()<end:await process_frame
		check("lifecycle_ui_segment_in_flight",preview.stroke_controller.outstanding>0 and preview.shape_stroke_id!=0)
		call_deferred("_save_task","ui_active",base+"_ui_active.sandgp")
		check("lifecycle_ui_active_save",await wait_task("ui_active") and tasks.ui_active.error.is_empty())
		check("lifecycle_ui_active_settles",not preview.ui_pump_running and preview.shape_stroke_id==0 and preview.solver.mold_field_ever_used and preview.last_error.is_empty())
		preview.playing=true
		var old_count: int=preview.gravel_field.active_count
		call_deferred("_drop_task","drop")
		end=Time.get_ticks_msec()+30000
		while not preview.async_controller.legacy and not tasks.has("drop") and Time.get_ticks_msec()<end:await process_frame
		call_deferred("_save_task","drop_save",base+"_drop.sandgp")
		check("lifecycle_drop_finishes",await wait_task("drop") and tasks.drop.get("ok",false))
		check("lifecycle_drop_save_finishes",await wait_task("drop_save") and tasks.drop_save.error.is_empty())
		check("lifecycle_drop_restores_playing",preview.playing and preview.input_scheduler.accepting and preview.gravel_field.active_count==old_count+2)
		preview.playing=false;check("lifecycle_after_drop_idle",await idle())
		var snapshot:=await capture("lifecycle_restore_source")
		preview.async_controller.hold_completions=true;enqueue(6)
		check("lifecycle_restore_has_inflight",await wait_slots(3))
		call_deferred("_restore_task","restore",snapshot)
		await frames(3)
		check("lifecycle_restore_waits_owned_work",preview.beach_restore_running and not tasks.has("restore") and preview.solver.rd!=null)
		preview.async_controller.hold_completions=false
		check("lifecycle_restore_finishes",await wait_task("restore") and tasks.restore.error.is_empty())
		var restored:=await capture("lifecycle_restore_after")
		same_native("lifecycle_restore_exact",snapshot,restored,true)
		var service=get_root().get_node("BeachScenes")
		service.session_directory=base+"_sessions";DirAccess.make_dir_recursive_absolute(service.session_directory)
		preview.async_controller.hold_completions=true;enqueue(6)
		check("lifecycle_switch_has_inflight",await wait_slots(3))
		var old_solver=preview.solver;var old_controller=preview.async_controller;var old_id: int=preview.get_instance_id()
		check("lifecycle_switch_capture_request",service.request_switch("test1_capture"))
		await frames(3)
		check("lifecycle_switch_waits_save",service.busy and preview.async_checkpoint_running and is_instance_id_valid(old_id))
		preview.async_controller.hold_completions=false
		end=Time.get_ticks_msec()+120000
		while service.busy and Time.get_ticks_msec()<end:await process_frame
		check("lifecycle_switch_capture_done",not service.busy and service.last_error.is_empty())
		preview=service.active_scene
		check("lifecycle_switch_inherits_mode",preview.async_pipeline_enabled and preview.async_backend_ready and preview.scene_key=="test1_capture")
		check("lifecycle_switch_old_released",old_solver.rd==null and not is_instance_id_valid(old_id))
		check("lifecycle_switch_cpu_owner_released",old_controller.slots.can_release() and not old_controller.ready)
		var main_saved:=Snapshot.load(service.saved.main.path)
		check("lifecycle_main_session_valid",main_saved.error.is_empty())
		check("lifecycle_switch_backwash",await switch_scene(service,"test1_backwash"))
		check("lifecycle_switch_return_main",await switch_scene(service,"main"))
		var returned:=await capture("lifecycle_session_restored")
		same_native("lifecycle_session_exact",main_saved.checkpoint,returned,true)
		service.inject_target_failure_once=true
		check("lifecycle_rollback_switch",await switch_scene(service,"test1_capture",true))
		check("lifecycle_rollback_main",preview.scene_key=="main" and preview.ready_for_ticks)
		var rollback_saved:=Snapshot.load(service.saved.main.path)
		var rollback:=await capture("lifecycle_rollback_capture")
		same_native("lifecycle_rollback_exact",rollback_saved.checkpoint,rollback,true)
		lifecycle_events=service.release_records.duplicate(true)
		check("lifecycle_released_nodes",lifecycle_events.all(func(row):return row.gpu_released and row.node_freed))
		preview.async_controller.hold_completions=true;enqueue(8)
		check("lifecycle_shutdown_has_inflight",await wait_slots(3))
		call_deferred("_save_task","last_save",base+"_shutdown_save.sandgp")
		await frames(2)
		call_deferred("_shutdown_task","shutdown_one");call_deferred("_shutdown_task","shutdown_two")
		await frames(3)
		check("lifecycle_shutdown_waits_capture",preview.shutdown_requested and preview.async_checkpoint_running and not preview.gpu_release_done and preview.solver.rd!=null)
		preview.async_controller.hold_completions=false
		check("lifecycle_last_save_completed",await wait_task("last_save") and tasks.last_save.error.is_empty())
		check("lifecycle_concurrent_shutdown_completed",await wait_task("shutdown_one") and await wait_task("shutdown_two") and shutdown_calls==2 and preview.gpu_release_done)
		check("lifecycle_shutdown_all_resources",preview.solver.rd==null and preview.async_controller.water.rd==null and preview.async_controller.collision.rd==null and preview.gravel_field==null and preview.preview_query==null)
		check("lifecycle_shutdown_cpu_owner_released",preview.async_controller.slots.can_release() and not preview.async_controller.ready)
	check("lifecycle_runtime_healthy",preview.last_error.is_empty())
	evidence={"configuration":preview.source_signature,"loaded_scripts":loaded_code(),"tasks":tasks,"scene_releases":lifecycle_events,"shutdown_calls":shutdown_calls}
	if not preview.gpu_release_done:await preview.shutdown()
	preview.queue_free();await process_frame
	# A direct close during an admitted shape segment has no save boundary to
	# close it on our behalf. Its receipt, UI pump, baseline and bridge must drain.
	preview=load(scene_path).instantiate();preview.async_pipeline_enabled=true;preview.playing=false;root.add_child(preview)
	end=Time.get_ticks_msec()+60000
	while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_msec()<end:await process_frame
	check("lifecycle_shape_exit_ready",preview.ready_for_ticks and preview.last_error.is_empty())
	start_ui_stroke()
	end=Time.get_ticks_msec()+30000
	while preview.stroke_controller.outstanding==0 and preview.ui_pump_running and Time.get_ticks_msec()<end:await process_frame
	check("lifecycle_shape_exit_has_admitted_work",preview.stroke_controller.outstanding>0 and preview.shape_stroke_id!=0)
	call_deferred("_shutdown_task","shape_shutdown")
	check("lifecycle_shape_exit_completes",await wait_task("shape_shutdown") and preview.gpu_release_done)
	check("lifecycle_shape_exit_owner_closed",not preview.ui_pump_running and preview.shape_stroke_id==0 and preview.async_controller.slots.can_release() and preview.solver.rd==null and preview.last_error.is_empty())
	evidence.shape_exit={"generation":preview.generation,"cpu_pool_released":preview.async_controller.slots.can_release(),"shape_stroke_id":preview.shape_stroke_id,"events":preview.async_controller.events.duplicate(true)}
	preview.queue_free();await process_frame
	var text:=FileAccess.get_file_as_string(output.get_basename()+".log")
	check("lifecycle_no_engine_errors",not text.is_empty() and not text.contains("SCRIPT ERROR:") and not text.contains("\nERROR:"))
	var file:=FileAccess.open(output,FileAccess.WRITE);file.store_string(JSON.stringify({"pass":not failed,"checks":checks,"evidence":evidence},"\t"));file.close()
	quit(1 if failed else 0)

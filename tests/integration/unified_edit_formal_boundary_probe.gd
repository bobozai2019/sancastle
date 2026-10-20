extends "res://tests/integration/unified_edit_playable_probe.gd"

const Routes=preload("res://scripts/beach/unified_scene_routes.gd")
var mode:=""
var save_done:=false
var save_error: StringName=&""
var close_done:=false
var forced_cleanup:=false
var save_completions:=0

func _run() -> void:
	mode=scene_key.get_slice("_",0);scene_key=scene_key.trim_prefix(mode+"_")
	orphan_baseline=int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	DisplayServer.window_set_size(Vector2i(1280,720))
	scene=load(Routes.FORMAL[scene_key]).instantiate();scene.playing=false;scene.generation=1001;root.add_child(scene)
	var start:=Time.get_ticks_msec()
	# The scene may accept sand edits before its props boot transition ends;
	# checkpoint admission requires that transition to finish as well.
	while (not scene.ready_for_ticks or scene._booting) and scene.last_error.is_empty() and Time.get_ticks_msec()-start<180000:await process_frame
	observations.startup={"phase":String(scene.runtime.phase),"root_error":String(scene.last_error),"elapsed_ms":Time.get_ticks_msec()-start,"current":scene.runtime.current!=null,"booting":scene._booting}
	if scene.runtime.candidate!=null:
		var staged=scene.runtime.candidate
		observations.startup.candidate={"initialized":staged.initialized,"started":staged.initialization_started,"error":String(staged.initialization_error),"height_readers":staged.heights.active_count(),"height_hint":staged.heights.hinted,"applied_chunks":staged.heights.applied_state_seq.size()}
	check("formal_boundary_ready",scene.ready_for_ticks and not scene._booting and scene.last_error.is_empty())
	if not scene.ready_for_ticks or scene._booting:await _close();return
	observations.sources=scene.configuration.sources.duplicate(true)
	check("actual_formal_root",scene.scene_file_path==Routes.FORMAL[scene_key] and scene.playable_scene_family()=="formal")
	if mode=="capture":await _capture_unknown()
	elif mode=="height":await _height_unknown()
	elif mode=="physics":await _physics_pending()
	elif mode=="recorded":await _recorded_save()
	else:check("supported_boundary",false)
	observations.forced_cleanup=forced_cleanup
	await _close()

func _start_save(path: String) -> void:
	save_error=await scene.save_gpu_checkpoint(path);save_done=true;save_completions+=1
func _start_close() -> void:
	await scene.shutdown();close_done=true
func _fill() -> void:
	check("boundary_fill",scene.input.begin(&"place_sand",Vector2(3,0),{},0.1,3,0.25).accepted);scene.input.finish()
func _wait_save() -> void:
	var start:=Time.get_ticks_msec()
	while not save_done and Time.get_ticks_msec()-start<30000:await process_frame
func _wait_close() -> void:
	var start:=Time.get_ticks_msec()
	while not close_done and Time.get_ticks_msec()-start<10000:await process_frame

func _capture_unknown() -> void:
	var owner=scene.runtime.current
	owner.transport.inject_idle_fence_unavailable=true
	var path:=output+"/unknown_current.sandue"
	_start_save(path)
	var capture=owner.checkpoint_capture
	check("root_save_has_unscheduled_real_capture",capture!=null and not capture.started and scene._saving)
	if capture==null:return
	capture.inject_registration_failure_once=true
	var start:=Time.get_ticks_msec()
	while not capture.unknown and Time.get_ticks_msec()-start<15000:await process_frame
	check("capture_has_real_unknown_terminal_proof",capture.unknown and capture.registered>0 and capture.pending==0 and not capture.finished and not save_done)
	observations.capture_before={"phase":String(capture.phase),"registered":capture.registered,"pending":capture.pending,"finished":capture.finished}
	owner.transport.inject_idle_fence_unavailable=false
	start=Time.get_ticks_msec()
	while not save_done and Time.get_ticks_msec()-start<4000:await process_frame
	check("current_capture_automatically_retries_real_proof",save_done and capture.finished and not owner.released and save_error==&"checkpoint_readback_registration" and not FileAccess.file_exists(path))
	if not save_done:forced_cleanup=true;owner.retry_checkpoint_lifetime();await _wait_save()
	await process_frame;await process_frame
	check("failed_save_leaves_live_domain_ready",scene.ready_for_ticks and scene.runtime.current==owner and scene.last_error.is_empty())
	observations.live_capture={"finished":capture.finished,"error":String(save_error),"owner_released":owner.released}
	save_done=false;save_error=&"";owner.transport.inject_idle_fence_unavailable=true
	path=output+"/unknown_close.sandue";_start_save(path);capture=owner.checkpoint_capture
	check("second_root_capture_before_recording",capture!=null and not capture.started)
	capture.inject_registration_failure_once=true
	start=Time.get_ticks_msec()
	while not capture.unknown and Time.get_ticks_msec()-start<15000:await process_frame
	check("second_capture_unknown_before_close",capture.unknown and not capture.finished and not save_done)
	_start_close()
	for frame in 3:await process_frame
	check("unknown_capture_retains_retired_owner",not close_done and not owner.released and scene.runtime.retired.size()==1 and not FileAccess.file_exists(path))
	owner.transport.inject_idle_fence_unavailable=false
	await _wait_close()
	check("root_automatically_retries_real_checkpoint_proof",close_done and owner.released and capture.finished)
	if not close_done:
		forced_cleanup=true;owner.retry_checkpoint_lifetime();await _wait_close()
	await _wait_save()
	check("failed_capture_never_written",save_done and save_error==&"checkpoint_readback_registration" and not FileAccess.file_exists(path))
	check("two_capture_callbacks_exactly_once",save_completions==2)
	observations.capture_after={"phase":String(capture.phase),"finished":capture.finished,"error":String(save_error),"released":owner.released}
	observations.events=scene.runtime.events.duplicate(true)

func _height_unknown() -> void:
	var owner=scene.runtime.current
	owner.heights.inject_readback_failure_once=true
	await _fill();await _idle()
	var start:=Time.get_ticks_msec();var seen:=false
	while not seen and Time.get_ticks_msec()-start<10000:
		for row in owner.heights.events:seen=seen or row.event==&"readback_unknown"
		await process_frame
	check("height_real_registration_unknown_observed",seen)
	start=Time.get_ticks_msec()
	while (owner.heights.active_count()!=0 or owner.heights.hinted) and Time.get_ticks_msec()-start<4000:await process_frame
	check("current_height_reader_automatically_retried",owner.heights.active_count()==0 and not owner.heights.hinted and _applied(owner)>=owner.completed_state_seq)
	if owner.heights.active_count()!=0:
		forced_cleanup=true;owner.heights.retry_readbacks()
		start=Time.get_ticks_msec()
		while owner.heights.active_count()!=0 and Time.get_ticks_msec()-start<10000:await process_frame
	observations.height_events=owner.heights.events.duplicate(true);observations.state_seq=owner.completed_state_seq;observations.applied=_applied(owner)

func _applied(owner) -> int:
	var latest:=0
	for value in owner.heights.applied_state_seq.values():latest=maxi(latest,int(value))
	return latest

func _physics_pending() -> void:
	var owner=scene.runtime.current
	owner.heights.hold_physics=true
	await _fill();await _idle()
	var start:=Time.get_ticks_msec()
	while owner.heights.active_count()==0 and Time.get_ticks_msec()-start<10000:await process_frame
	check("authority_complete_physics_not_applied",owner.completed_state_seq>0 and owner.heights.active_count()>0 and _applied(owner)<owner.completed_state_seq)
	var path:=output+"/physics_pending.sandue"
	var pending_save_error: StringName=await scene.save_gpu_checkpoint(path)
	observations.pending_save_error=String(pending_save_error)
	check("save_does_not_wait_for_collision_application",pending_save_error.is_empty())
	var saved:=Codec.load(path,scene.configuration)
	check("save_uses_completed_authority_not_old_collision",saved.error.is_empty() and saved.checkpoint.state_seq==owner.completed_state_seq and _applied(owner)<owner.completed_state_seq)
	observations.snapshot={"path":path,"sha256":FileAccess.get_sha256(path),"state_seq":owner.completed_state_seq,"applied_before":_applied(owner)}
	_start_close();for frame in 3:await process_frame
	check("close_retains_unconsumed_height_owner",not close_done and not owner.released and owner.heights.active_count()>0)
	owner.heights.hold_physics=false;await _wait_close()
	check("physics_reader_ack_then_release",close_done and owner.released and owner.heights.active_count()==0)
	observations.height_events=owner.heights.events.duplicate(true);observations.events=scene.runtime.events.duplicate(true)

func _recorded_save() -> void:
	var owner=scene.runtime.current;owner.hold_completions=true
	scene.panel.get_node("Margin/Controls/Tools/Wall").pressed.emit()
	check("open_recorded_stroke",scene.input.begin(&"wall_v1",Vector2(3,0),scene.panel.parameters(),0.1,3,0.25).accepted)
	var start:=Time.get_ticks_msec();var gpu_done:=false
	while not gpu_done and Time.get_ticks_msec()-start<10000:
		for record in owner._records.values():gpu_done=gpu_done or owner.slots.slot_snapshot(record.identity.slot_id).state==owner.Slots.State.GPU_COMPLETE
		await process_frame
	check("real_gpu_done_before_cpu_consumption",gpu_done and owner.completed_state_seq==0 and scene.input.terminal.is_empty())
	var path:=output+"/recorded.sandue"
	_start_save(path);for frame in 3:await process_frame
	check("save_waits_for_retained_gpu_completion",not save_done and owner.checkpoint_capture!=null and not owner.checkpoint_capture.started and not FileAccess.file_exists(path))
	owner.hold_completions=false;await _wait_save();await _idle()
	var saved:=Codec.load(path,scene.configuration)
	check("recorded_save_after_real_completion",save_done and save_error.is_empty() and saved.error.is_empty() and saved.checkpoint.highwater_id==3 and saved.checkpoint.state_seq==owner.completed_state_seq and owner.accounting.stroke.is_empty())
	observations.snapshot={"path":path,"sha256":FileAccess.get_sha256(path),"state_seq":owner.completed_state_seq,"highwater_id":owner.command_highwater()};observations.results=scene.input.terminal.duplicate(true)

func finish() -> void:
	FileAccess.open(output+"/probe.json",FileAccess.WRITE).store_string(JSON.stringify({"pass":not failed,"checks":checks,"observations":observations,"scope":"Formal actual queued/recorded/readback/physics ownership boundaries; forced cleanup is failure evidence, never an automatic-path PASS"},"\t"))
	quit(1 if failed else 0)

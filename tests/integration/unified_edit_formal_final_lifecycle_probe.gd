extends "res://tests/integration/unified_edit_playable_probe.gd"

const Routes=preload("res://scripts/beach/unified_scene_routes.gd")
var mode:=""
var close_done:=false
var restore_done:=false
var restore_error: StringName=&""

func _run() -> void:
	mode=scene_key.get_slice("_",0);scene_key=scene_key.trim_prefix(mode+"_")
	orphan_baseline=int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	DisplayServer.window_set_size(Vector2i(1280,720))
	scene=load(Routes.FORMAL[scene_key]).instantiate();scene.playing=false;scene.generation=1001;root.add_child(scene)
	observations.sources=scene.configuration.sources.duplicate(true)
	if mode=="boot":
		var staged=scene.runtime.candidate
		check("close_before_first_commit",scene.runtime.current==null and staged!=null)
		_start_close();await _wait_close()
		check("boot_candidate_released_without_publication",close_done and staged.released and _owned(staged)==0 and scene.runtime.current==null)
		observations.released={"generation":staged._generation,"owned":_owned(staged),"released":staged.released}
	else:
		var start:=Time.get_ticks_msec()
		while not scene.ready_for_ticks and scene.last_error.is_empty() and Time.get_ticks_msec()-start<180000:await process_frame
		check("formal_special_ready",scene.ready_for_ticks and scene.last_error.is_empty())
		if not scene.ready_for_ticks:await _close();return
		var path:=output+"/baseline.sandue"
		check("special_baseline_saved",(await scene.save_gpu_checkpoint(path)).is_empty());await process_frame
		if mode=="restoreclose":await _restore_close(path)
		elif mode in ["faultrestore","faultclose"]:await _fault(path)
		elif mode=="detach":await _detach(path)
		else:check("known_special_mode",false)
	observations.events=scene.runtime.events.duplicate(true)
	await _close()

func _start_close() -> void:
	await scene.shutdown();close_done=true
func _wait_close() -> void:
	var start:=Time.get_ticks_msec()
	while not close_done and Time.get_ticks_msec()-start<30000:await process_frame
func _start_restore(path: String) -> void:
	restore_error=await scene.restore_gpu_checkpoint(path);restore_done=true
func _owned(owner) -> int:
	var total:=0
	for member in [owner.transport,owner.state,owner.executor,owner.executor.response,owner.water,owner.coupled,owner.heights,owner.views]:total+=member.owned.size()
	return total

func _restore_close(path: String) -> void:
	var old=scene.runtime.current
	_start_restore(path)
	var staged=scene.runtime.candidate
	check("restore_candidate_created",staged!=null and not restore_done)
	staged.restore_verifier.hold_delivery=true
	var start:=Time.get_ticks_msec()
	while staged.restore_verifier.held.is_empty() and Time.get_ticks_msec()-start<15000:await process_frame
	check("actual_candidate_verifier_readers_held",not staged.restore_verifier.held.is_empty() and staged.restore_verifier.pending>0)
	_start_close();for frame in 3:await process_frame
	check("close_preserves_held_verifier_owner",not close_done and not staged.released and staged.restore_verifier.pending>0)
	RenderingServer.call_on_render_thread(staged.restore_verifier.release_held_render)
	await _wait_close()
	check("verifier_returns_then_both_owners_release",close_done and restore_done and not restore_error.is_empty() and staged.released and old.released and _owned(staged)==0 and _owned(old)==0)
	observations.released={"candidate_owned":_owned(staged),"old_owned":_owned(old),"candidate_released":staged.released,"old_released":old.released,"restore_error":String(restore_error)}

func _fault(path: String) -> void:
	var old=scene.runtime.current
	old.transport.inject_readback_failure_once=true;old.transport.inject_terminal_unavailable=true
	check("recorded_unknown_edit_admitted",scene.input.begin(&"place_sand",Vector2(3,0),{},0.1,3,0.25).accepted);scene.input.finish()
	var start:=Time.get_ticks_msec()
	while scene.last_error.is_empty() and Time.get_ticks_msec()-start<15000:await process_frame
	check("recording_fault_stops_frontend",not scene.last_error.is_empty() and not scene.ready_for_ticks and old.active_count()>0 and old.transport.has_owned())
	if mode=="faultrestore":_start_restore(path)
	else:_start_close()
	for frame in 4:await process_frame
	check("unconfirmed_record_not_freed_or_fabricated",not old.released and old.transport.has_owned() and old.completed_state_seq==0 and scene.input.terminal.is_empty())
	old.transport.inject_terminal_unavailable=false
	if mode=="faultrestore":
		start=Time.get_ticks_msec()
		while (not restore_done or not scene.runtime.retired.is_empty()) and Time.get_ticks_msec()-start<60000:await process_frame
		await process_frame;await process_frame
		check("faulted_record_owner_recovered_by_native_candidate",restore_done and restore_error.is_empty() and scene.generation==1002 and scene.runtime.current.completed_state_seq==0 and scene.last_error.is_empty() and scene.ready_for_ticks)
	else:await _wait_close()
	check("record_owner_released_after_terminal_proof",old.released and _owned(old)==0)
	var rows: Array=[]
	for row in scene.input.terminal:
		if row.get("generation")==1001 and row.get("command_id")==1:rows.append(row)
	check("unknown_result_once_without_applied_outcome",rows.size()==1 and rows[0].get("unknown",false) and rows[0].get("submitted",false) and not rows[0].has("outcome"))
	check("old_result_cannot_be_taken_again",scene.runtime.take_result(1001,1).is_empty())
	observations.unknown_results=rows.duplicate(true);observations.released={"generation":1001,"owned":_owned(old),"released":old.released,"completed_state_seq":old.completed_state_seq}
	if mode=="faultrestore":
		check("new_epoch_reuses_command_number_safely",scene.input.begin(&"place_sand",Vector2(3,0),{},0.1,3,0.25).accepted);scene.input.finish();await _idle()
		var fresh:=0
		for row in scene.input.terminal:
			if row.get("generation")==1002 and row.get("command_id")==1 and row.get("outcome")==L.Outcome.APPLIED:fresh+=1
		check("new_epoch_result_is_distinct",fresh==1 and scene.runtime.current.completed_state_seq>0)
		observations.new_results=scene.input.terminal.duplicate(true)

func _detach(path: String) -> void:
	var old=scene.runtime.current
	# Pause only the root's periodic maintenance so the injected unknown detach
	# can be inspected deterministically; Runtime and physics children continue.
	scene.set_process(false);old.views.inject_detach_failure_once=true
	_start_restore(path)
	var start:=Time.get_ticks_msec()
	while not restore_done and Time.get_ticks_msec()-start<60000:await process_frame
	for frame in 3:await process_frame
	check("new_epoch_commits_before_old_detach_proof",restore_done and restore_error.is_empty() and scene.generation==1002 and scene.runtime.retired.size()==1 and not old.released and not old.views.detached_confirmed)
	_start_close();await _wait_close()
	check("close_maintenance_retries_old_detach",close_done and old.released and _owned(old)==0 and scene.runtime.closed)
	observations.released={"owned":_owned(old),"released":old.released,"detached_confirmed":old.views.detached_confirmed}

func finish() -> void:
	FileAccess.open(output+"/probe.json",FileAccess.WRITE).store_string(JSON.stringify({"pass":not failed,"checks":checks,"observations":observations,"scope":"Formal early/candidate shutdown, actual unknown recording proof, cross-generation results and unknown detach; no fallback or fabricated outcome"},"\t"))
	quit(1 if failed else 0)

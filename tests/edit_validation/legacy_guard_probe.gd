extends "res://tests/edit_validation/undo_probe.gd"

var close_done := false
var close_pending := 0
var close_us := -1

func _write(ok: bool, error := "") -> void:
	var f:=FileAccess.open(output.path_join("legacy_guard_probe.json"),FileAccess.WRITE)
	f.store_string(JSON.stringify({"pass":ok,"rows":rows,"error":error,"scope":"legacy single-cell seam, future preflight and real shadow readback close"},"\t"))

func _close_shadow() -> void:
	if close_us>=0: return
	close_us=Time.get_ticks_usec();close_pending=lab.pending_state_readbacks
	await lab.shutdown();close_done=true

func _run() -> void:
	lab=load("res://tests/edit_validation/edit_checkpoint_lab.tscn").instantiate()
	root.add_child(lab)
	while not lab.ready_for_ticks and lab.last_error.is_empty(): await process_frame
	lab.water_policy=0
	var c:=_command(1,0.001);c.radius_m=0.02;c.transform.position_m=Vector3(-11.9375,0,0.0625)
	var gpu: Dictionary=await lab.apply_gpu_command(c)
	var before: Dictionary=await _snapshot("before_seam")
	c=_command(2,0.01);c.kind=&"smooth";c.radius_m=0.07;c.strength=1.0;c.transform.position_m=Vector3(-11.875,0,0.0625);c.erase("amount_m3")
	var result: Dictionary=await lab.apply_legacy_command(c)
	var after: Dictionary=await _snapshot("after_seam")
	rows.append({"case":"single_chunk_smooth_refreshes_adjacent_ghost_samples","pass":gpu.get("status")==1 and result.results[0].status==&"applied" and result.results[0].dirty_chunks.size()==1 and before.sand!=after.sand and _collision_exact(after) and before.water==after.water and before.momentum_x==after.momentum_x and before.momentum_z==after.momentum_z,"legacy":result,"collision_exact":_collision_exact(after)})
	var future:=c.duplicate(true);future.command_id=3;future.sim_tick=1
	var highwater: int=lab.command_queue.last_command_id
	var future_result: Dictionary=await lab.apply_legacy_command(future)
	rows.append({"case":"future_legacy_not_orphaned","pass":future_result.get("error")=="invalid_command" and lab.command_queue.pending.is_empty() and lab.command_queue.last_command_id==highwater,"result":future_result})
	lab.observe_readback_ownership=true;lab.state_readback_submitted.connect(_close_shadow)
	c.command_id=3;c.kind=&"compact"
	var close_result: Dictionary=await lab.apply_legacy_command(c)
	while not close_done: await process_frame
	rows.append({"case":"close_actual_legacy_shadow_readback","pass":close_result.get("error")=="closed" and close_pending>0 and lab.pending_state_readbacks==0 and lab.state_readback_callback_us>=close_us and lab.release_record_us>=lab.state_readback_callback_us and lab.solver==null and lab.last_error.is_empty(),"pending_at_close":close_pending,"close_us":close_us,"callback_us":lab.state_readback_callback_us,"release_us":lab.release_record_us})
	var ok:=true
	for row in rows: ok=ok and row.pass
	_write(ok);lab.queue_free();finished=true;print("LEGACY_GUARD_COMPLETE pass=%s" % str(ok));quit(0 if ok else 1)

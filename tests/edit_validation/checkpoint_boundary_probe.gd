extends "res://tests/edit_validation/water_transaction_probe.gd"

const Codec=preload("res://scripts/simulation/edit_validation/gpu_checkpoint_codec.gd")
var capture_checks := []
var close_on_capture := false
var close_done := false
var close_us := -1
var pending_at_close := 0

func _write(ok: bool, error := "") -> void:
	var f:=FileAccess.open(output.path_join("checkpoint_boundary_probe.json"),FileAccess.WRITE)
	f.store_string(JSON.stringify({"pass":ok,"rows":rows,"error":error,"scope":"live save admission barrier and actual full-field/CFL readback ownership; live restore pending"},"\t"))

func _setup() -> void:
	lab=load("res://tests/edit_validation/edit_checkpoint_lab.tscn").instantiate()
	root.add_child(lab)
	while not lab.ready_for_ticks and lab.last_error.is_empty(): await process_frame
	lab.observe_readback_ownership=true
	lab.state_readback_submitted.connect(_at_capture)

func _at_capture() -> void:
	if close_on_capture:
		await _close_owner("state");return
	if not lab.checkpoint_running: return
	var command:=_command(lab.command_queue.last_command_id+1,0.001)
	var stock: float=lab.domain.tool_inventory_m3
	var denied: Dictionary=await lab.apply_gpu_command(command)
	var scheduler_denied: StringName=lab.input_scheduler.submit(command)
	var ok: bool=lab.pending_state_readbacks>0 and denied.get("error")=="checkpoint_busy" and scheduler_denied==&"backend_unavailable" and lab.domain.tool_inventory_m3==stock and lab.command_queue.pending.is_empty()
	capture_checks.append({"pass":ok,"pending_readbacks":lab.pending_state_readbacks,"direct_error":denied,"scheduler_error":String(scheduler_denied)})

func _close_owner(kind: String) -> void:
	if close_us>=0: return
	close_us=Time.get_ticks_usec()
	pending_at_close=lab.pending_state_readbacks if kind=="state" else lab.pending_cfl_readbacks
	await lab.shutdown()
	close_done=true

func _at_cfl() -> void: await _close_owner("cfl")

func _same_raw(sidecar: Dictionary, state: Dictionary) -> bool:
	for field in Codec.FIELD_BYTES:
		if sidecar.raw_fields[field]!=state[field]: return false
	return true

func _run() -> void:
	await _setup()
	lab.water_policy=1
	var start:=Vector3(0.0625,0,0.0625)
	var a: bool=lab._start_input(&"place_sand",start,start,&"circle",0.015)
	while not lab.solver.receipt_pending: await process_frame
	var active_at_save: bool=lab.busy and lab.solver.receipt_pending
	var b: bool=lab._start_input(&"place_sand",start,start,&"circle",0.01)
	var pending_at_save: int=lab.command_queue.pending.size()
	var path:=output.path_join("live_pending_checkpoint.scp")
	var error: StringName=await lab.save_checkpoint(path)
	var loaded:=Codec.load(path)
	var state: Dictionary=await _snapshot("after_live_save")
	var applied: bool=error==&"" and loaded.error==&"" and _same_raw(loaded.sidecar,state) and loaded.sidecar.prefix.size()==2 and lab.execution_prefix.size()==2 and lab.input_scheduler.reserved_total()==0.0 and lab.command_queue.pending.is_empty() and loaded.sidecar.ledger.tool_inventory_m3==lab.domain.tool_inventory_m3
	rows.append({"case":"save_waits_actual_inflight_and_due_pending","pass":a and b and active_at_save and pending_at_save==1 and applied,"active_at_save":active_at_save,"pending_at_save":pending_at_save,"error":String(error),"capture_checks":capture_checks.duplicate(true),"prefix":loaded.sidecar.prefix})
	var future:=_command(3,0.001);future.sim_tick=2
	var admitted: bool=lab.input_scheduler.submit(future)==&""
	var stock: float=lab.domain.tool_inventory_m3
	var reserved: float=lab.input_scheduler.reserved_total()
	var future_path:=output.path_join("future_pending_rejected.scp")
	var future_error: StringName=await lab.save_checkpoint(future_path)
	rows.append({"case":"future_pending_save_fails_without_omission","pass":admitted and future_error==&"pending_commands" and not FileAccess.file_exists(future_path) and lab.command_queue.pending.size()==1 and lab.input_scheduler.reserved_total()==reserved and lab.domain.tool_inventory_m3==stock and lab.input_scheduler.accepting,"error":String(future_error),"reserved":reserved})
	await lab.set_paused(false);await lab.input_scheduler.advance_ticks(2);await lab.set_paused(true)
	var settled_error: StringName=await lab.save_checkpoint(output.path_join("future_settled_checkpoint.scp"))
	var settled:=Codec.load(output.path_join("future_settled_checkpoint.scp"))
	rows.append({"case":"same_future_command_included_after_due_tick","pass":settled_error==&"" and settled.error==&"" and settled.sidecar.tick==2 and settled.sidecar.prefix.size()==3 and lab.input_scheduler.reserved_total()==0.0,"tick":lab.completed_ticks})
	var gates:=capture_checks.size()==2
	for item in capture_checks: gates=gates and item.pass
	rows.append({"case":"no_new_submission_during_actual_snapshot","pass":gates,"checks":capture_checks})
	await lab.shutdown();lab.queue_free()
	await _setup();close_on_capture=true
	var closed_path:=output.path_join("closed_snapshot_rejected.scp")
	var closed_error: StringName=await lab.save_checkpoint(closed_path)
	while not close_done: await process_frame
	var owner: bool=pending_at_close>0 and lab.pending_state_readbacks==0 and lab.state_readback_callback_us>=close_us and lab.release_record_us>=lab.state_readback_callback_us and lab.release_wait_count>0 and lab.solver==null
	rows.append({"case":"close_actual_full_field_snapshot_owner","pass":closed_error==&"closed" and not FileAccess.file_exists(closed_path) and owner,"pending_at_close":pending_at_close,"close_us":close_us,"last_callback_us":lab.state_readback_callback_us,"release_us":lab.release_record_us,"wait_count":lab.release_wait_count})
	lab.queue_free();close_on_capture=false;close_done=false;close_us=-1
	await _setup();lab.cfl_readback_submitted.connect(_at_cfl);await lab.set_paused(false)
	await lab.advance_ticks(1)
	while not close_done: await process_frame
	owner=pending_at_close>0 and lab.pending_cfl_readbacks==0 and lab.cfl_readback_callback_us>=close_us and lab.release_record_us>=lab.cfl_readback_callback_us and lab.release_wait_count>0 and lab.completed_ticks==0 and lab.solver==null
	rows.append({"case":"close_actual_CFL_owner_no_late_tick","pass":owner,"pending_at_close":pending_at_close,"close_us":close_us,"callback_us":lab.cfl_readback_callback_us,"release_us":lab.release_record_us,"wait_count":lab.release_wait_count,"completed_ticks":lab.completed_ticks})
	var ok:=true
	for row in rows: ok=ok and row.pass
	_write(ok);lab.queue_free();finished=true;print("CHECKPOINT_BOUNDARY_COMPLETE pass=%s rows=%d" % [str(ok),rows.size()]);quit(0 if ok else 1)

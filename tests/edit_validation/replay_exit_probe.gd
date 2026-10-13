extends "res://tests/edit_validation/undo_probe.gd"

var close_done := false
var close_started := false
var close_us := -1
var pending_at_close := 0
var source_solver
var worker_solver

func _write(ok: bool, error := "") -> void:
	var f:=FileAccess.open(output.path_join("replay_exit_probe.json"),FileAccess.WRITE)
	f.store_string(JSON.stringify({"pass":ok,"rows":rows,"error":error,"scope":"actual replay worker CFL in-flight, parent waits worker ownership and no target commit"},"\t"))

func _watch_worker(worker) -> void:
	worker.observe_readback_ownership=true
	worker.cfl_readback_submitted.connect(_close_at_cfl.bind(worker))

func _close_at_cfl(worker) -> void:
	if close_started: return
	close_started=true;close_us=Time.get_ticks_usec();pending_at_close=worker.pending_cfl_readbacks
	source_solver=lab.solver;worker_solver=worker.solver
	await lab.shutdown();close_done=true

func _close_fast_capture() -> void:
	if close_started: return
	close_started=true;close_us=Time.get_ticks_usec();pending_at_close=lab.pending_state_readbacks
	source_solver=lab.solver
	await lab.shutdown();close_done=true

func _fast_capture_case() -> void:
	close_done=false;close_started=false;close_us=-1
	lab=load("res://tests/edit_validation/edit_checkpoint_lab.tscn").instantiate();lab.local_dispatch=true
	root.add_child(lab)
	while not lab.ready_for_ticks and lab.last_error.is_empty(): await process_frame
	lab.water_policy=0
	await lab.apply_gpu_command(_command(1,0.015))
	var stock: float=lab.domain.tool_inventory_m3
	var prefix: Array=lab.execution_prefix.duplicate(true)
	lab.observe_readback_ownership=true;lab.state_readback_submitted.connect(_close_fast_capture)
	var result: Dictionary=await lab.undo_latest()
	while not close_done: await process_frame
	rows.append({"case":"close_fast_undo_target_capture","pass":result.get("error")=="closed" and pending_at_close>0 and source_solver.rd==null and lab.pending_state_readbacks==0 and lab.state_readback_callback_us>=close_us and lab.release_record_us>=lab.state_readback_callback_us and lab.domain.tool_inventory_m3==stock and lab.execution_prefix==prefix and lab.redo_commands.is_empty() and lab.last_error.is_empty(),"result":result,"pending_at_close":pending_at_close,"close_us":close_us,"callback_us":lab.state_readback_callback_us,"release_us":lab.release_record_us})
	lab.queue_free()

func _case(redo: bool) -> void:
	close_done=false;close_started=false;close_us=-1
	lab=load("res://tests/edit_validation/edit_checkpoint_lab.tscn").instantiate();lab.local_dispatch=true
	root.add_child(lab)
	while not lab.ready_for_ticks and lab.last_error.is_empty(): await process_frame
	lab.water_policy=0
	await lab.apply_gpu_command(_command(1,0.015))
	await lab.set_paused(false);await lab.advance_ticks(2);await lab.set_paused(true)
	await lab.apply_gpu_command(_command(2,0.01))
	await lab.set_paused(false);await lab.advance_ticks(1);await lab.set_paused(true)
	if redo: await lab.undo_latest()
	var stock: float=lab.domain.tool_inventory_m3
	var prefix: Array=lab.execution_prefix.duplicate(true)
	var prior_disposals: int=lab.replay_disposals.size()
	lab.observe_replay_boundaries=true;lab.replay_worker_created.connect(_watch_worker)
	var result: Dictionary=await lab.redo_latest() if redo else await lab.undo_latest()
	while not close_done: await process_frame
	var audit: Dictionary=lab.replay_disposals[-1]
	var owned: bool=pending_at_close>0 and source_solver.rd==null and worker_solver.rd==null and lab.solver==null and lab.replay_worker==null and audit.solver_released and audit.pending_state==0 and audit.pending_cfl==0 and audit.cfl_callback_us>=close_us and audit.release_us>=audit.cfl_callback_us and lab.release_record_us>=audit.release_us
	rows.append({"case":"close_redo_replay" if redo else "close_undo_replay","pass":result.get("error")=="closed" and owned and lab.domain.tool_inventory_m3==stock and lab.execution_prefix==prefix and lab.replay_disposals.size()==prior_disposals+1 and lab.last_error.is_empty(),"result":result,"pending_at_close":pending_at_close,"close_us":close_us,"worker_disposal":audit,"source_release_us":lab.release_record_us,"ledger_unchanged":lab.domain.tool_inventory_m3==stock})
	lab.queue_free()

func _run() -> void:
	await _case(false);await _case(true);await _fast_capture_case()
	var ok:=true
	for row in rows: ok=ok and row.pass
	_write(ok);finished=true;print("REPLAY_EXIT_COMPLETE pass=%s" % str(ok));quit(0 if ok else 1)

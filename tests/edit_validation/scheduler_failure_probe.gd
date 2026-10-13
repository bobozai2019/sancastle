extends "res://tests/edit_validation/scheduler_probe.gd"

func _write(ok: bool, error := "") -> void:
	var f:=FileAccess.open(output.path_join("scheduler_failure_probe.json"),FileAccess.WRITE)
	f.store_string(JSON.stringify({"pass":ok,"rows":rows,"error":error,"scope":"post-commit receipt transport failure, GPU rollback and pending cancellation; injection is explicit"},"\t"))

func _inject_receipt_fault() -> void:
	lab.solver.inject_receipt_failure_once=true

func _run() -> void:
	await _setup(256)
	lab.expect_transport_failure=true
	var before: Dictionary=await _snapshot("before")
	var stock: float=lab.domain.tool_inventory_m3
	var revision: int=lab.solver.state_revision
	var accepted:=true
	for k in 3:
		var c:=_command(k+1,0.005);c.sim_tick=k
		accepted=accepted and scheduler.submit(c,1,0.0)==&""
	RenderingServer.call_on_render_thread(_inject_receipt_fault)
	await scheduler.drain_due()
	var after: Dictionary=await _snapshot("after",true)
	var same:=true
	for key in before:
		if key!="water_receipt": same=same and before[key]==after[key]
	var terminal: bool=scheduler.terminal.size()==3 and scheduler.terminal[0].result.get("transport_failed",false)
	for item in scheduler.terminal: terminal=terminal and item.result.get("cancelled",false)
	var quarantined: bool=not lab.ready_for_ticks and scheduler.submit(_command(4,0.005))==&"backend_unavailable"
	var ok: bool=accepted and same and terminal and quarantined and lab.domain.tool_inventory_m3==stock and lab.solver.state_revision==revision and lab.command_queue.applied_log.is_empty() and scheduler.reserved_total()==0.0 and scheduler.reservations.is_empty() and lab.command_queue.pending.is_empty()
	rows.append({"pass":ok,"authority_and_published_unchanged":same,"terminal_once":terminal,"quarantined":quarantined,"stock":lab.domain.tool_inventory_m3,"reserved":scheduler.reserved_total(),"terminal":scheduler.terminal})
	_write(ok);await scheduler.close();lab.queue_free();finished=true
	print("SCHEDULER_FAILURE_COMPLETE pass=%s" % str(ok));quit(0 if ok else 1)


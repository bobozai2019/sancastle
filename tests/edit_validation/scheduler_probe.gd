extends "res://tests/edit_validation/water_transaction_probe.gd"

const Scheduler = preload("res://scripts/simulation/edit_validation/gpu_edit_scheduler.gd")
var scheduler
var scheduler_policy := 0

func _write(ok: bool, error := "") -> void:
	var file := FileAccess.open(output.path_join("scheduler_probe.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass":ok,"rows":rows,"error":error,"scope":"real GPU 64 pending and nominal reservations, ordered due execution; no performance"},"\t"))

func _setup(size: int) -> void:
	lab=load("res://tests/edit_validation/edit_gpu_water_"+("numeric" if size==64 else "brush")+"_lab.tscn").instantiate()
	lab.local_dispatch=true;root.add_child(lab)
	while not lab.ready_for_ticks and lab.last_error.is_empty(): await process_frame
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--scheduler-policy="): scheduler_policy=int(arg.trim_prefix("--scheduler-policy="))
	lab.water_policy=scheduler_policy
	scheduler=Scheduler.new(lab)

func _batch(size: int, burst: bool) -> Dictionary:
	await _setup(size)
	var accepted := true
	for k in 64:
		var command := _command(k+1,0.005)
		command.radius_m=0.3
		command.transform.position_m=Vector3((k%8-4)*0.1,0,(k/8-4)*0.1)
		if k%2==1:
			command.shape=&"swept_segment"
			command.transform.end_position_m=command.transform.position_m+Vector3(0.15,0,0.05)
		accepted=accepted and scheduler.submit(command)==&""
		if not burst: await scheduler.drain_due()
	var full_denied := true
	var before_reserved: float = scheduler.reserved_total()
	if burst:
		full_denied=scheduler.submit(_command(65,0.005))==&"backend_unavailable" and lab.command_queue.last_command_id==64 and absf(before_reserved-0.32)<1e-12 and lab.domain.tool_inventory_m3==2.0
	await scheduler.drain_due()
	var ordered: bool = scheduler.terminal.size()==64
	for k in scheduler.terminal.size():
		ordered=ordered and scheduler.terminal[k].command.command_id==k+1 and scheduler.terminal[k].result.get("status")==1
	var state: Dictionary = await _snapshot("%d_%s" % [size,"burst" if burst else "serial"])
	var ledger: float = lab.domain.tool_inventory_m3
	var zero_reserved: bool = scheduler.reserved_total()==0.0 and scheduler.reservations.is_empty() and scheduler.policies.is_empty() and not scheduler.pumping and lab.command_queue.pending.is_empty()
	var ok: bool = accepted and full_denied and ordered and zero_reserved and lab.last_error.is_empty() and lab.command_queue.applied_log.size()==64
	rows.append({"case":"burst64" if burst else "serial64","grid":size,"policy":scheduler_policy,"pass":ok,"admitted":accepted,"ordered_exactly_once":ordered,"full_queue_reject":full_denied,"reservation_before_drain":before_reserved,"reservations_zero":zero_reserved,"stock":ledger,"max_pending":scheduler.max_pending,"terminal":scheduler.terminal})
	await scheduler.close();lab.queue_free();await process_frame;lab=null;scheduler=null
	return {"state":state,"stock":ledger}

func _order() -> void:
	await _setup(64)
	var future := _command(1,0.01);future.sim_tick=2
	var present := _command(2,0.01)
	var accepted: bool = scheduler.submit(future)==&"" and scheduler.submit(present)==&""
	await scheduler.drain_due()
	var first: bool = scheduler.terminal.size()==1 and scheduler.terminal[0].command.command_id==2
	await scheduler.advance_ticks(2)
	var second: bool = scheduler.terminal.size()==2 and scheduler.terminal[1].command.command_id==1 and scheduler.terminal[1].result.get("status")==1 and scheduler.reserved_total()==0.0
	rows.append({"case":"future_id_then_current_id","pass":accepted and first and second,"terminal":scheduler.terminal,"completed_tick":lab.completed_ticks})
	await scheduler.close();lab.queue_free();await process_frame;lab=null;scheduler=null

func _run() -> void:
	for size in [64,256]:
		var serial_state: Dictionary = await _batch(size,false)
		var burst_state: Dictionary = await _batch(size,true)
		var equal: bool = serial_state.stock==burst_state.stock
		for key in serial_state.state:
			if key!="water_receipt" or scheduler_policy>0: equal=equal and serial_state.state[key]==burst_state.state[key]
		rows.append({"case":"serial_burst_bitwise","grid":size,"pass":equal})
	await _order()
	var ok := rows.size()==7
	for row in rows: ok=ok and row.pass
	_write(ok);finished=true;print("SCHEDULER_COMPLETE pass=%s rows=%d" % [str(ok),rows.size()]);quit(0 if ok else 1)

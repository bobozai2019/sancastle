extends "res://tests/edit_validation/scheduler_probe.gd"

func _write(ok: bool, error := "") -> void:
	var file:=FileAccess.open(output.path_join("scheduler_exit_probe.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass":ok,"rows":rows,"error":error,"scope":"actual GPU in-flight receipt then generation invalidation and owner-safe release; no performance"},"\t"))

func _run() -> void:
	lab=load("res://tests/edit_validation/edit_scheduler_exit_lab.tscn").instantiate();lab.local_dispatch=true
	root.add_child(lab)
	while not lab.ready_for_ticks and lab.last_error.is_empty(): await process_frame
	scheduler=Scheduler.new(lab)
	var backend=lab.solver
	var stock: float=lab.domain.tool_inventory_m3
	var generation: int=lab.generation
	var admitted := true
	for i in 64: admitted=admitted and scheduler.submit(_command(i+1,0.005),1,0.0)==&""
	scheduler.call_deferred("drain_due")
	await lab.dispatch_observed
	var pending_now: bool=backend.receipt_pending
	var outstanding65: bool=scheduler.submit(_command(65,0.005),1,0.0)==&"" and lab.command_queue.pending.size()==64
	var full: bool=scheduler.submit(_command(66,0.005))==&"backend_unavailable"
	await scheduler.advance_ticks(1)
	var tick_guard: bool=lab.completed_ticks==0 and scheduler.denied_tick_requests==1
	var close_us:=Time.get_ticks_usec()
	await scheduler.close()
	var receipt: Dictionary=Protocol.decode_receipt(lab.exit_gpu_receipt)
	_save("actual_gpu_receipt.bin",lab.exit_gpu_receipt)
	var cancelled: bool=scheduler.terminal.size()==65
	for item in scheduler.terminal: cancelled=cancelled and item.result.get("cancelled",false)
	var owners_returned: bool=lab.release_record_us>=backend.receipt_callback_us and backend.receipt_callback_us>close_us and backend.rd==null and lab.release_wait_count>0
	var ok: bool=admitted and lab.dispatch_state.pending and pending_now and outstanding65 and full and tick_guard and cancelled and owners_returned and lab.domain.tool_inventory_m3==stock and lab.command_queue.applied_log.is_empty() and scheduler.reserved_total()==0.0 and scheduler.reservations.is_empty() and lab.generation==generation+1 and lab.ignored_receipts==1 and receipt.get("status")==1 and scheduler.submit(_command(66,0.005))==&"backend_unavailable"
	rows.append({"pass":ok,"pending_at_close":pending_now,"active_plus64":outstanding65,"full_rejected":full,"tick_guard":tick_guard,"cancelled_once":cancelled,"owners_returned_before_release":owners_returned,"close_us":close_us,"callback_us":backend.receipt_callback_us,"release_record_us":lab.release_record_us,"release_wait_count":lab.release_wait_count,"stock_before":stock,"stock_after":lab.domain.tool_inventory_m3,"reserved_after":scheduler.reserved_total(),"ignored_receipts":lab.ignored_receipts,"gpu_receipt":receipt,"terminal":scheduler.terminal})
	_write(ok);lab.queue_free();finished=true
	print("SCHEDULER_EXIT_COMPLETE pass=%s" % str(ok));quit(0 if ok else 1)

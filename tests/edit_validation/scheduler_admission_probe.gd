extends "res://tests/edit_validation/scheduler_probe.gd"

func _write(ok: bool, error := "") -> void:
	var file:=FileAccess.open(output.path_join("scheduler_admission_probe.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass":ok,"rows":rows,"error":error,"scope":"live GPU inventory reservation, generation and duplicate actual receipt; no performance"},"\t"))

func _seed(stock: float) -> void:
	var sand:=PackedFloat32Array();sand.resize(4096);sand.fill(0.4)
	await lab.seed_test_fields({"sand":sand},stock)
	scheduler=Scheduler.new(lab)

func _run() -> void:
	await _setup(64)
	await _seed(0.02)
	var a:=_command(1,0.015);a.sim_tick=2
	var b:=_command(2,0.01)
	var accepted: bool=scheduler.submit(a)==&""
	var shortage: bool=scheduler.submit(b)==&"insufficient_inventory" and lab.command_queue.last_command_id==1 and lab.command_queue.pending.size()==1
	b.amount_m3=0.005
	var remainder: bool=scheduler.submit(b)==&""
	var eps:=_command(3,0.0000005);eps.sim_tick=2
	var borrowed: bool=scheduler.submit(eps)==&""
	var second:=_command(4,0.00000075)
	var repeat_denied: bool=scheduler.submit(second)==&"insufficient_inventory" and lab.command_queue.last_command_id==3
	rows.append({"case":"nominal_aggregate_EPS","pass":accepted and shortage and remainder and borrowed and repeat_denied,"reserved":scheduler.reserved_total(),"stock":lab.domain.tool_inventory_m3})
	var old_generation: int=lab.generation
	await scheduler.reset_domain()
	var stale:=_command(4,0.001);stale.generation=old_generation
	var stale_denied: bool=scheduler.submit(stale)==&"inactive_generation"
	rows.append({"case":"reset_cancels_reservations","pass":scheduler.reserved_total()==0.0 and lab.command_queue.pending.is_empty() and lab.generation==old_generation+1 and stale_denied,"terminal":scheduler.terminal})
	await _seed(0.0)
	var dig:=_command(1,0.01);dig.kind=&"remove_sand"
	var placed:=_command(2,0.0001)
	var dig_ok: bool=scheduler.submit(dig)==&""
	var no_credit: bool=scheduler.submit(placed)==&"insufficient_inventory" and lab.domain.tool_inventory_m3==0.0
	await scheduler.drain_due()
	var funded: bool=lab.domain.tool_inventory_m3>0.0 and scheduler.submit(placed)==&""
	await scheduler.drain_due()
	var saved: PackedByteArray=lab.raw_receipt.duplicate()
	var saved_generation: int=lab.generation
	var stock: float=lab.domain.tool_inventory_m3
	var ignored: int=lab.ignored_receipts
	lab._settle_receipt(saved,lab.generation)
	var duplicate: bool=lab.domain.tool_inventory_m3==stock and lab.ignored_receipts==ignored+1
	rows.append({"case":"dig_credit_after_receipt_and_duplicate","pass":dig_ok and no_credit and funded and duplicate and scheduler.terminal.size()==2,"stock":stock,"terminal":scheduler.terminal})
	await _seed(0.0)
	var new_state: Dictionary=await _snapshot("new_generation_before_old_receipt")
	var new_ignored: int=lab.ignored_receipts
	lab._settle_receipt(saved,saved_generation)
	var unchanged_state: Dictionary=await _snapshot("new_generation_after_old_receipt")
	var unchanged: bool=lab.domain.tool_inventory_m3==0.0 and lab.ignored_receipts==new_ignored+1
	for key in new_state:
		if key!="water_receipt": unchanged=unchanged and new_state[key]==unchanged_state[key]
	rows.append({"case":"old_actual_receipt_after_reset","pass":unchanged,"old_generation":saved_generation,"new_generation":lab.generation})
	var loan:=_command(1,0.0000005);loan.radius_m=0.03;loan.transform.position_m=Vector3(0.0625,0,0.0625)
	var one: bool=scheduler.submit(loan)==&""
	await scheduler.drain_due()
	var negative: bool=lab.domain.tool_inventory_m3<0.0
	var next:=_command(2,0.0000001)
	var denied: bool=scheduler.submit(next)==&"insufficient_inventory" and scheduler.reserved_total()==0.0
	rows.append({"case":"negative_balance_no_new_EPS","pass":one and negative and denied,"stock":lab.domain.tool_inventory_m3,"terminal":scheduler.terminal})
	await _seed(2.0)
	var deep:=PackedFloat32Array();deep.resize(4096);deep.fill(715.0)
	await lab.seed_test_fields({"water":deep},2.0)
	scheduler=Scheduler.new(lab)
	var reject_command:=_command(1,0.005)
	var follow_command:=_command(2,0.001);follow_command.sim_tick=1
	var both: bool=scheduler.submit(reject_command,2,1.0)==&"" and scheduler.submit(follow_command,0,0.0)==&""
	var rejection_before: Dictionary=await _snapshot("rejected_candidate_before")
	await scheduler.drain_due()
	var rejection_after: Dictionary=await _snapshot("rejected_candidate_after")
	var rejected_unchanged: bool=both and scheduler.terminal.size()==1 and scheduler.terminal[0].result.get("status")==2 and lab.domain.tool_inventory_m3==2.0 and absf(scheduler.reserved_total()-0.001)<1e-12
	for key in rejection_before:
		if key!="water_receipt": rejected_unchanged=rejected_unchanged and rejection_before[key]==rejection_after[key]
	await scheduler.advance_ticks(1)
	var continued: bool=scheduler.terminal.size()==2 and scheduler.terminal[1].result.get("status")==1 and lab.command_queue.applied_log.size()==1 and scheduler.reserved_total()==0.0 and lab.solver.max_substeps_used==64 and lab.solver.overload_events==0
	rows.append({"case":"rejected_candidate_releases_only_own_reserve","pass":rejected_unchanged and continued,"original_CFL64_advanced":continued,"terminal":scheduler.terminal})
	await _seed(2.0)
	var high: int=9007199254740993
	lab.ticket_id=high
	lab.solver.state_revision=4294967295
	var native:=_command(high,0.001)
	var native_admitted: bool=scheduler.submit(native)==&""
	await scheduler.drain_due()
	var native_receipt: Dictionary=Protocol.decode_receipt(lab.raw_receipt)
	_save("native_high_identity_receipt.bin",lab.raw_receipt)
	rows.append({"case":"int64_ids_and_revision_carry","pass":native_admitted and native_receipt.get("status")==1 and native_receipt.command_id==high and native_receipt.ticket_id==high+1 and native_receipt.input_revision==4294967295 and native_receipt.output_revision==4294967296,"receipt":native_receipt})
	var ok:=rows.size()==7
	for row in rows: ok=ok and row.pass
	_write(ok);await scheduler.close();lab.queue_free();finished=true
	print("SCHEDULER_ADMISSION_COMPLETE pass=%s rows=%d" % [str(ok),rows.size()]);quit(0 if ok else 1)

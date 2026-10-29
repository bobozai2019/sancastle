extends "res://tests/edit_validation/water_transaction_probe.gd"

func _write(ok: bool, error := "") -> void:
	var f:=FileAccess.open(output.path_join("interaction_reset_probe.json"),FileAccess.WRITE)
	f.store_string(JSON.stringify({"pass":ok,"rows":rows,"error":error,"scope":"live interaction reset waits GPU transaction and collision owners; fresh generation"},"\t"))

func _run() -> void:
	lab=load("res://tests/edit_validation/edit_interaction_lab.tscn").instantiate()
	root.add_child(lab)
	while not lab.ready_for_ticks and lab.last_error.is_empty(): await process_frame
	lab.water_policy=1
	var original: Dictionary=await _snapshot("initial")
	var old_generation: int=lab.generation
	var accepted: bool=lab._start_input(&"place_sand",Vector3(0.0625,0,0.0625),Vector3(0.0625,0,0.0625),&"circle",0.015)
	while not lab.busy: await process_frame
	var scheduler=lab.input_scheduler
	var future:=_command(2,0.01);future.sim_tick=2
	var queued: bool=scheduler.submit(future)==&""
	var pending_at_reset: bool=lab.busy
	await lab.reset_domain()
	var state: Dictionary=await _snapshot("after_reset")
	var exact:=true
	# The private receipt is scratch and has no initialized pre-command value.
	# Compare the ten authoritative fields and both initialized publications.
	for field in original:
		if field!="water_receipt": exact=exact and original[field]==state[field]
	var old_receipt: PackedByteArray=lab.raw_receipt.duplicate()
	var ignored: int=lab.ignored_receipts
	lab._settle_receipt(old_receipt,old_generation)
	var stale_ignored: bool=lab.ignored_receipts==ignored+1
	var cancellation: bool=scheduler.terminal.size()==2 and scheduler.terminal[0].result.get("cancelled",false) and scheduler.terminal[1].result.get("status")==1
	var reset_ok: bool=accepted and queued and pending_at_reset and exact and stale_ignored and cancellation and scheduler.reserved_total()==0.0 and lab.generation==old_generation+1 and lab.domain.tool_inventory_m3==lab.profile.inventory_m3 and lab.command_queue.pending.is_empty() and lab.input_scheduler.generation==lab.generation
	rows.append({"case":"reset_during_admitted_transaction","pass":reset_ok,"pending_at_reset":pending_at_reset,"all_fields_exact":exact,"old_receipt_ignored":stale_ignored,"old_terminal":scheduler.terminal,"new_generation":lab.generation})
	var count: int=lab.input_results.size()
	var new_ok: bool=lab._start_input(&"place_sand",Vector3(0.0625,0,0.0625),Vector3(0.0625,0,0.0625),&"circle",0.015)
	while lab.input_running: await process_frame
	var result: Dictionary=lab.input_results[-1].receipt if lab.input_results.size()>count else {}
	var active: bool=new_ok and result.get("status")==1 and result.get("command_id")==1 and result.get("generation")==lab.generation and not lab.collision_needed.is_empty()
	rows.append({"case":"new_generation_input","pass":active,"receipt":result})
	var ok: bool=reset_ok and active and lab.last_error.is_empty()
	_write(ok,lab.last_error);await lab.shutdown();lab.queue_free();finished=true;print("INTERACTION_RESET_COMPLETE pass=%s" % str(ok));quit(0 if ok else 1)

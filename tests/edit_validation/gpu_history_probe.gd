extends "res://tests/edit_validation/water_transaction_probe.gd"

const History=preload("res://scripts/simulation/edit_validation/gpu_edit_history.gd")
var history
var operation_done := false
var operation_result := false

func _write(ok: bool, error := "") -> void:
	var f:=FileAccess.open(output.path_join("gpu_history_probe.json"),FileAccess.WRITE)
	f.store_string(JSON.stringify({"pass":ok,"rows":rows,"error":error,"scope":"render-thread native preimage primitive; not integrated undo/checkpoint"},"\t"))

func _operation(kind: String, value: int=0) -> bool:
	operation_done=false
	RenderingServer.call_on_render_thread(_render_operation.bind(kind,value))
	while not operation_done: await process_frame
	return operation_result

func _render_operation(kind: String, value: int) -> void:
	var ok:=true
	match kind:
		"create": history=History.new(lab.solver)
		"capture": ok=history.capture(value,lab.completed_ticks)
		"finish": ok=history.finish(value==1)
		"restore": ok=history.restore_latest(value)
		"publish": lab.solver.publish_sand()
		"flip": lab.solver.current_index=1-lab.solver.current_index
		"release": history.release();ok=history.bytes_owned==0 and history.records.is_empty() and history.pending.is_empty()
	call_deferred("_operation_complete",ok)

func _operation_complete(ok: bool) -> void: operation_result=ok;operation_done=true

func _run() -> void:
	lab=load("res://tests/edit_validation/edit_interaction_lab.tscn").instantiate()
	root.add_child(lab)
	while not lab.ready_for_ticks and lab.last_error.is_empty(): await process_frame
	var count: int=lab.profile.grid_size*lab.profile.grid_size
	var fields: Dictionary={}
	for field in ["sediment","wetness","compaction","momentum_x","momentum_z"]:
		var values:=PackedFloat32Array();values.resize(count)
		for i in count:
			values[i]=float(i%17)*0.001 if field not in ["momentum_x","momentum_z"] else float(i%13-6)*0.002
		fields[field]=values
	await lab.seed_test_fields(fields)
	lab.water_policy=3;lab.signed_speed_m_s=0.25
	var before: Dictionary=await _snapshot("before")
	await _operation("create")
	var captured: bool=await _operation("capture",1)
	var duplicate_denied: bool=not await _operation("capture",2)
	var result: Dictionary=await lab.apply_gpu_command(_command(1,0.015))
	var accepted: bool=await _operation("finish",1)
	var edited: Dictionary=await _snapshot("edited")
	var changed: bool=before.sand!=edited.sand and before.water!=edited.water and before.momentum_x!=edited.momentum_x
	var cross_tick_denied: bool=not await _operation("restore",1)
	var restored: bool=await _operation("restore",0)
	await _operation("publish")
	var after: Dictionary=await _snapshot("restored")
	var exact:=true
	for field in before:
		if field!="water_receipt": exact=exact and before[field]==after[field]
	await _operation("flip")
	var other: Dictionary=await _snapshot("restored_other_ping")
	for field in History.FIELDS: exact=exact and before[field]==other[field]
	await _operation("flip")
	var ok: bool=captured and duplicate_denied and accepted and result.get("status")==1 and changed and cross_tick_denied and restored and exact
	rows.append({"case":"native_preimage_restores_both_ping_pongs","pass":ok,"all_fields_exact":exact,"candidate_fields_changed":changed,"cross_tick_denied":cross_tick_denied,"duplicate_capture_denied":duplicate_denied,"receipt":result})
	var bounded:=true
	for id in range(2,35):
		bounded=await _operation("capture",id) and bounded
		bounded=await _operation("finish",1) and bounded
	var retained: int=history.records.size()
	var retained_bytes: int=history.bytes_owned
	var first_id: int=history.records[0].command_id
	var pending_capture: bool=await _operation("capture",35)
	var discarded: bool=await _operation("finish",0)
	bounded=bounded and retained==32 and first_id==3 and retained_bytes==count*24*32 and history.bytes_owned==retained_bytes and history.peak_bytes<=History.MAX_BYTES and pending_capture and discarded
	rows.append({"case":"bounded_ring_and_discard","pass":bounded,"records":retained,"first_retained_id":first_id,"bytes":retained_bytes,"peak_bytes":history.peak_bytes,"limit_bytes":History.MAX_BYTES})
	var released: bool=await _operation("release")
	rows.append({"case":"release_all_native_textures","pass":released})
	ok=ok and bounded and released and lab.last_error.is_empty()
	_write(ok,lab.last_error);await lab.shutdown();lab.queue_free();finished=true;print("GPU_HISTORY_COMPLETE pass=%s" % str(ok));quit(0 if ok else 1)

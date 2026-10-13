extends "res://tests/edit_validation/water_transaction_probe.gd"

const Codec=preload("res://scripts/simulation/edit_validation/gpu_checkpoint_codec.gd")
const Scheduler=preload("res://scripts/simulation/edit_validation/gpu_edit_scheduler.gd")
var restore_done := false
var restore_ok := false

func _write(ok: bool, error := "") -> void:
	var f:=FileAccess.open(output.path_join("checkpoint_codec_probe.json"),FileAccess.WRITE)
	f.store_string(JSON.stringify({"pass":ok,"rows":rows,"error":error,"scope":"checksummed native sidecar + isolated cold restore and continued fields; live save coordinator not yet"},"\t"))

func _equal(a: Dictionary, b: Dictionary) -> bool:
	for field in a:
		if field!="water_receipt" and a[field]!=b[field]: return false
	return true

func _ledger(entry) -> Dictionary:
	var result: Dictionary={}
	for key in ["tool_inventory_m3","water_source_m3","water_sink_m3","sand_source_m3","sand_sink_m3"]: result[key]=entry.domain.get(key)
	return result

func _restore_raw(fields: Dictionary, revision: int) -> void:
	var ok: bool=lab.solver.restore_native_fields(fields,revision)
	if ok:
		lab.solver.owner_generation=lab.generation
		lab._publish_render()
	call_deferred("_restore_complete",ok)

func _restore_complete(ok: bool) -> void: restore_ok=ok;restore_done=true

func _run() -> void:
	lab=load("res://tests/edit_validation/edit_recovery_lab.tscn").instantiate();lab.local_dispatch=true
	root.add_child(lab)
	while not lab.ready_for_ticks and lab.last_error.is_empty(): await process_frame
	var fields: Dictionary={}
	for field in ["wetness","compaction","sediment","momentum_x","momentum_z"]:
		var values:=PackedFloat32Array();values.resize(65536)
		for i in 65536: values[i]=float(i%11)*0.005 if field not in ["momentum_x","momentum_z"] else float(i%7-3)*0.002
		fields[field]=values
	await lab.seed_test_fields(fields)
	var scheduler=Scheduler.new(lab)
	var first_id: int=9007199254740993
	var future:=_command(first_id,0.015);future.sim_tick=2
	var current:=_command(first_id+1,0.01)
	var admitted: bool=scheduler.submit(future,1,0.0)==&"" and scheduler.submit(current,3,0.25)==&""
	await scheduler.drain_due();await lab.set_paused(false);await scheduler.advance_ticks(2);await lab.set_paused(true)
	var source=lab
	var before: Dictionary=await _snapshot("source_checkpoint")
	var raw: Dictionary={}
	for field in Codec.FIELD_BYTES: raw[field]=before[field]
	var built:=Codec.build(raw,_ledger(lab),lab.execution_prefix,lab.completed_ticks,lab.generation,lab.solver.state_revision,lab.command_queue.last_command_id,lab.command_queue.pending.size(),scheduler.reserved_total())
	if not built.error.is_empty(): _write(false,String(built.error));finished=true;quit(1);return
	var path:=output.path_join("native_checkpoint.scp")
	var saved: StringName=Codec.save(path,built.checkpoint)
	var loaded:=Codec.load(path)
	var roundtrip: bool=admitted and saved==&"" and loaded.error==&"" and loaded.sidecar.prefix==source.execution_prefix and loaded.sidecar.prefix[0].command.command_id==first_id+1 and loaded.sidecar.prefix[1].command.command_id==first_id and loaded.sidecar.highwater_id==first_id+1
	rows.append({"case":"native_int64_nonmonotonic_execution_prefix_roundtrip","pass":roundtrip,"tick":lab.completed_ticks,"command_ids":[first_id+1,first_id],"legacy_projection_count":loaded.checkpoint.command_ids.size()})
	var duplicate: StringName=Codec.save(path,built.checkpoint)
	rows.append({"case":"existing_checkpoint_not_overwritten","pass":duplicate==&"already_exists"})
	for variation in ["pending","reservation","version","size","nan","half","obstacle","duplicate_id","projection"]:
		var bad: Dictionary=built.checkpoint.duplicate(true)
		match variation:
			"pending": bad.gpu_edit_sidecar.pending_count=1
			"reservation": bad.gpu_edit_sidecar.reserved_m3=0.001
			"version": bad.gpu_edit_sidecar.version=2
			"size": bad.gpu_edit_sidecar.raw_fields.flux.resize(4)
			"nan": bad.gpu_edit_sidecar.raw_fields.water.encode_float(0,NAN)
			"half": bad.gpu_edit_sidecar.raw_fields.compaction.encode_half(0,INF)
			"obstacle": bad.gpu_edit_sidecar.raw_fields.obstacle[0]=12
			"duplicate_id": bad.gpu_edit_sidecar.prefix.append(bad.gpu_edit_sidecar.prefix[0].duplicate(true))
			"projection": bad.fields.momentum_x[0]+=0.01
		var bad_path:=output.path_join("rejected_"+variation+".scp")
		var error: StringName=Codec.save(bad_path,bad)
		rows.append({"case":"reject_"+variation,"pass":not error.is_empty() and not FileAccess.file_exists(bad_path),"error":String(error)})
	var bytes:=FileAccess.get_file_as_bytes(path);bytes[bytes.size()-1]^=1
	var corrupt_path:=output.path_join("corrupt_checkpoint.scp")
	var f:=FileAccess.open(corrupt_path,FileAccess.WRITE);f.store_buffer(bytes);f.close()
	rows.append({"case":"checksum_rejects_corruption","pass":Codec.load(corrupt_path).error==&"checksum_mismatch"})
	source.visible=false;source.set_process_unhandled_input(false)
	lab=load("res://tests/edit_validation/edit_recovery_lab.tscn").instantiate();lab.local_dispatch=true;lab.visible=false;lab.set_process_unhandled_input(false)
	root.add_child(lab)
	while not lab.ready_for_ticks and lab.last_error.is_empty(): await process_frame
	lab.domain.restore(loaded.checkpoint.shadow)
	lab.generation=maxi(lab.generation,loaded.sidecar.generation)+1;lab.domain.generation=lab.generation
	lab.completed_ticks=loaded.sidecar.tick
	lab.command_queue=lab.Queue.new(lab.domain);lab.command_queue.last_command_id=loaded.sidecar.highwater_id
	lab.execution_prefix=loaded.sidecar.prefix.duplicate(true)
	for item in lab.execution_prefix:
		if item.result.status==1: lab.command_queue.applied_log.append(item.command.duplicate(true))
	lab.input_scheduler=Scheduler.new(lab)
	lab.collision_proxy.generation=lab.generation
	RenderingServer.call_on_render_thread(_restore_raw.bind(loaded.sidecar.raw_fields,loaded.sidecar.revision))
	while not restore_done: await process_frame
	var restored: Dictionary=await _snapshot("restored_checkpoint")
	rows.append({"case":"isolated_cold_restore_all_native_fields","pass":restore_ok and _equal(before,restored) and _ledger(source)==_ledger(lab) and lab.completed_ticks==source.completed_ticks,"generation":lab.generation})
	var target=lab
	var continuation: Dictionary={}
	for entry in [source,target]:
		lab=entry;lab.water_policy=3;lab.signed_speed_m_s=-0.25
		var result: Dictionary=await lab.apply_gpu_command(_command(first_id+2,0.015))
		await lab.set_paused(false);await lab.advance_ticks(3);await lab.set_paused(true)
		continuation["source" if entry==source else "restored"]={"state":await _snapshot("source_continue" if entry==source else "restored_continue"),"ledger":_ledger(entry),"result":result,"tick":entry.completed_ticks}
	var pair: bool=_equal(continuation.source.state,continuation.restored.state) and continuation.source.ledger==continuation.restored.ledger and continuation.source.tick==continuation.restored.tick and continuation.source.result.status==1 and continuation.restored.result.status==1
	rows.append({"case":"same_input_and_three_ticks_strict_continuation","pass":pair,"tick":target.completed_ticks,"source_generation":source.generation,"restored_generation":target.generation})
	var ok: bool=source.last_error.is_empty() and target.last_error.is_empty()
	for row in rows: ok=ok and row.pass
	_write(ok);await source.shutdown();await target.shutdown();source.queue_free();target.queue_free();finished=true;print("CHECKPOINT_CODEC_COMPLETE pass=%s rows=%d" % [str(ok),rows.size()]);quit(0 if ok else 1)

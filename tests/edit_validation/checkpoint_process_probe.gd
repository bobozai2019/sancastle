extends "res://tests/edit_validation/undo_probe.gd"

var mode := "write"
var checkpoint_source := ""

func _write(ok: bool, error := "") -> void:
	var f:=FileAccess.open(output.path_join("checkpoint_process_probe.json"),FileAccess.WRITE)
	f.store_string(JSON.stringify({"pass":ok,"rows":rows,"error":error,"mode":mode,"source":checkpoint_source,"scope":"separate native process strict fields, ledger and rendered pixels"},"\t"))

func _ledger() -> Dictionary:
	var result: Dictionary={}
	for key in ["tool_inventory_m3","water_source_m3","water_sink_m3","sand_source_m3","sand_sink_m3"]: result[key]=lab.domain.get(key)
	return result

func _record_state(prefix: String) -> Dictionary:
	var state: Dictionary=await _snapshot(prefix)
	await process_frame;await process_frame
	var image:=root.get_texture().get_image()
	image.save_png(output.path_join(prefix+".png"))
	return state

func _check_files(state: Dictionary, prefix: String) -> bool:
	for field in state:
		if field!="water_receipt" and state[field]!=FileAccess.get_file_as_bytes(checkpoint_source.path_join(prefix+"_"+field+".bin")): return false
	return true

func _pixels(prefix: String) -> bool:
	var actual:=Image.load_from_file(output.path_join(prefix+".png"))
	var expected:=Image.load_from_file(checkpoint_source.path_join(prefix+".png"))
	return actual.get_size()==expected.get_size() and actual.get_format()==expected.get_format() and actual.get_data()==expected.get_data()

func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--checkpoint-mode="): mode=arg.trim_prefix("--checkpoint-mode=")
		if arg.begins_with("--checkpoint-source="): checkpoint_source=arg.trim_prefix("--checkpoint-source=")
	lab=load("res://tests/edit_validation/edit_checkpoint_lab.tscn").instantiate();lab.local_dispatch=true
	root.add_child(lab)
	while not lab.ready_for_ticks and lab.last_error.is_empty(): await process_frame
	var canonical: Dictionary={}
	if mode=="write":
		lab.water_policy=3;lab.signed_speed_m_s=0.25
		var first: Dictionary=await lab.apply_gpu_command(_command(1,0.015))
		await lab.set_paused(false);await lab.advance_ticks(2);await lab.set_paused(true)
		var saved: StringName=await lab.save_checkpoint(output.path_join("process_checkpoint.scp"))
		await _record_state("checkpoint")
		_save("checkpoint_ledger.bin",var_to_bytes(_ledger()))
		canonical=_command(2,0.01);canonical.transform.position_m=Vector3(4.0625,0,0.0625)
		_save("continuation_command.bin",var_to_bytes(canonical))
		rows.append({"case":"writer_checkpoint","pass":first.get("status")==1 and saved==&"","tick":lab.completed_ticks})
	elif mode=="read":
		var restored: StringName=await lab.restore_checkpoint(checkpoint_source.path_join("process_checkpoint.scp"))
		var state: Dictionary=await _record_state("checkpoint")
		var expected_ledger: Dictionary=bytes_to_var(FileAccess.get_file_as_bytes(checkpoint_source.path_join("checkpoint_ledger.bin")))
		rows.append({"case":"reader_restored_checkpoint","pass":restored==&"" and _check_files(state,"checkpoint") and _ledger()==expected_ledger and _collision_exact(state) and _pixels("checkpoint"),"pixels_exact":_pixels("checkpoint"),"tick":lab.completed_ticks,"generation":lab.generation})
		canonical=bytes_to_var(FileAccess.get_file_as_bytes(checkpoint_source.path_join("continuation_command.bin")))
		canonical.generation=lab.generation
	else: _write(false,"invalid process mode");finished=true;quit(1);return
	lab.water_policy=1;lab.signed_speed_m_s=0.0
	var result: Dictionary=await lab.apply_gpu_command(canonical)
	await lab.set_paused(false);await lab.advance_ticks(3);await lab.set_paused(true)
	var state: Dictionary=await _record_state("continued")
	_save("continued_ledger.bin",var_to_bytes(_ledger()))
	if mode=="write": rows.append({"case":"writer_continuation","pass":result.get("status")==1 and lab.completed_ticks==5})
	else:
		var ledger: Dictionary=bytes_to_var(FileAccess.get_file_as_bytes(checkpoint_source.path_join("continued_ledger.bin")))
		rows.append({"case":"reader_strict_continuation","pass":result.get("status")==1 and _check_files(state,"continued") and _ledger()==ledger and _collision_exact(state) and _pixels("continued") and lab.completed_ticks==5,"pixels_exact":_pixels("continued"),"tick":lab.completed_ticks,"source_checkpoint_sha256":FileAccess.get_sha256(checkpoint_source.path_join("process_checkpoint.scp"))})
	var ok: bool=lab.last_error.is_empty()
	for row in rows: ok=ok and row.pass
	_write(ok,lab.last_error);await lab.shutdown();lab.queue_free();finished=true;print("CHECKPOINT_PROCESS_COMPLETE mode=%s pass=%s" % [mode,str(ok)]);quit(0 if ok else 1)

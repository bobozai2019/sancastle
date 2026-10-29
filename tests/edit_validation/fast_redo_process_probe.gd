extends "res://tests/edit_validation/checkpoint_process_probe.gd"

func _write(ok: bool, error := "") -> void:
	var file:=FileAccess.open(output.path_join("fast_redo_process_probe.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass":ok,"rows":rows,"error":error,"mode":mode,"source":checkpoint_source,"scope":"disk fast undo target, same tick fresh ID, time-advanced strict replay in independent process"},"\t"))

func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--checkpoint-mode="): mode=arg.trim_prefix("--checkpoint-mode=")
		if arg.begins_with("--checkpoint-source="): checkpoint_source=arg.trim_prefix("--checkpoint-source=")
	lab=load("res://tests/edit_validation/edit_checkpoint_lab.tscn").instantiate();lab.local_dispatch=true
	root.add_child(lab)
	while not lab.ready_for_ticks and lab.last_error.is_empty(): await process_frame
	if mode=="write":
		lab.water_policy=3;lab.signed_speed_m_s=0.25
		var applied: Dictionary=await lab.apply_gpu_command(_command(1,0.015))
		var undone: Dictionary=await lab.undo_latest()
		var saved: StringName=await lab.save_checkpoint(output.path_join("fast_redo.scp"))
		await _record_state("checkpoint");_save("checkpoint_ledger.bin",var_to_bytes(_ledger()))
		rows.append({"case":"writer_fast_target_saved","pass":applied.get("status")==1 and undone.get("ok",false) and saved==&"" and lab.redo_commands.size()==1 and lab.redo_commands[-1].get("same_tick_transaction",false)})
		var redone: Dictionary=await lab.redo_latest()
		await _record_state("same_redone");_save("same_redone_ledger.bin",var_to_bytes(_ledger()))
		await lab.set_paused(false);await lab.advance_ticks(3);await lab.set_paused(true)
		await _record_state("advanced_redone");_save("advanced_redone_ledger.bin",var_to_bytes(_ledger()))
		rows.append({"case":"writer_reference_fresh_redo_and_three_ticks","pass":redone.get("status")==1 and redone.get("command_id")==2 and lab.completed_ticks==3})
	else:
		var path:=checkpoint_source.path_join("fast_redo.scp")
		var restored: StringName=await lab.restore_checkpoint(path)
		var state: Dictionary=await _record_state("checkpoint")
		rows.append({"case":"reader_fast_target_and_same_tick_mode","pass":restored==&"" and lab.redo_commands.size()==1 and lab.redo_commands[-1].get("same_tick_transaction",false) and _check_files(state,"checkpoint") and _pixels("checkpoint") and _ledger()==bytes_to_var(FileAccess.get_file_as_bytes(checkpoint_source.path_join("checkpoint_ledger.bin")))})
		var redone: Dictionary=await lab.redo_latest()
		state=await _record_state("same_redone")
		rows.append({"case":"reader_same_tick_fresh_transaction","pass":redone.get("status")==1 and redone.get("command_id")==2 and _check_files(state,"same_redone") and _pixels("same_redone") and _collision_exact(state) and _ledger()==bytes_to_var(FileAccess.get_file_as_bytes(checkpoint_source.path_join("same_redone_ledger.bin")))})
		restored=await lab.restore_checkpoint(path)
		await lab.set_paused(false);await lab.advance_ticks(3);await lab.set_paused(true)
		var stack: Array=lab.redo_commands.duplicate(true)
		var before: Dictionary=await _snapshot("before_conflict")
		var stock: Dictionary=_ledger()
		lab.redo_commands[-1].replay_target.field_sha256.water="0".repeat(64)
		var rejected: Dictionary=await lab.redo_latest()
		var after: Dictionary=await _snapshot("after_conflict")
		rows.append({"case":"reader_archived_hash_conflict_preserves_branch","pass":rejected.get("error")=="replay_target_mismatch" and _same(before,after) and _ledger()==stock and lab.completed_ticks==3 and lab.redo_commands.size()==1})
		lab.redo_commands=stack
		var advanced: Dictionary=await lab.redo_latest()
		state=await _record_state("advanced_redone")
		rows.append({"case":"reader_time_advanced_fast_redo","pass":restored==&"" and advanced.get("ok",false) and advanced.get("target_fields_exact",false) and _check_files(state,"advanced_redone") and _pixels("advanced_redone") and _collision_exact(state) and _ledger()==bytes_to_var(FileAccess.get_file_as_bytes(checkpoint_source.path_join("advanced_redone_ledger.bin"))) and lab.redo_commands.is_empty() and lab.completed_ticks==3,"redo":advanced})
	var ok: bool=lab.last_error.is_empty()
	for row in rows: ok=ok and row.pass
	_write(ok,lab.last_error);await lab.shutdown();lab.queue_free();finished=true;print("FAST_REDO_PROCESS_COMPLETE mode=%s pass=%s" % [mode,str(ok)]);quit(0 if ok else 1)

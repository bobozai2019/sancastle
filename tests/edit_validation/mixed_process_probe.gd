extends "res://tests/edit_validation/checkpoint_process_probe.gd"

func _write(ok: bool, error := "") -> void:
	var f:=FileAccess.open(output.path_join("mixed_process_probe.json"),FileAccess.WRITE)
	f.store_string(JSON.stringify({"pass":ok,"rows":rows,"error":error,"mode":mode,"source":checkpoint_source,"scope":"original CPU compact/smooth mixed with native GPU E/dig; disk strict replay and pixels"},"\t"))

func _legacy(id: int, kind: StringName) -> Dictionary:
	var command:=_command(id,0.01)
	command.kind=kind;command.strength=0.6;command.erase("amount_m3")
	return command

func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--checkpoint-mode="): mode=arg.trim_prefix("--checkpoint-mode=")
		if arg.begins_with("--checkpoint-source="): checkpoint_source=arg.trim_prefix("--checkpoint-source=")
	lab=load("res://tests/edit_validation/edit_checkpoint_lab.tscn").instantiate();lab.local_dispatch=true
	root.add_child(lab)
	while not lab.ready_for_ticks and lab.last_error.is_empty(): await process_frame
	if mode=="write":
		lab.water_policy=3;lab.signed_speed_m_s=0.25
		var gpu: Dictionary=await lab.apply_gpu_command(_command(1,0.015))
		var before: Dictionary=await _snapshot("before_legacy")
		var compact: Dictionary=await lab.apply_legacy_command(_legacy(2,&"compact"))
		var smooth: Dictionary=await lab.apply_legacy_command(_legacy(3,&"smooth"))
		var after: Dictionary=await _snapshot("after_legacy")
		var preserved:=true
		for field in ["water","momentum_x","momentum_z","sediment"]: preserved=preserved and before[field]==after[field]
		rows.append({"case":"CPU_legacy_preserves_h_q_sed_and_changes_compaction_sand","pass":gpu.get("status")==1 and compact.get("results",[]).size()==1 and smooth.get("results",[]).size()==1 and preserved and before.compaction!=after.compaction and before.sand!=after.sand,"water_fields_exact":preserved,"compact_result":compact,"smooth_result":smooth})
		var dig:=_command(4,0.005);dig.kind=&"remove_sand"
		var last: Dictionary=await lab.apply_gpu_command(dig)
		await lab.set_paused(false);await lab.advance_ticks(3);await lab.set_paused(true)
		await _record_state("redone");_save("redone_ledger.bin",var_to_bytes(_ledger()))
		var undone_gpu: Dictionary=await lab.undo_latest()
		var undone_smooth: Dictionary=await lab.undo_latest()
		await _record_state("checkpoint");_save("checkpoint_ledger.bin",var_to_bytes(_ledger()))
		var saved: StringName=await lab.save_checkpoint(output.path_join("mixed_checkpoint.scp"))
		rows.append({"case":"mixed_undo_and_save_with_CPU_prefix_and_redo","pass":last.get("status")==1 and undone_gpu.get("ok",false) and undone_smooth.get("ok",false) and saved==&"" and lab.execution_prefix.size()==2 and lab.execution_prefix[-1].backend=="legacy_cpu" and lab.redo_commands.size()==2,"gpu_undo":undone_gpu,"smooth_undo":undone_smooth,"prefix":lab.execution_prefix})
	else:
		var restored: StringName=await lab.restore_checkpoint(checkpoint_source.path_join("mixed_checkpoint.scp"))
		var state: Dictionary=await _record_state("checkpoint")
		var ledger: Dictionary=bytes_to_var(FileAccess.get_file_as_bytes(checkpoint_source.path_join("checkpoint_ledger.bin")))
		rows.append({"case":"reader_restores_mixed_CPU_prefix","pass":restored==&"" and _check_files(state,"checkpoint") and _ledger()==ledger and _collision_exact(state) and _pixels("checkpoint") and lab.execution_prefix[-1].backend=="legacy_cpu","pixels_exact":_pixels("checkpoint")})
		var first: Dictionary=await lab.redo_latest()
		var second: Dictionary=await lab.redo_latest()
		state=await _record_state("redone")
		ledger=bytes_to_var(FileAccess.get_file_as_bytes(checkpoint_source.path_join("redone_ledger.bin")))
		rows.append({"case":"reader_mixed_legacy_and_GPU_redo_strict_pair","pass":first.get("ok",false) and second.get("ok",false) and _check_files(state,"redone") and _ledger()==ledger and _collision_exact(state) and _pixels("redone") and lab.execution_prefix.size()==4 and lab.redo_commands.is_empty(),"pixels_exact":_pixels("redone"),"first":first,"second":second})
	var ok: bool=lab.last_error.is_empty()
	for row in rows: ok=ok and row.pass
	_write(ok,lab.last_error);await lab.shutdown();lab.queue_free();finished=true;print("MIXED_PROCESS_COMPLETE mode=%s pass=%s" % [mode,str(ok)]);quit(0 if ok else 1)

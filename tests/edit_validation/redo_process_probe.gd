extends "res://tests/edit_validation/checkpoint_process_probe.gd"

const Codec=preload("res://scripts/simulation/edit_validation/gpu_checkpoint_codec.gd")

func _write(ok: bool, error := "") -> void:
	var f:=FileAccess.open(output.path_join("redo_process_probe.json"),FileAccess.WRITE)
	f.store_string(JSON.stringify({"pass":ok,"rows":rows,"error":error,"mode":mode,"source":checkpoint_source,"scope":"disk redo compact prefix pool and separate-process strict replay"},"\t"))

func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--checkpoint-mode="): mode=arg.trim_prefix("--checkpoint-mode=")
		if arg.begins_with("--checkpoint-source="): checkpoint_source=arg.trim_prefix("--checkpoint-source=")
	lab=load("res://tests/edit_validation/edit_checkpoint_lab.tscn").instantiate();lab.local_dispatch=true
	root.add_child(lab)
	while not lab.ready_for_ticks and lab.last_error.is_empty(): await process_frame
	if mode=="write":
		lab.water_policy=3;lab.signed_speed_m_s=0.25
		var a: Dictionary=await lab.apply_gpu_command(_command(1,0.015))
		await lab.set_paused(false);await lab.advance_ticks(1);await lab.set_paused(true)
		lab.water_policy=1;lab.signed_speed_m_s=0.0
		var b: Dictionary=await lab.apply_gpu_command(_command(2,0.01))
		await lab.set_paused(false);await lab.advance_ticks(3);await lab.set_paused(true)
		await _record_state("redone");_save("redone_ledger.bin",var_to_bytes(_ledger()))
		var undo_a: Dictionary=await lab.undo_latest()
		var undo_b: Dictionary=await lab.undo_latest()
		await _record_state("checkpoint");_save("checkpoint_ledger.bin",var_to_bytes(_ledger()))
		var path:=output.path_join("redo_checkpoint.scp")
		var saved: StringName=await lab.save_checkpoint(path)
		var loaded:=Codec.load(path)
		var file:=FileAccess.open(path,FileAccess.READ)
		rows.append({"case":"writer_compact_redo_pool","pass":a.status==1 and b.status==1 and undo_a.get("ok",false) and undo_b.get("ok",false) and saved==&"" and loaded.error==&"" and loaded.checkpoint.gpu_edit_redo.records.size()==2 and loaded.checkpoint.gpu_edit_redo.prefix_items.size()==2 and file.get_length()<32*1024*1024,"file_bytes":file.get_length(),"records":loaded.checkpoint.gpu_edit_redo.records.size(),"pool_entries":loaded.checkpoint.gpu_edit_redo.prefix_items.size()})
		file.close()
		# Codec capacity fixture, not 32 actual user transactions.
		var repeated: Array=[]
		for i in 16: repeated.append_array(lab.redo_commands.duplicate(true))
		var capacity: Dictionary=loaded.checkpoint.duplicate(true)
		capacity.gpu_edit_redo=lab.RedoCodec.pack(repeated)
		var decoded: Dictionary=lab.RedoCodec.unpack(capacity.gpu_edit_redo,capacity.gpu_edit_sidecar,lab.domain.domain_id)
		var capacity_path:=output.path_join("redo_capacity_32.scp")
		var capacity_error: StringName=Codec.save(capacity_path,capacity)
		var capacity_file:=FileAccess.open(capacity_path,FileAccess.READ)
		rows.append({"case":"synthetic_32_record_codec_capacity","pass":decoded.error==&"" and decoded.records.size()==32 and capacity_error==&"" and capacity.gpu_edit_redo.prefix_items.size()==2 and capacity_file.get_length()<32*1024*1024,"records":decoded.records.size(),"pool_entries":capacity.gpu_edit_redo.prefix_items.size(),"file_bytes":capacity_file.get_length()})
		capacity_file.close()
		for variation in ["reference","hash","version"]:
			var bad: Dictionary=loaded.checkpoint.duplicate(true)
			match variation:
				"reference": bad.gpu_edit_redo.records[0].replay_target.prefix_indices[0]=9999
				"hash": bad.gpu_edit_redo.records[0].replay_target.field_sha256.water="z".repeat(64)
				"version": bad.gpu_edit_redo.version=2
			var bad_path:=output.path_join("bad_redo_"+variation+".scp")
			var write_error: StringName=Codec.save(bad_path,bad)
			var before_generation: int=lab.generation
			var rejected: StringName=await lab.restore_checkpoint(bad_path)
			rows.append({"case":"reject_redo_"+variation,"pass":write_error==&"" and not rejected.is_empty() and lab.generation==before_generation and lab.redo_commands.size()==2,"error":String(rejected)})
	else:
		var restored: StringName=await lab.restore_checkpoint(checkpoint_source.path_join("redo_checkpoint.scp"))
		var state: Dictionary=await _record_state("checkpoint")
		var ledger: Dictionary=bytes_to_var(FileAccess.get_file_as_bytes(checkpoint_source.path_join("checkpoint_ledger.bin")))
		rows.append({"case":"reader_restores_compact_redo_stack","pass":restored==&"" and lab.redo_commands.size()==2 and lab.redo_commands[-1].has("replay_target") and _check_files(state,"checkpoint") and _ledger()==ledger and _pixels("checkpoint"),"pixels_exact":_pixels("checkpoint")})
		var first: Dictionary=await lab.redo_latest()
		var second: Dictionary=await lab.redo_latest()
		state=await _record_state("redone")
		ledger=bytes_to_var(FileAccess.get_file_as_bytes(checkpoint_source.path_join("redone_ledger.bin")))
		rows.append({"case":"reader_two_strict_cross_tick_redos","pass":first.get("ok",false) and second.get("ok",false) and _check_files(state,"redone") and _ledger()==ledger and _collision_exact(state) and _pixels("redone") and lab.redo_commands.is_empty() and lab.completed_ticks==4,"pixels_exact":_pixels("redone"),"first":first,"second":second,"events":lab.replay_events})
	var ok: bool=lab.last_error.is_empty()
	for row in rows: ok=ok and row.pass
	_write(ok,lab.last_error);await lab.shutdown();lab.queue_free();finished=true;print("REDO_PROCESS_COMPLETE mode=%s pass=%s" % [mode,str(ok)]);quit(0 if ok else 1)

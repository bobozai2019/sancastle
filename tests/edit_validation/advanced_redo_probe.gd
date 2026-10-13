extends "res://tests/edit_validation/undo_probe.gd"

var source
var reference

func _write(ok: bool, error := "") -> void:
	var f:=FileAccess.open(output.path_join("advanced_redo_probe.json"),FileAccess.WRITE)
	f.store_string(JSON.stringify({"pass":ok,"rows":rows,"error":error,"scope":"cross-tick redo validates archived tick then advances both branches to current tick"},"\t"))

func _ledger(entry) -> Dictionary:
	var result: Dictionary={}
	for key in ["tool_inventory_m3","water_source_m3","water_sink_m3","sand_source_m3","sand_sink_m3"]: result[key]=entry.domain.get(key)
	return result

func _setup() -> void:
	lab=load("res://tests/edit_validation/edit_checkpoint_lab.tscn").instantiate();lab.local_dispatch=true
	root.add_child(lab)
	while not lab.ready_for_ticks and lab.last_error.is_empty(): await process_frame

func _run() -> void:
	await _setup();source=lab
	lab.water_policy=3;lab.signed_speed_m_s=0.25
	await lab.apply_gpu_command(_command(1,0.015))
	await lab.set_paused(false);await lab.advance_ticks(1);await lab.set_paused(true)
	lab.water_policy=1;lab.signed_speed_m_s=0.0
	await lab.apply_gpu_command(_command(2,0.01))
	await lab.set_paused(false);await lab.advance_ticks(2);await lab.set_paused(true)
	var prefix: Array=lab.execution_prefix.duplicate(true)
	var undone: Dictionary=await lab.undo_latest()
	await lab.set_paused(false);await lab.advance_ticks(2);await lab.set_paused(true)
	var redone: Dictionary=await lab.redo_latest()
	var actual: Dictionary=await _snapshot("advanced_redone")
	var ledger: Dictionary=_ledger(source)
	rows.append({"case":"redo_after_two_more_ticks","pass":undone.get("ok",false) and redone.get("ok",false) and redone.get("target_fields_exact",false) and source.completed_ticks==5 and source.redo_commands.is_empty() and _collision_exact(actual),"undo":undone,"redo":redone,"events":source.replay_events})
	source.visible=false;source.set_process_unhandled_input(false)
	await _setup();reference=lab
	reference.history_enabled=false;reference.replay_mode=true
	var restored: StringName=await reference.restore_checkpoint_data(source.replay_anchor)
	var commands_exact:=true
	for item in prefix:
		await reference.set_paused(false);await reference.advance_ticks(item.execution_tick-reference.completed_ticks);await reference.set_paused(true)
		var result: Dictionary=await reference._replay_native_item(item)
		commands_exact=commands_exact and result.error==&""
	await reference.set_paused(false);await reference.advance_ticks(5-reference.completed_ticks);await reference.set_paused(true)
	var expected: Dictionary=await _snapshot("original_branch_at_current_tick")
	rows.append({"case":"matches_original_full_branch_at_tick5","pass":restored==&"" and commands_exact and _same(actual,expected) and ledger==_ledger(reference),"tick":reference.completed_ticks})
	await reference.shutdown();reference.queue_free()
	await _setup();reference=lab
	reference.water_policy=3;reference.signed_speed_m_s=0.25
	await reference.apply_gpu_command(_command(1,0.015))
	var original: Dictionary=await _snapshot("fast_original_tick0")
	var original_ledger: Dictionary=_ledger(reference)
	var fast_undo: Dictionary=await reference.undo_latest()
	var target_valid: bool=reference.redo_commands.size()==1 and reference.redo_commands[-1].get("same_tick_transaction",false) and reference.redo_commands[-1].has("replay_target")
	# The same tick path still creates a fresh acknowledged transaction.
	var same_redo: Dictionary=await reference.redo_latest()
	var same_state: Dictionary=await _snapshot("fast_same_tick_redone")
	rows.append({"case":"fast_undo_retains_target_and_same_tick_redo_identity","pass":fast_undo.get("ok",false) and target_valid and same_redo.get("status")==1 and same_redo.command_id==2 and _same(original,same_state) and _ledger(reference)==original_ledger,"undo":fast_undo,"redo":same_redo})
	var fast_prefix: Array=reference.execution_prefix.duplicate(true)
	var second_undo: Dictionary=await reference.undo_latest()
	await reference.set_paused(false);await reference.advance_ticks(3);await reference.set_paused(true)
	var fast_redo: Dictionary=await reference.redo_latest()
	var fast_actual: Dictionary=await _snapshot("fast_redone_after_three_ticks")
	var fast_ledger: Dictionary=_ledger(reference)
	rows.append({"case":"fast_undo_redo_after_time_advance","pass":second_undo.get("ok",false) and fast_redo.get("ok",false) and fast_redo.get("target_fields_exact",false) and reference.completed_ticks==3 and reference.redo_commands.is_empty() and _collision_exact(fast_actual),"redo":fast_redo})
	var fast_source=reference
	fast_source.visible=false;fast_source.set_process_unhandled_input(false)
	await _setup();reference=lab;reference.history_enabled=false;reference.replay_mode=true
	var fast_restored: StringName=await reference.restore_checkpoint_data(fast_source.replay_anchor)
	var fast_commands_exact:=true
	for item in fast_prefix:
		var replayed: Dictionary=await reference._replay_native_item(item)
		fast_commands_exact=fast_commands_exact and replayed.error==&""
	await reference.set_paused(false);await reference.advance_ticks(3);await reference.set_paused(true)
	var fast_expected: Dictionary=await _snapshot("fast_original_branch_at_tick3")
	rows.append({"case":"fast_redo_matches_original_branch_at_tick3","pass":fast_restored==&"" and fast_commands_exact and _same(fast_actual,fast_expected) and fast_ledger==_ledger(reference)})
	await fast_source.shutdown();fast_source.queue_free()
	var ok: bool=source.last_error.is_empty() and reference.last_error.is_empty()
	for row in rows: ok=ok and row.pass
	_write(ok);await source.shutdown();await reference.shutdown();source.queue_free();reference.queue_free();finished=true;print("ADVANCED_REDO_COMPLETE pass=%s" % str(ok));quit(0 if ok else 1)

extends "res://tests/edit_validation/undo_probe.gd"

var source
var reference

func _write(ok: bool, error := "") -> void:
	var f:=FileAccess.open(output.path_join("cross_tick_undo_probe.json"),FileAccess.WRITE)
	f.store_string(JSON.stringify({"pass":ok,"rows":rows,"error":error,"scope":"original-prefix strict replay before counterfactual cross-tick undo and redo"},"\t"))

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
	var first:=_command(1,0.015);first.sim_tick=2
	var second:=_command(2,0.01)
	var a: bool=lab.input_scheduler.submit(first,1,0.0)==&""
	var b: bool=lab.input_scheduler.submit(second,3,0.25)==&""
	await lab.input_scheduler.drain_due();await lab.set_paused(false);await lab.input_scheduler.advance_ticks(2);await lab.advance_ticks(2);await lab.set_paused(true)
	var rejected: Dictionary=await lab.apply_gpu_command(_command(3,10.0))
	var prefix: Array=lab.execution_prefix.duplicate(true)
	var current: Dictionary=await _snapshot("before_undo")
	var ledger: Dictionary=_ledger(source)
	var generation: int=lab.generation
	var old_solver=lab.solver
	lab.execution_prefix[0].stock_before+=0.005
	var denied: Dictionary=await lab.undo_latest()
	var after_denial: Dictionary=await _snapshot("after_mismatched_replay")
	rows.append({"case":"original_replay_input_conflict_preserves_current","pass":denied.get("error")=="replay_current_mismatch" and _same(current,after_denial) and _ledger(lab)==ledger and lab.generation==generation and lab.solver==old_solver and lab.ready_for_ticks and lab.input_scheduler.accepting,"result":denied})
	lab.execution_prefix=prefix.duplicate(true)
	var result: Dictionary=await lab.undo_latest()
	var undone: Dictionary=await _snapshot("cross_tick_undone")
	var source_ledger: Dictionary=_ledger(source)
	var first_ok: bool=a and b and rejected.get("status")==2 and result.get("ok",false) and result.get("command_id")==1 and result.get("original_fields_exact",false) and lab.completed_ticks==4 and lab.command_queue.last_command_id==3 and lab.execution_prefix.size()==1 and lab.execution_prefix[0].command.command_id==2 and _collision_exact(undone) and _ray_error(undone)<=1e-5 and lab.generation>generation and old_solver.rd==null
	rows.append({"case":"cross_tick_undo_nonmonotonic_ID_and_rejected_tail","pass":first_ok,"result":result,"events":lab.replay_events.duplicate(true),"tick":lab.completed_ticks,"remaining_id":lab.execution_prefix[0].command.command_id})
	source.set_process_unhandled_input(false);source.visible=false
	await _setup();reference=lab
	reference.history_enabled=false;reference.replay_mode=true
	var anchor_error: StringName=await reference.restore_checkpoint_data(source.replay_anchor)
	var replayed: Dictionary=await reference._replay_native_item(prefix[0])
	await reference.set_paused(false);await reference.advance_ticks(4);await reference.set_paused(true)
	var expected: Dictionary=await _snapshot("only_surviving_command_reference")
	rows.append({"case":"counterfactual_matches_independent_completed_branch","pass":anchor_error==&"" and replayed.error==&"" and _same(undone,expected) and source_ledger==_ledger(reference),"reference_tick":reference.completed_ticks})
	lab=source
	var second_undo: Dictionary=await source.undo_latest()
	var empty: Dictionary=await _snapshot("empty_prefix_undo")
	await reference.restore_checkpoint_data(source.replay_anchor)
	await reference.set_paused(false);await reference.advance_ticks(4);await reference.set_paused(true)
	lab=reference
	var flat: Dictionary=await _snapshot("empty_prefix_reference")
	rows.append({"case":"evicted_fast_history_uses_anchor_for_next_undo","pass":second_undo.get("ok",false) and _same(empty,flat) and _ledger(source)==_ledger(reference) and source.execution_prefix.is_empty() and source.command_queue.last_command_id==3 and source.redo_commands.size()==2,"result":second_undo})
	lab=source
	var stack: Array=source.redo_commands.duplicate(true)
	var empty_ledger: Dictionary=_ledger(source)
	var before_redo_generation: int=source.generation
	var old_value: float=source.redo_commands[-1].replay_checkpoint.gpu_edit_sidecar.raw_fields.water.decode_float(0)
	source.redo_commands[-1].replay_checkpoint.gpu_edit_sidecar.raw_fields.water.encode_float(0,old_value+0.001)
	var redo_denied: Dictionary=await source.redo_latest()
	var after_redo_denial: Dictionary=await _snapshot("redo_conflict_preserved")
	rows.append({"case":"redo_target_conflict_preserves_current","pass":redo_denied.get("error")=="replay_target_mismatch" and _same(empty,after_redo_denial) and _ledger(source)==empty_ledger and source.generation==before_redo_generation and source.redo_commands.size()==2,"result":redo_denied})
	source.redo_commands=stack.duplicate(true)
	var first_redo: Dictionary=await source.redo_latest()
	var first_redone: Dictionary=await _snapshot("first_cross_tick_redone")
	rows.append({"case":"cross_tick_redo_surviving_branch","pass":first_redo.get("ok",false) and _same(first_redone,undone) and _ledger(source)==source_ledger and source.redo_commands.size()==1 and source.execution_prefix.size()==1,"result":first_redo})
	var second_redo: Dictionary=await source.redo_latest()
	var second_redone: Dictionary=await _snapshot("second_cross_tick_redone")
	rows.append({"case":"cross_tick_redo_original_branch_with_rejection","pass":second_redo.get("ok",false) and _same(second_redone,current) and _ledger(source)==ledger and source.redo_commands.is_empty() and source.execution_prefix.size()==3 and source.execution_prefix[-1].result.status==2 and _collision_exact(second_redone) and source.command_queue.last_command_id==3,"result":second_redo,"events":source.replay_events})
	var ok: bool=source.last_error.is_empty() and reference.last_error.is_empty()
	for row in rows: ok=ok and row.pass
	_write(ok);await source.shutdown();await reference.shutdown();source.queue_free();reference.queue_free();finished=true;print("CROSS_TICK_UNDO_COMPLETE pass=%s rows=%d" % [str(ok),rows.size()]);quit(0 if ok else 1)

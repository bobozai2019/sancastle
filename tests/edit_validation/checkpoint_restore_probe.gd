extends "res://tests/edit_validation/undo_probe.gd"

const Codec=preload("res://scripts/simulation/edit_validation/gpu_checkpoint_codec.gd")

func _write(ok: bool, error := "") -> void:
	var f:=FileAccess.open(output.path_join("checkpoint_restore_probe.json"),FileAccess.WRITE)
	f.store_string(JSON.stringify({"pass":ok,"rows":rows,"error":error,"scope":"live isolated candidate commit, restored collision and fields, rejected restore preserves current branch"},"\t"))

func _ledger(entry) -> Dictionary:
	var values: Dictionary={}
	for key in ["tool_inventory_m3","water_source_m3","water_sink_m3","sand_source_m3","sand_sink_m3"]: values[key]=entry.domain.get(key)
	return values

func _setup() -> void:
	lab=load("res://tests/edit_validation/edit_checkpoint_lab.tscn").instantiate();lab.local_dispatch=true
	root.add_child(lab)
	while not lab.ready_for_ticks and lab.last_error.is_empty(): await process_frame

func _run() -> void:
	await _setup()
	lab.water_policy=1
	var a:=_command(1,0.015);a.transform.position_m=Vector3(-3.9375,0,0.0625)
	var first: Dictionary=await lab.apply_gpu_command(a)
	lab.water_policy=3;lab.signed_speed_m_s=-0.25
	var b:=_command(2,0.01);b.transform.position_m=Vector3(4.0625,0,0.0625)
	var second: Dictionary=await lab.apply_gpu_command(b)
	await lab.set_paused(false);await lab.advance_ticks(2);await lab.set_paused(true)
	var path:=output.path_join("live_restore_checkpoint.scp")
	var saved: StringName=await lab.save_checkpoint(path)
	var saved_state: Dictionary=await _snapshot("saved_state")
	var saved_ledger: Dictionary=_ledger(lab)
	var loaded:=Codec.load(path)
	var c:=_command(3,0.04)
	var mutation: Dictionary=await lab.apply_gpu_command(c)
	var old_receipt: PackedByteArray=lab.raw_receipt.duplicate()
	var branch: Dictionary=await _snapshot("discarded_branch")
	var branch_ledger: Dictionary=_ledger(lab)
	var old_generation: int=lab.generation
	var old_solver=lab.solver
	lab.inject_restore_failure_once=true
	var failed: StringName=await lab.restore_checkpoint(path)
	var after_failure: Dictionary=await _snapshot("after_candidate_failure")
	rows.append({"case":"candidate_failure_preserves_active_branch","pass":first.status==1 and second.status==1 and mutation.status==1 and saved==&"" and failed==&"candidate_failed" and _same(branch,after_failure) and branch_ledger==_ledger(lab) and lab.generation==old_generation and lab.solver==old_solver and lab.discarded_candidate_count==1 and lab.ready_for_ticks and lab.input_scheduler.accepting,"error":String(failed)})
	for variation in ["profile","policy","clock"]:
		var checkpoint: Dictionary=loaded.checkpoint.duplicate(true)
		match variation:
			"profile": checkpoint.gpu_edit_configuration.profile_sha256="0".repeat(64)
			"policy": checkpoint.gpu_edit_configuration.signed_speed_m_s=NAN
			"clock": checkpoint.gpu_edit_configuration.visual_time_s+=1.0
		var bad_path:=output.path_join("bad_config_"+variation+".scp")
		var write_error: StringName=Codec.save(bad_path,checkpoint)
		var error: StringName=await lab.restore_checkpoint(bad_path)
		var state: Dictionary=await _snapshot("rejected_"+variation)
		rows.append({"case":"reject_config_"+variation,"pass":write_error==&"" and not error.is_empty() and _same(branch,state) and lab.generation==old_generation and _ledger(lab)==branch_ledger and lab.solver==old_solver,"error":String(error)})
	var restored: StringName=await lab.restore_checkpoint(path)
	var restored_state: Dictionary=await _snapshot("live_restored")
	var collision: bool=_collision_exact(restored_state)
	rows.append({"case":"live_restored_fields_ledger_collision_and_generation","pass":restored==&"" and _same(saved_state,restored_state) and _ledger(lab)==saved_ledger and collision and _ray_error(restored_state)<=1e-5 and lab.generation==old_generation+1 and old_solver.rd==null and lab.solver!=old_solver and lab.command_queue.last_command_id==2 and lab.completed_ticks==2 and lab.execution_prefix==loaded.sidecar.prefix,"collision_exact":collision,"old_solver_released":old_solver.rd==null,"generation":lab.generation,"revision":lab.solver.state_revision})
	var ignored: int=lab.ignored_receipts
	lab._settle_receipt(old_receipt,old_generation)
	rows.append({"case":"discarded_branch_receipt_ignored","pass":lab.ignored_receipts==ignored+1 and _ledger(lab)==saved_ledger})
	var count: int=lab.input_results.size()
	var click:=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_RIGHT;click.pressed=true
	click.position=lab.get_viewport().get_final_transform()*lab.get_node("Camera").unproject_position(Vector3(0.0625,0.4,0.0625))
	Input.parse_input_event(click)
	var deadline:=Time.get_ticks_msec()+3000
	while (lab.input_results.size()==count or lab.input_running) and Time.get_ticks_msec()<deadline: await process_frame
	var ui_result: Dictionary=lab.input_results[-1].receipt if lab.input_results.size()>count else {}
	rows.append({"case":"actual_input_after_restore","pass":ui_result.get("status")==1 and ui_result.get("command_id")==3 and ui_result.get("generation")==lab.generation,"receipt":ui_result})
	var release:=InputEventMouseButton.new();release.button_index=MOUSE_BUTTON_RIGHT;release.pressed=false;Input.parse_input_event(release)
	var canonical: Dictionary=lab.input_events[-1].command.duplicate(true)
	var source=lab
	source.set_process_unhandled_input(false);source.visible=false
	await _setup()
	var reference_error: StringName=await lab.restore_checkpoint(path)
	canonical.generation=lab.generation
	var reference_result: Dictionary=await lab.apply_gpu_command(canonical)
	var reference=lab
	var results: Dictionary={}
	for entry in [source,reference]:
		lab=entry
		await lab.set_paused(false);await lab.advance_ticks(3);await lab.set_paused(true)
		results["source" if entry==source else "reference"]={"state":await _snapshot("source_continued" if entry==source else "reference_continued"),"ledger":_ledger(entry)}
	rows.append({"case":"restored_actual_input_strict_three_tick_pair","pass":reference_error==&"" and reference_result.get("status")==1 and _same(results.source.state,results.reference.state) and results.source.ledger==results.reference.ledger and source.completed_ticks==reference.completed_ticks,"tick":source.completed_ticks})
	var ok: bool=source.last_error.is_empty() and reference.last_error.is_empty()
	for row in rows: ok=ok and row.pass
	_write(ok);await source.shutdown();await reference.shutdown();source.queue_free();reference.queue_free();finished=true;print("CHECKPOINT_RESTORE_COMPLETE pass=%s rows=%d" % [str(ok),rows.size()]);quit(0 if ok else 1)

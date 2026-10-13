extends "res://tests/edit_validation/undo_probe.gd"

var close_done := false
var close_started := false
var candidate
var previous_solver
var previous_stock := 0.0
var saved_stock := 0.0
var previous_generation := 0
var observed_phase := ""

func _write(ok: bool, error := "") -> void:
	var f:=FileAccess.open(output.path_join("checkpoint_restore_exit_probe.json"),FileAccess.WRITE)
	f.store_string(JSON.stringify({"pass":ok,"rows":rows,"error":error,"scope":"actual allocated restore candidate and post-publication close; no GPU duration inference"},"\t"))

func _close_restore() -> void:
	if close_started: return
	close_started=true
	observed_phase=lab.restore_phase
	candidate=lab.restore_candidate if lab.restore_candidate!=null else lab.solver
	await lab.shutdown()
	close_done=true

func _case(after_publish: bool) -> void:
	close_done=false;close_started=false
	lab=load("res://tests/edit_validation/edit_checkpoint_lab.tscn").instantiate()
	root.add_child(lab)
	while not lab.ready_for_ticks and lab.last_error.is_empty(): await process_frame
	lab.water_policy=0
	await lab.apply_gpu_command(_command(1,0.015))
	saved_stock=lab.domain.tool_inventory_m3
	var path:=output.path_join("exit_checkpoint_%s.scp" % str(after_publish))
	var saved: StringName=await lab.save_checkpoint(path)
	await lab.apply_gpu_command(_command(2,0.025))
	previous_stock=lab.domain.tool_inventory_m3;previous_generation=lab.generation;previous_solver=lab.solver
	lab.observe_restore_boundaries=true
	if after_publish: lab.restore_published.connect(_close_restore)
	else: lab.restore_candidate_ready.connect(_close_restore)
	var result: StringName=await lab.restore_checkpoint(path)
	while not close_done: await process_frame
	var owned: bool=candidate!=null and candidate.rd==null and previous_solver.rd==null and lab.restore_candidate==null and lab.solver==null and not lab.restore_build_pending
	var terminal: bool=result==(&"closed_after_restore_publish" if after_publish else &"closed")
	var account: bool=lab.domain.tool_inventory_m3==(saved_stock if after_publish else previous_stock)
	var phase: bool=observed_phase==("published" if after_publish else "building")
	rows.append({"case":"close_after_publish" if after_publish else "close_before_candidate_commit","pass":saved==&"" and owned and terminal and account and phase and lab.last_error.is_empty(),"error":String(result),"observed_phase":observed_phase,"resources_returned":owned,"stock":lab.domain.tool_inventory_m3,"old_stock":previous_stock,"saved_stock":saved_stock,"generation":lab.generation,"discarded_candidate_count":lab.discarded_candidate_count,"events":lab.checkpoint_events})
	lab.queue_free()

func _run() -> void:
	await _case(false)
	await _case(true)
	var ok:=true
	for row in rows: ok=ok and row.pass
	_write(ok);finished=true;print("CHECKPOINT_RESTORE_EXIT_COMPLETE pass=%s" % str(ok));quit(0 if ok else 1)

extends "res://tests/edit_validation/beach_live_restore_probe.gd"

var boundary_done := false
var boundary_observation := {}
var boundary_old_solver
var boundary_new_solver
var boundary_old_material
var boundary_new_material
var anchor_checkpoint := {}

func _write(ok: bool, error: String="") -> void:
	var file:=FileAccess.open(output.path_join("beach_restore_close_probe.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass":ok,"rows":rows,"error":error,"scope":"actual metadata/publication/collision boundaries during full beach restore close"},"\t"));file.close()

func _close_at_boundary(stage: String) -> void:
	boundary_new_solver=preview.beach_restore_candidate.solver if stage=="metadata" else preview.solver
	boundary_new_material=preview.beach_restore_candidate.material_coupler if stage=="metadata" else preview.material_coupler
	boundary_observation={"stage":stage,"phase":preview.beach_restore_phase,"generation":preview.generation,"tick":preview.completed_ticks,"ready":preview.ready_for_ticks,"accepting":preview.input_scheduler.accepting,"old_released":boundary_old_solver.rd==null,"candidate_pending":preview.beach_restore_candidate.pending,"at_us":Time.get_ticks_usec()}
	if stage=="collision": boundary_observation.collision_exact=_collision_exact(anchor_checkpoint)
	if "--beach-staged-slope" in OS.get_cmdline_user_args():
		boundary_observation.old_staged_buffer_live=boundary_old_material.result_buffer.is_valid()
		boundary_observation.new_staged_buffer_live=boundary_new_material.result_buffer.is_valid()
	await preview.shutdown();boundary_done=true

func _create_preview() -> void:
	preview=load("res://tests/edit_validation/edit_beach_recovery_lab.tscn").instantiate();preview.playing=false;root.add_child(preview)
	while not preview.ready_for_ticks and preview.last_error.is_empty(): await process_frame

func _run() -> void:
	root.size=Vector2i(1920,1080);DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	await _create_preview()
	await _ticks(15)
	preview.water_policy=3;preview.signed_speed_m_s=0.25
	var receipt: Dictionary=await preview.apply_gpu_command(_command(9007199254741103,0.01))
	await _ticks(2)
	var anchor_path:=output.path_join("anchor.scp")
	var saved: StringName=await preview.save_gpu_checkpoint(anchor_path)
	anchor_checkpoint=Store.load(anchor_path).checkpoint
	rows.append({"case":"full_edited_anchor","pass":receipt.get("status")==1 and saved==&"" and anchor_checkpoint.tick==17})
	await preview.shutdown();preview.queue_free();for i in 4: await process_frame
	for stage in ["metadata","published","collision"]:
		await _create_preview();await _ticks(1)
		boundary_done=false;boundary_observation={};boundary_old_solver=preview.solver;boundary_old_material=preview.material_coupler
		var initial_generation: int=preview.generation
		preview.observe_beach_restore=true
		var name: String="beach_restore_metadata_committed" if stage=="metadata" else ("beach_restore_published" if stage=="published" else "beach_restore_collision_ready")
		preview.connect(name,_close_at_boundary.bind(stage))
		var error: StringName=await preview.restore_gpu_checkpoint_data(anchor_checkpoint)
		while not boundary_done: await process_frame
		var valid: bool=error==&"closed_after_restore_commit" and boundary_observation.stage==stage and boundary_observation.generation==initial_generation+1 and boundary_observation.tick==17 and not boundary_observation.ready and not boundary_observation.accepting and boundary_observation.candidate_pending==0 and boundary_old_solver.rd==null and boundary_new_solver.rd==null and preview.collision_proxy.rd==null and preview.gpu_release_done and not preview.beach_restore_running and not preview.ready_for_ticks and not preview.input_scheduler.accepting and preview.gpu_release_us>=boundary_observation.at_us and preview.pending_beach_native_readbacks==0
		valid=valid and boundary_observation.old_released==(stage!="metadata")
		if stage=="collision": valid=valid and boundary_observation.collision_exact
		if "--beach-staged-slope" in OS.get_cmdline_user_args():
			valid=valid and boundary_observation.new_staged_buffer_live and boundary_observation.old_staged_buffer_live==(stage=="metadata") and not boundary_old_material.result_buffer.is_valid() and not boundary_new_material.result_buffer.is_valid() and boundary_old_material.consume_sets.is_empty() and boundary_new_material.consume_sets.is_empty() and not boundary_old_material.consume_pipeline.is_valid() and not boundary_new_material.consume_pipeline.is_valid()
		rows.append({"case":"actual_"+stage+"_close","pass":valid,"error":String(error),"observed":boundary_observation,"release_us":preview.gpu_release_us})
		preview.queue_free();for i in 4: await process_frame
	var ok:=true
	for row in rows: ok=ok and row.pass
	_write(ok);finished=true;print("BEACH_RESTORE_CLOSE_COMPLETE pass=%s"%str(ok));quit(0 if ok else 1)

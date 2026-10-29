extends "res://tests/edit_validation/beach_save_boundary_probe.gd"
var restore_close_done := false
var restore_close_pending := 0
var closed_restore_candidate
var closed_active_solver
var closed_restore_material
var closed_active_material
var retained_failed_material

func _retain_staged_failure_material() -> void:
	retained_failed_material=preview.beach_restore_candidate.material_coupler
var mutable_restore_input := {}
var mutation_pending := 0

func _mutate_restore_input() -> void:
	mutation_pending=preview.beach_restore_candidate.pending
	mutable_restore_input.gpu_beach_edit.selection.speed=0.9
	mutable_restore_input.gpu_beach_edit.ledger.tool_inventory_m3=99.0

func _close_restore_candidate() -> void:
	closed_restore_candidate=preview.beach_restore_candidate;closed_active_solver=preview.solver
	closed_restore_material=closed_restore_candidate.material_coupler;closed_active_material=preview.material_coupler
	restore_close_pending=closed_restore_candidate.pending
	await preview.shutdown();restore_close_done=true

func _write(ok: bool, error: String="") -> void:
	var file:=FileAccess.open(output.path_join("beach_live_restore_probe.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass":ok,"rows":rows,"error":error,"scope":"complete beach isolated resource bundle, native precommit verification, live publication and collision"},"\t"));file.close()

func _native_equal(a: Dictionary, b: Dictionary) -> bool:
	return a.gpu_beach_native==b.gpu_beach_native and a.fields==b.fields and a.foam_history==b.foam_history and a.local_front_history==b.local_front_history and a.gpu_beach_edit.prefix==b.gpu_beach_edit.prefix and a.gpu_beach_edit.ledger==b.gpu_beach_edit.ledger and a.gpu_beach_edit.selection==b.gpu_beach_edit.selection

func _collision_exact(checkpoint: Dictionary, exact_revision: bool=true) -> bool:
	var rock: PackedFloat32Array=checkpoint.gpu_beach_native.fields.rock.to_float32_array()
	var sand: PackedFloat32Array=checkpoint.gpu_beach_native.fields.sand.to_float32_array()
	for chunk in 64:
		var applied: int=preview.collision_proxy.applied_revisions.get(chunk,-1)
		if exact_revision and applied!=checkpoint.revision: return false
		if not exact_revision and applied<int(preview.collision_needed.get(chunk,0)): return false
		var values: PackedFloat32Array=preview.collision_proxy.shapes[chunk].shape.map_data
		for z in 33:
			for x in 33:
				var cell: int=mini((chunk/8)*32+z,255)*256+mini((chunk%8)*32+x,255)
				var expected:=PackedFloat32Array([rock[cell]+sand[cell]])
				if values[z*33+x]!=expected[0]: return false
	return true

func _run() -> void:
	root.size=Vector2i(1920,1080);DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	preview=load("res://tests/edit_validation/edit_beach_recovery_lab.tscn").instantiate();preview.playing=false;root.add_child(preview)
	while not preview.ready_for_ticks and preview.last_error.is_empty(): await process_frame
	if not preview.last_error.is_empty(): _write(false,preview.last_error);finished=true;quit(1);return
	await _ticks(15)
	preview.water_policy=3;preview.signed_speed_m_s=0.25
	var first: Dictionary=await preview.apply_gpu_command(_command(9007199254741103,0.01))
	await _ticks(2)
	var path:=output.path_join("anchor.scp")
	var saved: StringName=await preview.save_gpu_checkpoint(path)
	var anchor: Dictionary=Store.load(path).checkpoint
	await _snapshot("anchor")
	rows.append({"case":"edited_full_anchor","pass":first.get("status")==1 and saved==&"" and anchor.tick==17})
	await _ticks(2)
	var second: Dictionary=await preview.apply_gpu_command(_command(9007199254741104,0.005))
	var future:=_command(9007199254741105,0.001);future.sim_tick=preview.completed_ticks+1
	var future_admitted: bool=preview.input_scheduler.submit(future)==&""
	var future_error: StringName=await preview.restore_gpu_checkpoint_data(anchor)
	rows.append({"case":"future_pending_restore_preserves_queue","pass":future_admitted and future_error==&"pending_commands" and preview.command_queue.pending.size()==1 and preview.command_queue.pending[0].command_id==future.command_id})
	preview.input_scheduler.cancel_pending("restore_probe_cancel")
	var before_path:=output.path_join("before_failure.scp")
	saved=await preview.save_gpu_checkpoint(before_path)
	var before: Dictionary=Store.load(before_path).checkpoint
	var active=preview.solver;var old_generation: int=preview.generation
	var active_material=preview.material_coupler
	preview.playing=true
	var error: StringName=await preview.restore_gpu_checkpoint_data(anchor)
	preview.playing=false
	rows.append({"case":"restore_requires_pause","pass":error==&"requires_pause" and preview.solver==active and preview.generation==old_generation})
	var bad: Dictionary=anchor.duplicate(true);bad.gpu_beach_edit.selection.speed=NAN
	error=await preview.restore_gpu_checkpoint_data(bad)
	rows.append({"case":"restore_preflight_preserves_active","pass":error==&"invalid_beach_selection" and preview.solver==active and preview.generation==old_generation})
	bad=anchor.duplicate(true);bad.local_front_history=PackedFloat32Array([NAN])
	error=await preview.restore_gpu_checkpoint_data(bad)
	rows.append({"case":"legacy_envelope_preflight_preserves_active","pass":error==&"invalid_local_front_history" and preview.solver==active and preview.generation==old_generation})
	preview.inject_beach_restore_failure=true
	if "--beach-staged-slope" in OS.get_cmdline_user_args():
		preview.observe_beach_restore=true;preview.beach_restore_submitted.connect(_retain_staged_failure_material,CONNECT_ONE_SHOT)
	error=await preview.restore_gpu_checkpoint_data(anchor)
	preview.observe_beach_restore=false
	var after_path:=output.path_join("after_failure.scp")
	saved=await preview.save_gpu_checkpoint(after_path)
	var after: Dictionary=Store.load(after_path).checkpoint
	rows.append({"case":"isolated_build_failure_retains_complete_branch","pass":error==&"candidate_injected_failure" and preview.solver==active and preview.generation==old_generation and _native_equal(before,after) and before.highwater_id==after.highwater_id and preview.completed_ticks==19 and preview.ready_for_ticks and not preview.beach_restore_running,"error":String(error)})
	if "--beach-staged-slope" in OS.get_cmdline_user_args():
		var failed_material=retained_failed_material
		rows.append({"case":"staged_failed_bundle_releases_private_buffer","pass":active_material.result_buffer.is_valid() and failed_material!=null and not failed_material.result_buffer.is_valid() and failed_material.consume_sets.is_empty() and not failed_material.consume_pipeline.is_valid()})
	mutable_restore_input=anchor.duplicate(true)
	preview.observe_beach_restore=true;preview.beach_restore_submitted.connect(_mutate_restore_input)
	error=await preview.restore_gpu_checkpoint_data(mutable_restore_input)
	preview.beach_restore_submitted.disconnect(_mutate_restore_input);preview.observe_beach_restore=false
	var restored_path:=output.path_join("restored.scp")
	saved=await preview.save_gpu_checkpoint(restored_path)
	var restored: Dictionary=Store.load(restored_path).checkpoint
	rows.append({"case":"live_restore_all_native_fields_history_ledger_prefix","pass":error==&"" and saved==&"" and _native_equal(anchor,restored) and preview.completed_ticks==17 and preview.generation==old_generation+1 and active.rd==null and preview.visual_time_s==17.0/30.0,"error":String(error),"phase":preview.beach_restore_phase})
	if "--beach-staged-slope" in OS.get_cmdline_user_args():
		rows.append({"case":"staged_swap_releases_old_private_buffer","pass":not active_material.result_buffer.is_valid() and preview.material_coupler.result_buffer.is_valid() and active_material.consume_sets.is_empty()})
	rows.append({"case":"restore_owns_immutable_async_input","pass":mutation_pending>0 and mutable_restore_input.gpu_beach_edit.ledger.tool_inventory_m3==99.0 and preview.domain.tool_inventory_m3==anchor.gpu_beach_edit.ledger.tool_inventory_m3 and preview.signed_speed_m_s==anchor.gpu_beach_edit.selection.speed,"pending_at_mutation":mutation_pending})
	rows.append({"case":"live_restore_64_collision_chunks","pass":_collision_exact(anchor)})
	await _snapshot("restored")
	var anchor_image:=Image.load_from_file(output.path_join("anchor.png"));var restored_image:=Image.load_from_file(output.path_join("restored.png"))
	rows.append({"case":"live_restore_published_pixels","pass":anchor_image.get_size()==restored_image.get_size() and anchor_image.get_data()==restored_image.get_data()})
	var stale:=_command(9007199254741105,0.001);stale.generation=old_generation
	var rejected: Dictionary=await preview.apply_gpu_command(stale)
	var fresh: Dictionary=await preview.apply_gpu_command(_command(9007199254741105,0.001))
	rows.append({"case":"restored_generation_admission","pass":rejected.has("error") and fresh.get("status")==1 and preview.gpu_prefix.size()==2 and preview.command_queue.last_command_id==9007199254741105,"stale":rejected})
	await _ticks(2)
	rows.append({"case":"restored_original_coupled_continuation","pass":preview.completed_ticks==19 and preview.last_error.is_empty() and preview.solver.state_revision>anchor.revision})
	preview.observe_beach_restore=true;preview.beach_restore_submitted.connect(_close_restore_candidate)
	error=await preview.restore_gpu_checkpoint_data(anchor)
	while not restore_close_done: await process_frame
	if "--beach-staged-slope" in OS.get_cmdline_user_args():
		rows.append({"case":"staged_precommit_close_releases_both_buffers","pass":closed_restore_material!=null and not closed_restore_material.result_buffer.is_valid() and not closed_active_material.result_buffer.is_valid() and closed_restore_material.consume_sets.is_empty() and closed_active_material.consume_sets.is_empty()})
	rows.append({"case":"close_owns_actual_candidate_readbacks","pass":error==&"closed_before_restore_commit" and restore_close_pending>0 and closed_restore_candidate.pending==0 and closed_restore_candidate.released and closed_restore_candidate.solver.rd==null and closed_active_solver.rd==null and preview.gpu_release_us>=closed_restore_candidate.release_us and closed_restore_candidate.release_us>=closed_restore_candidate.last_callback_us,"error":String(error),"pending_at_close":restore_close_pending,"last_callback_us":closed_restore_candidate.last_callback_us,"candidate_release_us":closed_restore_candidate.release_us,"active_release_us":preview.gpu_release_us})
	var verified:=true
	for check in preview.beach_restore_verifications: verified=verified and check.expected==23 and check.observed==23 and check.pending==0 and check.error.is_empty()
	rows.append({"case":"all_candidate_native_precommit_checks","pass":verified,"checks":preview.beach_restore_verifications})
	var ok: bool=preview.last_error.is_empty()
	for row in rows: ok=ok and row.pass
	_write(ok,preview.last_error);preview.queue_free();for i in 8: await process_frame
	finished=true;print("BEACH_LIVE_RESTORE_COMPLETE pass=%s"%str(ok));quit(0 if ok else 1)

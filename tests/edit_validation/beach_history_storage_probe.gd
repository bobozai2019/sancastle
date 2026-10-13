extends "res://tests/edit_validation/beach_save_boundary_probe.gd"

const History=preload("res://scripts/simulation/edit_validation/beach_gpu_edit_history.gd")
var history=History.new()
var storage_done := false
var storage_rows := []
var restore_ok := false

func _write(ok: bool, error: String="") -> void:
	var file:=FileAccess.open(output.path_join("beach_history_storage_probe.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass":ok,"rows":rows,"error":error,"scope":"full beach same-tick physical-slot GPU history primitive; not public undo/redo coordinator"},"\t"));file.close()

func _capture_storage() -> void:
	var success:=true
	for i in 33:
		var identity: Dictionary={"generation":preview.generation,"tick":preview.completed_ticks,"command_id":9007199254741103 if i==32 else i+1}
		success=success and history.capture(preview.solver,identity)
		history.finish(preview.solver,true)
	storage_rows.append({"case":"bounded_both_physical_slot_preimages","pass":success and history.records.size()==32 and history.records[0].identity.command_id==2 and history.bytes_owned==80*1024*1024 and history.peak_bytes==82.5*1024*1024,"records":history.records.size(),"owned_bytes":history.bytes_owned,"peak_bytes":history.peak_bytes})
	var identity: Dictionary={"generation":preview.generation,"tick":preview.completed_ticks,"command_id":9007199254741104}
	var held: bool=history.capture(preview.solver,identity)
	var refused: bool=not history.capture(preview.solver,identity)
	history.finish(preview.solver,false)
	storage_rows.append({"case":"pending_refusal_and_discard","pass":held and refused and history.pending.is_empty() and history.records.size()==32 and history.bytes_owned==80*1024*1024})
	var other_domain:=SandWaterDomain.new(preview.solver.grid_size,preview.solver.cell_size_m)
	other_domain.generation=preview.generation
	var other=preview._create_solver()
	var initialized: bool=other.initialize(preview.solver.rd,other_domain,preview.spirvs[0],preview.spirvs[1],preview.spirvs[2],preview.spirvs[3],preview.spirvs[4],preview.spirvs[5],preview.spirvs[6],preview.spirvs[7])
	var wrong_owner: bool=initialized and not history.restore_latest(other,preview.generation,preview.completed_ticks)
	other.release()
	storage_rows.append({"case":"same_device_same_generation_other_solver_refused","pass":wrong_owner})
	storage_done=true

func _restore_storage() -> void:
	var wrong_tick: bool=not history.restore_latest(preview.solver,preview.generation,preview.completed_ticks+1)
	var wrong_generation: bool=not history.restore_latest(preview.solver,preview.generation+1,preview.completed_ticks)
	restore_ok=history.restore_latest(preview.solver,preview.generation,preview.completed_ticks)
	preview._publish_textures()
	storage_rows.append({"case":"same_tick_generation_guards","pass":wrong_tick and wrong_generation and restore_ok})
	storage_done=true

func _release_storage() -> void:
	history.release(preview.solver);storage_done=true

func _run() -> void:
	root.size=Vector2i(1920,1080);DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	preview=load("res://tests/edit_validation/edit_beach_recovery_lab.tscn").instantiate();preview.playing=false;root.add_child(preview)
	while not preview.ready_for_ticks and preview.last_error.is_empty(): await process_frame
	await _ticks(17)
	preview.input_scheduler.accepting=false;preview.set_process_unhandled_input(false)
	var before_path:=output.path_join("before.scp")
	var saved: StringName=await preview.save_gpu_checkpoint(before_path)
	var before: Dictionary=Store.load(before_path).checkpoint
	RenderingServer.call_on_render_thread(_capture_storage)
	while not storage_done: await process_frame
	preview.water_policy=3;preview.signed_speed_m_s=0.25
	var receipt: Dictionary=await preview.apply_gpu_command(_command(9007199254741103,0.01))
	saved=await preview.save_gpu_checkpoint(output.path_join("edited.scp"))
	var edited: Dictionary=Store.load(output.path_join("edited.scp")).checkpoint
	var spare_changed:=false
	for field in ["water","sediment","momentum_x","momentum_z"]: spare_changed=spare_changed or before.gpu_beach_native.spare[field]!=edited.gpu_beach_native.spare[field]
	rows.append({"case":"actual_full_E_changes_prior_spare_state","pass":receipt.get("status")==1 and saved==&"" and spare_changed})
	storage_done=false;RenderingServer.call_on_render_thread(_restore_storage)
	while not storage_done: await process_frame
	# Test-only metadata settlement; the primitive itself does not manage stock,
	# prefix, generation, collision, or redo. Do not continue this test branch.
	preview.domain.tool_inventory_m3=before.gpu_beach_edit.ledger.tool_inventory_m3
	preview.gpu_prefix=before.gpu_beach_edit.prefix.duplicate(true);preview.command_queue.applied_log.clear()
	preview.water_policy=before.gpu_beach_edit.selection.policy;preview.signed_speed_m_s=before.gpu_beach_edit.selection.speed
	saved=await preview.save_gpu_checkpoint(output.path_join("restored.scp"))
	var restored: Dictionary=Store.load(output.path_join("restored.scp")).checkpoint
	rows.append({"case":"all_current_spare_and_visual_history_bytes_retained","pass":restore_ok and saved==&"" and before.gpu_beach_native==restored.gpu_beach_native and before.local_front_history.to_byte_array()==restored.local_front_history.to_byte_array() and before.revision==restored.revision})
	storage_done=false;RenderingServer.call_on_render_thread(_release_storage)
	while not storage_done: await process_frame
	rows.append({"case":"history_release_before_solver_close","pass":history.records.is_empty() and history.pending.is_empty() and history.bytes_owned==0})
	rows.append_array(storage_rows)
	await preview.shutdown()
	var ok: bool=preview.last_error.is_empty()
	for row in rows: ok=ok and row.pass
	_write(ok,preview.last_error);preview.queue_free();for i in 4: await process_frame
	finished=true;print("BEACH_HISTORY_STORAGE_COMPLETE pass=%s"%str(ok));quit(0 if ok else 1)

extends "res://tests/edit_validation/beach_live_restore_probe.gd"

var close_finished := false
var history_close_pending := 0
var close_started_us := -1

func _write(ok: bool, error: String="") -> void:
	var file:=FileAccess.open(output.path_join("beach_undo_boundary_probe.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass":ok,"rows":rows,"error":error,"scope":"actual redo target rollback and actual undo preimage readback close"},"\t"));file.close()

func _close_history_reads() -> void:
	history_close_pending=preview.history_readbacks;close_started_us=Time.get_ticks_usec()
	await preview.shutdown();close_finished=true

func _create_edited_preview(id: int) -> Dictionary:
	preview=load("res://tests/edit_validation/edit_beach_undo_lab.tscn").instantiate();preview.playing=false;root.add_child(preview)
	while not preview.ready_for_ticks and preview.last_error.is_empty(): await process_frame
	await _ticks(17)
	preview.water_policy=3;preview.signed_speed_m_s=0.25
	return await preview.apply_gpu_command(_command(id,0.01))

func _run() -> void:
	root.size=Vector2i(1920,1080);DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var id: int=9007199254741103
	var receipt: Dictionary=await _create_edited_preview(id)
	var undo: Dictionary=await preview.undo_latest()
	var baseline_path:=output.path_join("baseline.scp")
	var saved: StringName=await preview.save_gpu_checkpoint(baseline_path)
	var baseline: Dictionary=Store.load(baseline_path).checkpoint
	var expected_target: Dictionary=preview.redo_records[-1].target.duplicate(true)
	preview.redo_records[-1].target.hashes.fields_sand="0".repeat(64)
	var initial_generation: int=preview.generation
	var redo: Dictionary=await preview.redo_latest()
	var rolled_path:=output.path_join("rolled_back.scp")
	saved=await preview.save_gpu_checkpoint(rolled_path)
	var rolled: Dictionary=Store.load(rolled_path).checkpoint
	rows.append({"case":"redo_target_mismatch_rolls_back_all_native_ledger_prefix","pass":receipt.get("status")==1 and undo.get("ok",false) and redo.get("error")=="redo_target_mismatch" and saved==&"" and _native_equal(baseline,rolled) and preview.generation==initial_generation+1 and rolled.revision==baseline.revision+2 and preview.command_queue.last_command_id==id+1 and preview.full_history.records.is_empty() and preview.redo_records.size()==1 and preview.ready_for_ticks and preview.last_error.is_empty() and _collision_exact(rolled),"result":redo,"before_revision":baseline.revision,"after_revision":rolled.revision})
	preview.redo_records[-1].target=expected_target
	var retried: Dictionary=await preview.redo_latest()
	rows.append({"case":"retry_after_rollback_uses_next_real_identity","pass":retried.get("ok",false) and preview.command_queue.last_command_id==id+2 and preview.gpu_prefix.size()==1 and preview.gpu_prefix[-1].command.command_id==id+2 and preview.redo_records.is_empty() and preview.full_history.records.size()==1,"result":retried})
	await preview.shutdown();preview.queue_free();for i in 4: await process_frame
	receipt=await _create_edited_preview(id)
	var owned=preview.solver;var stock: float=preview.domain.tool_inventory_m3;var original_prefix: Array=preview.gpu_prefix.duplicate(true);initial_generation=preview.generation
	preview.observe_undo_history_reads=true;preview.undo_history_read_submitted.connect(_close_history_reads)
	undo=await preview.undo_latest()
	while not close_finished: await process_frame
	rows.append({"case":"actual_undo_history_readbacks_owned_until_close","pass":receipt.get("status")==1 and undo.get("error")=="closed" and history_close_pending>0 and preview.history_readbacks==0 and preview.history_last_callback_us>=close_started_us and preview.history_release_us>=preview.history_last_callback_us and preview.gpu_release_us>=preview.history_release_us and preview.full_history.bytes_owned==0 and owned.rd==null and preview.collision_proxy.rd==null and preview.domain.tool_inventory_m3==stock and preview.gpu_prefix==original_prefix and preview.generation==initial_generation and not preview.undo_running and not preview.input_scheduler.accepting,"result":undo,"history_close_pending":history_close_pending,"close_us":close_started_us,"callback_us":preview.history_last_callback_us,"history_release_us":preview.history_release_us,"owner_release_us":preview.gpu_release_us})
	var ok:=true
	for row in rows: ok=ok and row.pass
	_write(ok);preview.queue_free();for i in 4: await process_frame
	finished=true;print("BEACH_UNDO_BOUNDARY_COMPLETE pass=%s"%str(ok));quit(0 if ok else 1)

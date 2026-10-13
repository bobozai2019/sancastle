extends "res://tests/edit_validation/beach_mixed_restore_probe.gd"

func _write() -> void:
	var file:=FileAccess.open(output.path_join("beach_mixed_failure_probe.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass":not failed,"checks":checks,"scope":"real malformed CPU patch validation before GPU submission, provisional CPU recovery, quarantine and orderly release; no undo or post-submission fault claim"},"\t"))

func _run() -> void:
	root.size=Vector2i(1920,1080);DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	preview=load("res://tests/edit_validation/edit_beach_recovery_lab.tscn").instantiate();preview.playing=false;root.add_child(preview)
	while not preview.ready_for_ticks and preview.last_error.is_empty(): await process_frame
	if not preview.last_error.is_empty(): _error(preview.last_error);_write();finished=true;quit(1);return
	await _ticks(15);preview.water_policy=0
	var dig: Dictionary=await preview.apply_gpu_command(_command(0,&"remove_sand"))
	var compact: Dictionary=await preview.apply_legacy_command(_command(1,&"compact"))
	_check("mixed_failure_normal_control",dig.get("status")==1 and compact.get("results",[]).size()==1 and compact.results[0].status==&"applied")
	var before: Dictionary=await _all("before_failure")
	var prefix: Array=preview.gpu_prefix.duplicate(true)
	var applied: Array=preview.command_queue.applied_log.duplicate(true)
	var snapshots: Array=preview.command_queue.undo_stack.duplicate(true)
	var redo: Array=preview.command_queue.redo_stack.duplicate(true)
	var stock: float=preview.shadow_domain.tool_inventory_m3
	var revision: int=preview.solver.state_revision
	var tick: int=preview.completed_ticks
	preview.inject_legacy_patch_failure_once=true
	var result: Dictionary=await preview.apply_legacy_command(_command(2,&"smooth"))
	var after: Dictionary=await _all("after_failure")
	var exact:=true
	for key in before: exact=exact and before[key]==after[key]
	var cpu_comp:=Image.create_from_data(256,256,false,Image.FORMAT_RF,preview.shadow_domain.compaction.to_byte_array());cpu_comp.convert(Image.FORMAT_RH)
	_check("mixed_failure_native_and_cpu_atomic",result.get("error")=="paused tool patch dispatch failed" and exact and preview.solver.state_revision==revision and preview.completed_ticks==tick and preview.shadow_domain.sand.to_byte_array()==before.sand and cpu_comp.get_data()==before.compaction and preview.shadow_domain.tool_inventory_m3==stock and preview.gpu_prefix==prefix and preview.command_queue.applied_log==applied and preview.command_queue.undo_stack==snapshots and preview.command_queue.redo_stack==redo and preview.command_queue.last_command_id==9007199254741105 and preview.command_queue.pending.is_empty() and _chunks_exact(after) and await _published_exact(after),{"result":result,"all_15_fields_exact":exact,"consumed_id":preview.command_queue.last_command_id})
	var next_gpu: Dictionary=await preview.apply_gpu_command(_command(3,&"remove_sand"))
	var next_cpu: Dictionary=await preview.apply_legacy_command(_command(3,&"compact"))
	var save_path:=output.path_join("quarantine_denied.scp")
	var save_error: StringName=await preview.save_gpu_checkpoint(save_path)
	var restore_error: StringName=await preview.restore_gpu_checkpoint_data({})
	preview._start_tick();await process_frame
	_check("mixed_failure_quarantine",not preview.ready_for_ticks and not preview.playing and not preview.input_scheduler.accepting and not preview.legacy_command_running and not preview.tick_pending and next_gpu.get("error")=="backend_failed" and next_cpu.get("error")=="backend_failed" and save_error==&"backend_unavailable" and restore_error==&"backend_unavailable" and not FileAccess.file_exists(save_path) and preview.completed_ticks==tick)
	await preview.shutdown()
	_check("mixed_failure_release",preview.gpu_release_done and preview.solver.rd==null and preview.collision_proxy.rd==null)
	for item in checks: failed=failed or not item.pass
	_write();preview.queue_free();finished=true;print("BEACH_MIXED_FAILURE_COMPLETE pass=%s"%str(not failed));quit(1 if failed else 0)

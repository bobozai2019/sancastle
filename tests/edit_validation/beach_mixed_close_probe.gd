extends "res://tests/edit_validation/beach_mixed_restore_probe.gd"

var boundary_done := false
var observation := {}

func _write() -> void:
	var file:=FileAccess.open(output.path_join("beach_mixed_close_probe.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass":not failed,"checks":checks,"scope":"real CPU shadow/patch boundaries, competing native operations and orderly close; no undo, performance or cold continuation claim"},"\t"))

func _close_at_boundary(stage: String) -> void:
	var highwater: int=preview.command_queue.last_command_id
	var competing: Dictionary=_command(10,&"remove_sand")
	var gpu: Dictionary=await preview.apply_gpu_command(competing)
	var cpu: Dictionary=await preview.apply_legacy_command(_command(11,&"compact"))
	var save_path:=output.path_join(stage+"_denied.scp")
	var save_error: StringName=await preview.save_gpu_checkpoint(save_path)
	var restore_error: StringName=await preview.restore_gpu_checkpoint_data({})
	observation={"stage":stage,"legacy_running":preview.legacy_command_running,"accepting":preview.input_scheduler.accepting,"playing":preview.playing,"gpu_error":gpu.get("error"),"cpu_error":cpu.get("error"),"save_error":String(save_error),"restore_error":String(restore_error),"highwater_unchanged":preview.command_queue.last_command_id==highwater,"file_created":FileAccess.file_exists(save_path),"at_us":Time.get_ticks_usec()}
	await preview.shutdown()
	boundary_done=true

func _run() -> void:
	root.size=Vector2i(1920,1080);DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	for stage in ["shadow","patch"]:
		preview=load("res://tests/edit_validation/edit_beach_recovery_lab.tscn").instantiate();preview.playing=false;root.add_child(preview)
		while not preview.ready_for_ticks and preview.last_error.is_empty(): await process_frame
		if not preview.last_error.is_empty(): _error(preview.last_error);break
		await _ticks(15);preview.water_policy=0
		var initial: Dictionary=await preview.apply_gpu_command(_command(0,&"remove_sand"))
		boundary_done=false;observation={};preview.observe_legacy_boundaries=true
		preview.connect("legacy_shadow_ready" if stage=="shadow" else "legacy_patch_submitted",_close_at_boundary.bind(stage),CONNECT_ONE_SHOT)
		var result: Dictionary=await preview.apply_legacy_command(_command(1,&"compact"))
		while not boundary_done: await process_frame
		var passed: bool=initial.get("status")==1 and observation.legacy_running and not observation.accepting and not observation.playing and observation.gpu_error=="checkpoint_busy" and observation.cpu_error=="checkpoint_busy" and observation.save_error=="backend_unavailable" and observation.restore_error=="backend_unavailable" and observation.highwater_unchanged and not observation.file_created
		passed=passed and result.get("results",[]).size()==1 and result.results[0].status==&"applied" and preview.gpu_prefix.size()==2 and preview.command_queue.pending.is_empty() and not preview.legacy_command_running and preview.gpu_release_done and preview.gpu_release_us>=observation.at_us and preview.solver.rd==null and preview.collision_proxy.rd==null and not preview.input_scheduler.accepting and not preview.playing and preview.last_error.is_empty()
		_check("mixed_"+stage+"_competing_operations_and_close",passed,{"observation":observation,"result":result,"release_us":preview.gpu_release_us})
		preview.queue_free();for i in 4: await process_frame
	for item in checks: failed=failed or not item.pass
	_write();finished=true;print("BEACH_MIXED_CLOSE_COMPLETE pass=%s"%str(not failed));quit(1 if failed else 0)

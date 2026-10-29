extends "res://tests/edit_validation/beach_save_boundary_probe.gd"

func _write(ok: bool, error: String="") -> void:
	var file:=FileAccess.open(output.path_join("beach_capture_fault_probe.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass":ok,"rows":rows,"error":error,"scope":"full beach injected request failure or NaN derived payload; actual other callbacks and shutdown"},"\t"))

func _case(corrupt: bool) -> void:
	preview=load("res://tests/edit_validation/edit_beach_capture_fault_lab.tscn").instantiate();preview.playing=false
	root.add_child(preview)
	while not preview.ready_for_ticks and preview.last_error.is_empty(): await process_frame
	await _ticks(15)
	preview.water_policy=0
	await preview.apply_gpu_command(_command(1,0.01))
	await _snapshot("before_%s" % str(corrupt))
	var before: Dictionary=data.duplicate(true)
	var ledger:=_ledger();var prefix: Array=preview.gpu_prefix.duplicate(true)
	preview.fail_request=not corrupt;preview.corrupt_payload=corrupt
	var path:=output.path_join("invalid_payload.scp" if corrupt else "failed_request.scp")
	var saved: StringName=await preview.save_gpu_checkpoint(path)
	await _snapshot("after_%s" % str(corrupt))
	var after: Dictionary=data.duplicate(true)
	var exact:=true
	for key in before: exact=exact and before[key]==after[key]
	var denied: Dictionary=await preview.apply_gpu_command(_command(2,0.001))
	var refused: StringName=preview.input_scheduler.submit(_command(2,0.001))
	var owned=preview.solver
	await preview.shutdown()
	rows.append({"case":"corrupted_native_payload_no_file" if corrupt else "failed_last_request_returns_other_callbacks","pass":preview.injected and preview.capture_requests==27 and saved==&"capture_failed" and not FileAccess.file_exists(path) and not preview.checkpoint_capture_pending and not preview.gpu_save_running and preview.pending_beach_native_readbacks==0 and not preview.ready_for_ticks and not preview.playing and not preview.input_scheduler.accepting and exact and ledger==_ledger() and prefix==preview.gpu_prefix and denied.get("error")=="backend_failed" and refused==&"backend_unavailable" and owned.rd==null and preview.collision_proxy.rd==null and preview.gpu_release_us>=preview.beach_native_callback_us,"error":preview.last_error,"fault_us":preview.fault_us,"callback_us":preview.beach_native_callback_us,"release_us":preview.gpu_release_us,"requests":preview.capture_requests})
	preview.queue_free();for i in 8: await process_frame

func _run() -> void:
	root.size=Vector2i(1920,1080);DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	await _case(false);await _case(true)
	var ok:=true
	for row in rows: ok=ok and row.pass
	_write(ok);finished=true;print("BEACH_CAPTURE_FAULT_COMPLETE pass=%s" % str(ok));quit(0 if ok else 1)

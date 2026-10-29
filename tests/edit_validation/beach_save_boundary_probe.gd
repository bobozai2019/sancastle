extends "res://tests/edit_validation/beach_edit_process_probe.gd"

var captured := []
var close_on_capture := false
var close_done := false
var close_us := -1
var pending_at_close := 0

func _write(ok: bool, error: String="") -> void:
	var file:=FileAccess.open(output.path_join("beach_save_boundary_probe.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass":ok,"rows":rows,"error":error,"scope":"full original beach active receipt save, future pending rejection, actual native capture close ownership"},"\t"))

func _command(id: int, amount: float) -> Dictionary:
	return {"domain_id":preview.domain.domain_id,"generation":preview.generation,"sim_tick":preview.completed_ticks,"command_id":id,"kind":&"remove_sand","shape":&"circle","transform":{"position_m":Vector3(-14.8125,0,-14.8125)},"radius_m":0.75,"strength":1.0,"amount_m3":amount,"seed":101}

func _at_capture() -> void:
	var stock: float=preview.domain.tool_inventory_m3
	var id: int=preview.command_queue.last_command_id
	var command:=_command(id+1,0.001)
	var denied: Dictionary=await preview.apply_gpu_command(command)
	var queue_denied: StringName=preview.input_scheduler.submit(command)
	captured.append({"pass":preview.pending_beach_native_readbacks>0 and denied.get("error")=="checkpoint_busy" and queue_denied==&"backend_unavailable" and preview.domain.tool_inventory_m3==stock and preview.command_queue.last_command_id==id,"pending":preview.pending_beach_native_readbacks,"direct":denied,"queue":String(queue_denied)})
	if close_on_capture:
		pending_at_close=preview.pending_beach_native_readbacks;close_us=Time.get_ticks_usec()
		await preview.shutdown();close_done=true

func _run() -> void:
	root.size=Vector2i(1920,1080);DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	preview=load("res://tests/edit_validation/edit_beach_recovery_lab.tscn").instantiate();preview.playing=false
	root.add_child(preview)
	while not preview.ready_for_ticks and preview.last_error.is_empty(): await process_frame
	await _ticks(15)
	preview.observe_beach_capture=true;preview.beach_capture_submitted.connect(_at_capture)
	preview.water_policy=1
	var admitted: bool=preview.input_scheduler.submit(_command(1,0.01))==&""
	while not preview.solver.receipt_pending and preview.last_error.is_empty(): await process_frame
	var receipt_pending: bool=preview.solver.receipt_pending
	var second: bool=preview.input_scheduler.submit(_command(2,0.005))==&""
	var saved: StringName=await preview.save_gpu_checkpoint(output.path_join("active_save.scp"))
	var loaded:=Store.load(output.path_join("active_save.scp"))
	var guarded: bool=not captured.is_empty()
	for check in captured: guarded=guarded and check.pass
	rows.append({"case":"save_waits_actual_receipt_and_due_queue","pass":admitted and second and receipt_pending and saved==&"" and loaded.error==&"" and loaded.checkpoint.gpu_beach_edit.prefix.size()==2 and loaded.checkpoint.gpu_beach_edit.ledger.tool_inventory_m3==preview.domain.tool_inventory_m3 and preview.pending_beach_native_readbacks==0 and guarded,"saved_error":String(saved),"receipt_pending_at_save":receipt_pending,"capture":captured.duplicate(true)})
	var future:=_command(3,0.001);future.sim_tick=preview.completed_ticks+1
	var future_ok: bool=preview.input_scheduler.submit(future)==&""
	var rejected: StringName=await preview.save_gpu_checkpoint(output.path_join("future_rejected.scp"))
	rows.append({"case":"future_pending_save_preserves_queue","pass":future_ok and rejected==&"pending_commands" and preview.command_queue.pending.size()==1 and preview.command_queue.pending[0].command_id==3 and not FileAccess.file_exists(output.path_join("future_rejected.scp"))})
	preview.input_scheduler.cancel_pending("probe_cancel")
	captured.clear();close_on_capture=true
	var owned=preview.solver
	saved=await preview.save_gpu_checkpoint(output.path_join("close_capture.scp"))
	while not close_done: await process_frame
	loaded=Store.load(output.path_join("close_capture.scp"))
	rows.append({"case":"close_waits_actual_complete_native_capture","pass":pending_at_close>0 and saved==&"" and loaded.error==&"" and preview.pending_beach_native_readbacks==0 and preview.beach_native_callback_us>=close_us and preview.gpu_release_us>=preview.beach_native_callback_us and owned.rd==null and preview.collision_proxy.rd==null and not preview.gpu_save_running,"pending_at_close":pending_at_close,"close_us":close_us,"last_callback_us":preview.beach_native_callback_us,"release_us":preview.gpu_release_us,"capture":captured.duplicate(true)})
	var ok: bool=preview.last_error.is_empty()
	for row in rows: ok=ok and row.pass
	for row in captured: ok=ok and row.pass
	_write(ok,preview.last_error);preview.queue_free();for i in 8: await process_frame
	finished=true;print("BEACH_SAVE_BOUNDARY_COMPLETE pass=%s" % str(ok));quit(0 if ok else 1)

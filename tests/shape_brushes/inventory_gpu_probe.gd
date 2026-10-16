extends "res://tests/shape_brushes/legacy_pair_probe.gd"

func stock_command(id: int, kind: StringName, amount: float, future: bool=false) -> Dictionary:
	var value := legacy_command(id,kind,future); value.amount_m3=amount
	return value

func _run() -> void:
	root.size=Vector2i(1280,720)
	preview=load("res://tests/shape_brushes/inventory_lab.tscn").instantiate()
	preview.playing=false; preview.visual_time_s=0.0; root.add_child(preview)
	var deadline := Time.get_ticks_msec()+90000
	while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_msec()<deadline: await process_frame
	_check("inventory_backend_ready",preview.ready_for_ticks and not preview.unrestricted_sand_tools)
	if not preview.ready_for_ticks: _finish(); quit(1); return
	preview.shadow_domain.tool_inventory_m3=0.10
	var before := await snapshot("inventory_before")
	var admitted: bool=preview.input_scheduler.submit(stock_command(1,&"place_sand",0.04,true)).is_empty() and preview.input_scheduler.submit(stock_command(2,&"place_sand",0.04,true)).is_empty()
	_check("real_backend_reserves_two_fills",admitted and absf(preview.input_scheduler.reserved_total()-0.08)<1e-12 and preview.domain.tool_inventory_m3==0.10)
	var error: StringName=preview.input_scheduler.submit(stock_command(3,&"place_sand",0.03,true))
	_check("overdraw_preserves_queue_highwater",error==&"insufficient_inventory" and preview.command_queue.last_command_id==2 and preview.command_queue.pending.size()==2 and absf(preview.input_scheduler.reserved_total()-0.08)<1e-12)
	var after := await snapshot("inventory_denied")
	_check("reserved_and_denied_do_not_edit",exact(before,after))
	preview.input_scheduler.cancel_pending("stock_probe")
	_check("inventory_cancel_releases_all",preview.input_scheduler.reserved_total()==0.0 and preview.command_queue.pending.is_empty())
	var filled := 0.0
	for id in [3,4]:
		error=preview.input_scheduler.submit(stock_command(id,&"place_sand",0.04))
		await settle()
		var result: Dictionary=preview.input_scheduler.terminal[-1].result
		_check("stock_fill_"+str(id),error.is_empty() and result.get("status")==1,result)
		filled+=result.get("actual_sand_m3",0.0)
		var stock_once: float=preview.domain.tool_inventory_m3
		var applied_once: int=preview.command_queue.applied_log.size()
		preview._settle_gpu_receipt(preview.legacy_packet,preview.legacy_packet_epoch)
		_check("old_receipt_duplicate_once_"+str(id),preview.domain.tool_inventory_m3==stock_once and preview.command_queue.applied_log.size()==applied_once and preview.last_error.is_empty())
	_check("actual_fill_debits_inventory",absf(preview.domain.tool_inventory_m3-(0.10-filled))<1e-12 and absf(filled-0.08)<1e-6)
	error=preview.input_scheduler.submit(stock_command(5,&"place_sand",0.03))
	_check("exhausted_stock_rejects_before_gpu",error==&"insufficient_inventory" and preview.command_queue.last_command_id==4 and preview.command_queue.pending.is_empty())
	error=preview.input_scheduler.submit(stock_command(5,&"remove_sand",0.02))
	await settle()
	var dig: Dictionary=preview.input_scheduler.terminal[-1].result
	_check("dig_credits_actual_inventory",error.is_empty() and dig.get("status")==1 and absf(preview.domain.tool_inventory_m3-(0.10-filled+dig.actual_sand_m3))<1e-12,dig)
	_check("bucket_has_no_external_source_sink",preview.domain.sand_source_m3==0.0 and preview.domain.sand_sink_m3==0.0 and preview.input_scheduler.reserved_total()==0.0)
	var final := await snapshot("inventory_final")
	var a: PackedFloat32Array=before.sand.to_float32_array()
	var b: PackedFloat32Array=final.sand.to_float32_array()
	var delta := 0.0
	for i in a.size(): delta+=(b[i]-a[i])*0.015625
	_check("gpu_sand_plus_stock_closes_original_eps",absf(delta+preview.domain.tool_inventory_m3-0.10)<=1e-6,{"sand_delta":delta,"inventory":preview.domain.tool_inventory_m3,"eps":1e-6})
	var file := FileAccess.open(output.path_join("inventory_evidence.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"raw_index":raw_index,"terminal":preview.input_scheduler.terminal,"prefix":preview.gpu_prefix,"stock":preview.domain.tool_inventory_m3,"source_signature":preview.source_signature,"scope":"original bucket accounting on real new-entry legacy GPU route; new brushes disabled"},"\t")); file.close()
	await preview.shutdown(); _check("inventory_clean_shutdown",preview.gpu_release_done)
	_finish(); var ok := true
	for row in checks: ok=ok and row.pass
	quit(0 if ok else 1)

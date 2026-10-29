extends "res://tests/edit_validation/beach_live_restore_probe.gd"

func _write(ok: bool, error: String="") -> void:
	var file:=FileAccess.open(output.path_join("beach_same_tick_undo_probe.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass":ok,"rows":rows,"error":error,"scope":"complete beach same-tick B/C/D/E undo and fresh-ID redo, native/ledger/collision and actual keys"},"\t"));file.close()

func _watchdog() -> void:
	var started:=Time.get_ticks_msec()
	while not finished:
		if Time.get_ticks_msec()-started>300000: _write(false,"timeout");quit(1);return
		await process_frame

func _key(code: Key) -> Dictionary:
	var count: int=preview.recovery_key_results.size()
	var event:=InputEventKey.new();event.keycode=code;event.physical_keycode=code;event.ctrl_pressed=true;event.pressed=true
	Input.parse_input_event(event)
	while preview.recovery_key_results.size()==count and preview.last_error.is_empty(): await process_frame
	return preview.recovery_key_results[-1] if preview.recovery_key_results.size()>count else {"error":preview.last_error}

func _run() -> void:
	root.size=Vector2i(1920,1080);DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	for policy in 4:
		preview=load("res://tests/edit_validation/edit_beach_undo_lab.tscn").instantiate();preview.playing=false;root.add_child(preview)
		while not preview.ready_for_ticks and preview.last_error.is_empty(): await process_frame
		await _ticks(17)
		preview.water_policy=0;preview.signed_speed_m_s=0.0
		var first_id: int=9007199254741103+policy*10
		var dug: Dictionary=await preview.apply_gpu_command(_command(first_id,0.02))
		preview.water_policy=policy;preview.signed_speed_m_s=(-0.25 if policy==3 else 0.25) if policy>=2 else 0.0
		var base_path:=output.path_join("p%d_base.scp"%policy)
		var saved: StringName=await preview.save_gpu_checkpoint(base_path)
		var baseline: Dictionary=Store.load(base_path).checkpoint
		await _snapshot("p%d_base"%policy)
		var command:=_command(first_id+1,0.01);command.kind=&"place_sand"
		var placed: Dictionary=await preview.apply_gpu_command(command)
		var edited_path:=output.path_join("p%d_edited.scp"%policy)
		saved=await preview.save_gpu_checkpoint(edited_path)
		var edited: Dictionary=Store.load(edited_path).checkpoint
		await _snapshot("p%d_edited"%policy)
		var initial_generation: int=preview.generation
		var undo: Dictionary=await _key(KEY_Z) if policy==2 else await preview.undo_latest()
		var undone_path:=output.path_join("p%d_undo.scp"%policy)
		saved=await preview.save_gpu_checkpoint(undone_path)
		var undone: Dictionary=Store.load(undone_path).checkpoint
		rows.append({"case":"p%d_full_undo"%policy,"pass":dug.get("status")==1 and placed.get("status")==1 and undo.get("ok",false) and saved==&"" and _native_equal(baseline,undone) and undone.revision==edited.revision+1 and preview.generation==initial_generation+1 and preview.full_history.records.size()==1 and preview.redo_records.size()==1 and preview.command_queue.last_command_id==first_id+1 and _collision_exact(undone),"result":undo,"previous_revision":edited.revision,"restored_revision":undone.revision})
		await _snapshot("p%d_undo"%policy)
		var image_a:=Image.load_from_file(output.path_join("p%d_base.png"%policy));var image_b:=Image.load_from_file(output.path_join("p%d_undo.png"%policy))
		rows.append({"case":"p%d_undo_pixels"%policy,"pass":image_a.get_data()==image_b.get_data()})
		var redo: Dictionary=await _key(KEY_Y) if policy==2 else await preview.redo_latest()
		var redo_path:=output.path_join("p%d_redo.scp"%policy)
		saved=await preview.save_gpu_checkpoint(redo_path)
		var redone: Dictionary=Store.load(redo_path).checkpoint
		rows.append({"case":"p%d_full_redo"%policy,"pass":redo.get("ok",false) and saved==&"" and preview._fingerprint(edited)==preview._fingerprint(redone) and preview.full_history.records.size()==2 and preview.redo_records.is_empty() and preview.gpu_prefix.size()==2 and preview.gpu_prefix[-1].command.command_id==first_id+2 and _collision_exact(edited,false),"result":redo})
		await _snapshot("p%d_redo"%policy)
		image_a=Image.load_from_file(output.path_join("p%d_edited.png"%policy));image_b=Image.load_from_file(output.path_join("p%d_redo.png"%policy))
		rows.append({"case":"p%d_redo_pixels"%policy,"pass":image_a.get_data()==image_b.get_data()})
		if policy==0:
			var undo_first: Dictionary=await preview.undo_latest()
			var undo_second: Dictionary=await preview.undo_latest()
			rows.append({"case":"two_consecutive_undos_across_new_generations","pass":undo_first.get("ok",false) and undo_second.get("ok",false) and preview.gpu_prefix.is_empty() and preview.full_history.records.is_empty() and preview.redo_records.size()==2 and preview.domain.tool_inventory_m3==0.0})
			var redo_first: Dictionary=await preview.redo_latest()
			var redo_second: Dictionary=await preview.redo_latest()
			var twice_path:=output.path_join("two_redos.scp")
			saved=await preview.save_gpu_checkpoint(twice_path)
			var twice: Dictionary=Store.load(twice_path).checkpoint
			rows.append({"case":"two_redos_recreate_native_target_and_fresh_ids","pass":redo_first.get("ok",false) and redo_second.get("ok",false) and saved==&"" and preview._fingerprint(twice)==preview._fingerprint(edited) and preview.full_history.records.size()==2 and preview.redo_records.is_empty() and preview.gpu_prefix.size()==2 and preview.command_queue.last_command_id==first_id+4})
		await _ticks(1)
		var before_stock: float=preview.domain.tool_inventory_m3
		var blocked: Dictionary=await preview.undo_latest()
		rows.append({"case":"p%d_cross_tick_fast_path_refused"%policy,"pass":blocked.get("error")=="requires_checkpoint_replay" and preview.domain.tool_inventory_m3==before_stock and preview.gpu_prefix.size()==2})
		await preview.shutdown()
		rows.append({"case":"p%d_history_owned_close"%policy,"pass":preview.full_history.bytes_owned==0 and preview.full_history.records.is_empty() and preview.solver.rd==null})
		preview.queue_free();for i in 4: await process_frame
	var ok:=true
	for row in rows: ok=ok and row.pass
	_write(ok);finished=true;print("BEACH_SAME_TICK_UNDO_COMPLETE pass=%s"%str(ok));quit(0 if ok else 1)

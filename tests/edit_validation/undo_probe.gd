extends "res://tests/edit_validation/water_transaction_probe.gd"

func _write(ok: bool, error := "") -> void:
	var f:=FileAccess.open(output.path_join("undo_probe.json"),FileAccess.WRITE)
	f.store_string(JSON.stringify({"pass":ok,"rows":rows,"error":error,"scope":"native same-tick undo coordinator, ledger generation collision; no checkpoint replay yet"},"\t"))

func _same(a: Dictionary, b: Dictionary) -> bool:
	for field in a:
		if field!="water_receipt" and a[field]!=b[field]: return false
	return true

func _collision_exact(state: Dictionary) -> bool:
	var sand: PackedFloat32Array=state.sand.to_float32_array()
	var rock: PackedFloat32Array=state.rock.to_float32_array()
	for chunk in lab.collision_proxy.shapes:
		var values: PackedFloat32Array=lab.collision_proxy.shapes[chunk].shape.map_data
		for z in 33:
			for x in 33:
				var index: int=mini((chunk/8)*32+z,255)*256+mini((chunk%8)*32+x,255)
				if values[z*33+x]!=sand[index]+rock[index]: return false
	return true

func _ray_error(state: Dictionary) -> float:
	var sand: PackedFloat32Array=state.sand.to_float32_array()
	var rock: PackedFloat32Array=state.rock.to_float32_array()
	var maximum:=0.0
	for z in range(126,131):
		for x in range(126,131):
			var p:=Vector3((x+0.5)*0.125-16,10,(z+0.5)*0.125-16)
			var hit: Dictionary=lab.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(p,p-Vector3(0,20,0)))
			if hit.is_empty(): return INF
			maximum=maxf(maximum,absf(hit.position.y-sand[z*256+x]-rock[z*256+x]))
	return maximum

func _run() -> void:
	lab=load("res://tests/edit_validation/edit_recovery_lab.tscn").instantiate();lab.local_dispatch=true
	root.add_child(lab)
	while not lab.ready_for_ticks and lab.last_error.is_empty(): await process_frame
	var states: Array[Dictionary]=[await _snapshot("initial")]
	var stocks: Array[float]=[lab.domain.tool_inventory_m3]
	var saved_receipt:=PackedByteArray()
	var initial_generation: int=lab.generation
	for i in 3:
		lab.water_policy=[0,1,3][i];lab.signed_speed_m_s=0.25
		var result: Dictionary=await lab.apply_gpu_command(_command(i+1,0.015))
		rows.append({"case":"apply_policy_%d" % lab.water_policy,"pass":result.get("status")==1,"receipt":result})
		states.append(await _snapshot("after_%d" % (i+1)))
		stocks.append(lab.domain.tool_inventory_m3)
		saved_receipt=lab.raw_receipt.duplicate()
	for i in range(2,-1,-1):
		var result: Dictionary=await lab.undo_latest()
		var state: Dictionary=await _snapshot("undo_%d" % (i+1))
		var exact: bool=_same(states[i],state)
		var collision: bool=_collision_exact(state)
		var ray_error:=_ray_error(state)
		var ok: bool=result.get("ok",false) and exact and collision and ray_error<=1e-5 and lab.domain.tool_inventory_m3==stocks[i] and lab.command_queue.applied_log.size()==i and lab.execution_prefix.size()==i and lab.generation==initial_generation+3-i and lab.command_queue.last_command_id==3
		rows.append({"case":"undo_%d" % (i+1),"pass":ok,"all_fields_exact":exact,"collision_exact":collision,"ray_error_m":ray_error,"outcome":result,"history_bytes":lab.gpu_history.bytes_owned})
	var ignored: int=lab.ignored_receipts
	lab._settle_receipt(saved_receipt,initial_generation)
	rows.append({"case":"old_receipt_after_undo","pass":lab.ignored_receipts==ignored+1 and lab.domain.tool_inventory_m3==stocks[0]})
	for i in 3:
		var redo_result: Dictionary=await lab.redo_latest()
		var redo_state: Dictionary=await _snapshot("redo_%d" % (i+1))
		rows.append({"case":"redo_%d" % (i+1),"pass":redo_result.get("status")==1 and _same(states[i+1],redo_state) and lab.domain.tool_inventory_m3==stocks[i+1],"receipt":redo_result})
	for i in 3: await lab.undo_latest()
	lab.water_policy=1
	var next_id: int=lab.command_queue.last_command_id+1
	var rejected: Dictionary=await lab.apply_gpu_command(_command(next_id,10.0))
	await process_frame
	var rejection_ok: bool=rejected.get("status")==2 and lab.gpu_history.records.is_empty() and lab.gpu_history.pending.is_empty() and lab.gpu_history.bytes_owned==0 and lab.execution_prefix.size()==1
	rows.append({"case":"rejected_candidate_discards_preimage","pass":rejection_ok,"receipt":rejected})
	next_id+=1
	var result: Dictionary=await lab.apply_gpu_command(_command(next_id,0.015))
	var undo: Dictionary=await lab.undo_latest()
	var state: Dictionary=await _snapshot("after_rejected_prefix_undo")
	rows.append({"case":"new_generation_rejected_prefix_then_undo","pass":result.get("status")==1 and undo.get("ok",false) and _same(states[0],state) and lab.execution_prefix.size()==1 and lab.command_queue.last_command_id==next_id,"undo":undo})
	var click:=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_RIGHT;click.pressed=true
	click.position=lab.get_viewport().get_final_transform()*lab.get_node("Camera").unproject_position(Vector3(0.0625,0.4,0.0625))
	var input_count: int=lab.input_results.size()
	Input.parse_input_event(click)
	var deadline:=Time.get_ticks_msec()+3000
	while (lab.input_results.size()==input_count or lab.input_running) and Time.get_ticks_msec()<deadline: await process_frame
	var ui_result: Dictionary=lab.input_results[-1].receipt if lab.input_results.size()>input_count else {}
	var ui_undo: Dictionary=await lab.undo_latest()
	var ui_state: Dictionary=await _snapshot("actual_input_undo")
	rows.append({"case":"actual_input_after_undo_uses_highwater_and_new_generation","pass":ui_result.get("status")==1 and ui_result.get("command_id")==next_id+1 and ui_undo.get("ok",false) and _same(states[0],ui_state),"receipt":ui_result,"undo":ui_undo})
	var release:=InputEventMouseButton.new();release.button_index=MOUSE_BUTTON_RIGHT;release.pressed=false;Input.parse_input_event(release)
	next_id=lab.command_queue.last_command_id+1
	var future:=_command(next_id,0.01);future.sim_tick=1
	var admitted: bool=lab.input_scheduler.submit(future)==&""
	var denied: Dictionary=await lab.undo_latest()
	rows.append({"case":"pending_queue_blocks_undo","pass":admitted and denied.get("error")=="pending_commands" and lab.input_scheduler.reserved_total()==0.01,"result":denied})
	lab.input_scheduler.cancel_pending("test_cleanup")
	var frozen: Dictionary=await _snapshot("paused_before")
	await lab.advance_ticks(1)
	for i in 20: await process_frame
	var paused_state: Dictionary=await _snapshot("paused_after")
	rows.append({"case":"pause_freezes_fields_and_tick","pass":_same(frozen,paused_state) and lab.completed_ticks==0})
	await lab.set_paused(false)
	var running_denied: Dictionary=await lab.undo_latest()
	await lab.advance_ticks(2)
	await lab.set_paused(true)
	var advanced: Dictionary=await _snapshot("advanced_before_cross_tick_undo")
	# No retained record: establish a new edit at tick2, then advance past it.
	var command:=_command(next_id+1,0.015)
	var advanced_edit: Dictionary=await lab.apply_gpu_command(command)
	await lab.set_paused(false);await lab.advance_ticks(1);await lab.set_paused(true)
	var before_denial: Dictionary=await _snapshot("cross_tick_before")
	var cross_denied: Dictionary=await lab.undo_latest()
	var after_denial: Dictionary=await _snapshot("cross_tick_after")
	rows.append({"case":"cross_tick_requires_replay_and_running_denied","pass":running_denied.get("error")=="requires_pause" and lab.completed_ticks==3 and advanced_edit.get("status")==1 and cross_denied.get("error")=="requires_checkpoint_replay" and _same(before_denial,after_denial),"result":cross_denied})
	await lab.seed_test_fields({},0.0)
	lab.water_policy=0
	var eps_before: Dictionary=await _snapshot("eps_before")
	var eps_command:=_command(1,0.0000005);eps_command.radius_m=0.02;eps_command.transform.position_m=Vector3(0.0625,0,0.0625)
	var eps_result: Dictionary=await lab.apply_gpu_command(eps_command)
	var borrowed_stock: float=lab.domain.tool_inventory_m3
	var eps_undo: Dictionary=await lab.undo_latest()
	var eps_after: Dictionary=await _snapshot("eps_undo")
	var eps_redo: Dictionary=await lab.redo_latest()
	rows.append({"case":"EPS_negative_stock_exact_undo_redo","pass":eps_result.get("status")==1 and borrowed_stock<0.0 and eps_undo.get("ok",false) and _same(eps_before,eps_after) and eps_redo.get("status")==1 and lab.domain.tool_inventory_m3==borrowed_stock,"stock_after_edit":borrowed_stock,"undo":eps_undo,"redo":eps_redo})
	var ok: bool=lab.last_error.is_empty()
	for row in rows: ok=ok and row.pass
	_write(ok,lab.last_error);await lab.shutdown();lab.queue_free();finished=true;print("UNDO_COMPLETE pass=%s rows=%d" % [str(ok),rows.size()]);quit(0 if ok else 1)

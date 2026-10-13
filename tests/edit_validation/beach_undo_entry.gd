extends "res://tests/edit_validation/beach_recovery_entry.gd"

const FullHistory=preload("res://scripts/simulation/edit_validation/beach_gpu_edit_history.gd")
var full_history=FullHistory.new()
var history_identity := {}
var undo_running := false
var redo_executing := false
var preserve_history_restore := false
var redo_records := []
var history_readbacks := 0
var history_raw := {}
var history_read_error := false
var undo_events := []
var recovery_key_results := []
var history_consumed_done := false
signal undo_history_read_submitted
var observe_undo_history_reads := false
var history_last_callback_us := -1
var history_release_us := -1

func execute_admitted_gpu_command(command: Dictionary, available_m3: float) -> Dictionary:
	history_identity={"generation":generation,"tick":completed_ticks,"command_id":command.command_id,"stock":shadow_domain.tool_inventory_m3,"prefix_size":gpu_prefix.size(),"command":command.duplicate(true),"policy":water_policy,"speed":signed_speed_m_s}
	var result: Dictionary=await super.execute_admitted_gpu_command(command,available_m3)
	if result.get("status")==1 and not redo_executing: redo_records.clear()
	return result

func _render_gpu_command(data: PackedByteArray, token: int) -> void:
	if closing or token!=generation: return
	if not full_history.capture(solver,history_identity): call_deferred("_fail","full beach history capture failed");return
	super._render_gpu_command(data,token)

func _settle_gpu_receipt(bytes: PackedByteArray, token: int) -> void:
	super._settle_gpu_receipt(bytes,token)
	if gpu_settled: RenderingServer.call_on_render_thread(_finish_history.bind(gpu_receipt.status==1))

func _finish_history(applied: bool) -> void: full_history.finish(solver,applied)

func _start_tick() -> void:
	if undo_running: return
	super._start_tick()

func apply_gpu_command(command: Dictionary) -> Dictionary:
	if undo_running and not redo_executing: return {"error":"undo_busy"}
	return await super.apply_gpu_command(command)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.ctrl_pressed and event.keycode in [KEY_Z,KEY_Y]:
		var result: Dictionary=await undo_latest() if event.keycode==KEY_Z else await redo_latest()
		recovery_key_results.append(result)
		while recovery_key_results.size()>64: recovery_key_results.pop_front()
		return
	super._unhandled_input(event)

func _capture_complete_data() -> Dictionary:
	gpu_save_running=true
	_start_checkpoint_capture()
	while checkpoint_capture_pending and last_error.is_empty(): await get_tree().process_frame
	while pending_beach_native_readbacks>0: await get_tree().process_frame
	gpu_save_running=false
	if not last_error.is_empty() or checkpoints.is_empty():
		checkpoint_capture_pending=false;checkpoint_capture.clear();pending_save_path=""
		ready_for_ticks=false;playing=false;input_scheduler.accepting=false
		return {}
	return checkpoints[-1].duplicate(true)

func _read_history(record: Dictionary) -> void:
	for field in FullHistory.FIELDS:
		for index in 2:
			history_readbacks+=1
			if solver.rd.texture_get_data_async(record.textures[field][index],0,_on_history_field.bind(field,index))!=OK:
				history_readbacks-=1;history_read_error=true
	if observe_undo_history_reads: call_deferred("_notify_history_reads")

func _notify_history_reads() -> void: undo_history_read_submitted.emit()

func _on_history_field(bytes: PackedByteArray, field: String, index: int) -> void: call_deferred("_history_field",bytes,field,index)
func _history_field(bytes: PackedByteArray, field: String, index: int) -> void:
	history_last_callback_us=Time.get_ticks_usec()
	history_raw[field+"_%d"%index]=bytes;history_readbacks-=1
	if bytes.size()!=GRID_SIZE*GRID_SIZE*4: history_read_error=true

func _target_before(record: Dictionary, current: Dictionary) -> Dictionary:
	var target: Dictionary=current.duplicate(true)
	var native: Dictionary=target.gpu_beach_native
	native.current_index=record.index
	for field in FullHistory.FIELDS:
		native.fields[field]=history_raw[field+"_%d"%record.index]
		native.spare[field]=history_raw[field+"_%d"%(1-record.index)]
	for field in ["sand","water","sediment"]: target.shadow[field]=native.fields[field].to_float32_array()
	for field in ["water","momentum_x","momentum_z"]: target.fields[field]=native.fields[field].to_float32_array()
	target.shadow.tool_inventory_m3=record.identity.stock
	target.gpu_beach_edit.ledger.tool_inventory_m3=record.identity.stock
	target.gpu_beach_edit.prefix=target.gpu_beach_edit.prefix.slice(0,record.identity.prefix_size)
	# Undo restores field bytes while preserving the frozen monotonic revision
	# contract. Explicit checkpoint restore remains a separate operation.
	target.revision=int(current.revision)+1
	return target

func _fingerprint(checkpoint: Dictionary) -> Dictionary:
	var hashes:= {}
	for group in ["fields","spare"]:
		for field in checkpoint.gpu_beach_native[group]: hashes[group+"_"+field]=_digest(checkpoint.gpu_beach_native[group][field])
	for field in ["foam_0","foam_1","bed_0","bed_1"]: hashes[field]=_digest(checkpoint.gpu_beach_native.foam[field])
	hashes.local_front=_digest(checkpoint.local_front_history.to_byte_array())
	return {"hashes":hashes,"index":checkpoint.gpu_beach_native.current_index,"foam_index":checkpoint.gpu_beach_native.foam.current_index,"ledger":checkpoint.gpu_beach_edit.ledger.duplicate(true)}

func _digest(bytes: PackedByteArray) -> String:
	var context:=HashingContext.new();context.start(HashingContext.HASH_SHA256);context.update(bytes);return context.finish().hex_encode()

func _undo_error() -> String:
	if undo_running or gpu_save_running or beach_restore_running or shutdown_requested or closing or busy or input_running or input_scheduler.pumping or not ready_for_ticks: return "backend_unavailable"
	if playing: return "requires_pause"
	if not command_queue.pending.is_empty() or input_scheduler.reserved_total()!=0.0: return "pending_commands"
	return ""

func undo_latest() -> Dictionary:
	var error:=_undo_error()
	if not error.is_empty(): return {"error":error}
	if full_history.records.is_empty(): return {"error":"no_gpu_history"}
	var record: Dictionary=full_history.records[-1]
	if record.identity.tick!=completed_ticks: return {"error":"requires_checkpoint_replay"}
	if gpu_prefix.is_empty() or gpu_prefix[-1].command.command_id!=record.identity.command_id: return {"error":"requires_checkpoint_replay"}
	var accepting: bool=input_scheduler.accepting
	undo_running=true;input_scheduler.accepting=false;gpu_brush=&""
	var current: Dictionary=await _capture_complete_data()
	if current.is_empty() or shutdown_requested: return _finish_undo("closed" if shutdown_requested else "capture_failed",accepting)
	history_raw.clear();history_read_error=false
	RenderingServer.call_on_render_thread(_read_history.bind(record))
	# The render request itself must run before its counter can be observed.
	await get_tree().process_frame
	while history_readbacks>0 or (history_raw.size()<10 and not history_read_error): await get_tree().process_frame
	if history_read_error or shutdown_requested: return _finish_undo("closed" if shutdown_requested else "history_readback_failed",accepting)
	var target:=_target_before(record,current)
	var archived: Dictionary={"identity":record.identity.duplicate(true),"target":_fingerprint(current),"baseline":_fingerprint(target),"tick":completed_ticks}
	preserve_history_restore=true
	var restored: StringName=await restore_gpu_checkpoint_data(target)
	preserve_history_restore=false
	if restored.is_empty():
		history_consumed_done=false
		RenderingServer.call_on_render_thread(_consume_history)
		while not history_consumed_done: await get_tree().process_frame
		archived.generation=generation;redo_records.append(archived)
		while redo_records.size()>32: redo_records.pop_front()
	undo_events.append({"kind":"undo","tick":completed_ticks,"generation":generation,"error":String(restored)})
	return _finish_undo(String(restored),accepting)

func _consume_history() -> void:
	full_history.consume_latest(solver)
	call_deferred("_history_consumed")

func _history_consumed() -> void: history_consumed_done=true

func redo_latest() -> Dictionary:
	var error:=_undo_error()
	if not error.is_empty(): return {"error":error}
	if redo_records.is_empty(): return {"error":"no_redo"}
	var record: Dictionary=redo_records[-1]
	if record.tick!=completed_ticks: return {"error":"requires_checkpoint_replay"}
	var accepting: bool=input_scheduler.accepting
	undo_running=true;input_scheduler.accepting=false;redo_executing=true
	var baseline: Dictionary=await _capture_complete_data()
	if baseline.is_empty() or shutdown_requested:
		redo_executing=false;return _finish_undo("closed" if shutdown_requested else "capture_failed",accepting)
	if _fingerprint(baseline)!=record.baseline:
		redo_executing=false;return _finish_undo("redo_current_mismatch",accepting)
	var command: Dictionary=record.identity.command.duplicate(true)
	command.generation=generation;command.sim_tick=completed_ticks;command.command_id=command_queue.last_command_id+1
	var previous_policy:=water_policy;var previous_speed:=signed_speed_m_s
	water_policy=record.identity.policy;signed_speed_m_s=record.identity.speed
	var receipt: Dictionary=await apply_gpu_command(command)
	water_policy=previous_policy;signed_speed_m_s=previous_speed;redo_executing=false
	if shutdown_requested: return _finish_undo("closed_after_redo_apply",accepting)
	var current: Dictionary=await _capture_complete_data()
	var exact: bool=receipt.get("status")==1 and not current.is_empty() and _fingerprint(current)==record.target
	if exact: redo_records.pop_back()
	else:
		baseline.highwater_id=command_queue.last_command_id
		baseline.revision=int(current.get("revision",solver.state_revision))+1
		preserve_history_restore=true
		var rollback: StringName=await restore_gpu_checkpoint_data(baseline)
		preserve_history_restore=false
		if rollback.is_empty() and receipt.get("status")==1:
			history_consumed_done=false;RenderingServer.call_on_render_thread(_consume_history)
			while not history_consumed_done: await get_tree().process_frame
		elif not rollback.is_empty(): _fail("full beach redo rollback failed")
	undo_events.append({"kind":"redo","tick":completed_ticks,"generation":generation,"native_target_exact":exact})
	return _finish_undo("" if exact else "redo_target_mismatch",accepting)

func _finish_undo(error: String, accepting: bool) -> Dictionary:
	undo_running=false
	input_scheduler.accepting=accepting and ready_for_ticks and not shutdown_requested and last_error.is_empty()
	return {"ok":error.is_empty(),"error":error,"generation":generation,"tick":completed_ticks}

func _render_beach_restore_commit() -> void:
	var previous_instance: int=solver.get_instance_id()
	if not preserve_history_restore: full_history.release(solver);redo_records.clear()
	super._render_beach_restore_commit()
	if preserve_history_restore and not full_history.rebind_owner(previous_instance,solver,generation): call_deferred("_fail","full beach history owner transfer failed")

func _render_release() -> void:
	if solver!=null and history_readbacks==0 and not solver.receipt_pending and not collision_proxy.staging_texture.is_valid():
		full_history.release(solver);history_release_us=Time.get_ticks_usec()
	super._render_release()

func shutdown() -> void:
	shutdown_requested=true;input_scheduler.accepting=false
	while undo_running: await get_tree().process_frame
	await super.shutdown()

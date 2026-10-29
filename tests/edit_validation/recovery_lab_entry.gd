extends "res://tests/edit_validation/interaction_lab_entry.gd"

const History=preload("res://scripts/simulation/edit_validation/gpu_edit_history.gd")
var gpu_history
var execution_prefix := []
var history_metadata := {}
var paused := true
var recovery_running := false
var recovery_done := false
var recovery_ok := false
var undo_events := []
var redo_commands := []
var redo_running := false
var history_enabled := true

func _render_setup(token: int) -> void:
	if gpu_history!=null: gpu_history.release();gpu_history=null
	super._render_setup(token)
	if solver!=null and solver.rd!=null and token==generation and not closed: gpu_history=History.new(solver)

func execute_admitted_gpu_command(command: Dictionary, available_m3: float) -> Dictionary:
	history_metadata={"stock":domain.tool_inventory_m3,"prefix_size":execution_prefix.size(),"applied_size":command_queue.applied_log.size(),"command":command.duplicate(true),"policy":water_policy,"speed":signed_speed_m_s,"execution_tick":completed_ticks}
	var policy:=water_policy
	var speed:=signed_speed_m_s
	var result: Dictionary=await super.execute_admitted_gpu_command(command,available_m3)
	if result.get("status",0) in [1,2]:
		if not redo_running: redo_commands.clear()
		execution_prefix.append({"command":command.duplicate(true),"policy":policy,"speed":speed,"result":result.duplicate(true),"available_m3":available_m3,"stock_before":history_metadata.stock,"execution_tick":history_metadata.execution_tick})
	return result

func _render_command(data: PackedByteArray, token: int) -> void:
	if closed or token!=generation: return
	if not history_enabled:
		super._render_command(data,token);return
	if gpu_history==null or not gpu_history.capture(data.decode_s64(8),completed_ticks):
		call_deferred("_fail","GPU history capture failed");return
	gpu_history.pending.cpu=history_metadata.duplicate(true)
	super._render_command(data,token)

func _settle_receipt(data: PackedByteArray, token: int) -> void:
	var was_settled:=transaction_settled
	super._settle_receipt(data,token)
	if history_enabled and not was_settled and transaction_settled and token==generation and receipt.get("status")==2:
		RenderingServer.call_on_render_thread(_discard_rejected_history.bind(token))

func _discard_rejected_history(token: int) -> void:
	if token==generation and gpu_history!=null: gpu_history.finish(false)

func _render_publish_command(token: int) -> void:
	if history_enabled and token==generation and not closed and transaction_settled and receipt.get("status")==1:
		if gpu_history==null or gpu_history.pending.is_empty():
			call_deferred("_fail","missing GPU history before publication");return
		gpu_history.pending.cpu.receipt=receipt.duplicate(true)
		if not gpu_history.finish(true):
			call_deferred("_fail","GPU history retention failed");return
	super._render_publish_command(token)

func set_paused(value: bool) -> void:
	paused=value
	if value:
		while (busy or input_running) and not closed: await get_tree().process_frame

func advance_ticks(count: int) -> void:
	if paused or recovery_running or input_running: return
	await super.advance_ticks(count)

func undo_latest() -> Dictionary:
	if not paused: return {"error":"requires_pause"}
	if busy or input_running or recovery_running or closed or not ready_for_ticks: return {"error":"backend_unavailable"}
	if not command_queue.pending.is_empty() or input_scheduler.reserved_total()!=0.0: return {"error":"pending_commands"}
	if gpu_history==null or gpu_history.records.is_empty(): return {"error":"no_gpu_history"}
	var record: Dictionary=gpu_history.records[-1]
	if record.tick!=completed_ticks: return {"error":"requires_checkpoint_replay"}
	if record.generation!=generation or record.cpu.applied_size!=command_queue.applied_log.size()-1 or command_queue.applied_log[-1].command_id!=record.command_id:
		return {"error":"history_prefix_mismatch"}
	recovery_running=true;busy=true;ready_for_ticks=false;active_brush=&""
	input_scheduler.accepting=false
	while true:
		var collision_complete: bool=not collision_proxy.staging_texture.is_valid() and collision_proxy.pending_revisions.is_empty()
		for chunk in collision_needed: collision_complete=collision_complete and int(collision_proxy.applied_revisions.get(chunk,-1))>=int(collision_needed[chunk])
		if collision_complete: break
		if closed: busy=false;recovery_running=false;return {"error":"closed"}
		await get_tree().process_frame
	var old_generation:=generation
	var stock: float=record.cpu.stock
	var chunks:=_chunks_for_receipt(record.cpu.receipt)
	recovery_done=false
	RenderingServer.call_on_render_thread(_restore_preimage.bind(old_generation))
	while not recovery_done and not closed: await get_tree().process_frame
	if closed:
		busy=false;recovery_running=false;return {"error":"closed","cancelled":true}
	if not recovery_ok:
		_fail("GPU preimage restore failed");busy=false;recovery_running=false
		return {"error":"restore_failed"}
	# GPU copies succeeded. Settle the exact previous double stock before making
	# restored textures visible, and keep the ID high-water mark monotonic.
	domain.tool_inventory_m3=stock
	command_queue.applied_log.resize(record.cpu.applied_size)
	execution_prefix.resize(record.cpu.prefix_size)
	generation+=1;domain.generation=generation
	shadow_sand_revision=-1
	input_scheduler.generation=generation
	collision_needed.clear()
	var revision: int=solver.state_revision+1
	for chunk in chunks: collision_needed[chunk]=revision
	recovery_done=false
	RenderingServer.call_on_render_thread(_publish_undo.bind(old_generation,revision,chunks))
	while not recovery_done and not closed: await get_tree().process_frame
	if not closed and not recovery_ok:
		_fail("GPU undo publication or collision request failed")
		busy=false;recovery_running=false;return {"error":"publication_failed"}
	while not closed:
		var complete:=true
		for chunk in collision_needed: complete=complete and int(collision_proxy.applied_revisions.get(chunk,-1))>=int(collision_needed[chunk])
		if complete: break
		await get_tree().process_frame
	await get_tree().physics_frame;await get_tree().physics_frame
	var outcome: Dictionary={"command_id":record.command_id,"generation":generation,"revision":revision,"stock":stock,"tick":completed_ticks,"ok":recovery_ok and not closed and last_error.is_empty()}
	undo_events.append(outcome.duplicate(true))
	if outcome.ok:
		redo_commands.append({"command":record.cpu.command.duplicate(true),"policy":record.cpu.policy,"speed":record.cpu.speed,"tick":record.tick})
	busy=false;recovery_running=false;ready_for_ticks=outcome.ok
	input_scheduler.accepting=ready_for_ticks
	return outcome

func redo_latest() -> Dictionary:
	if not paused: return {"error":"requires_pause"}
	if busy or input_running or recovery_running or closed or not ready_for_ticks: return {"error":"backend_unavailable"}
	if not command_queue.pending.is_empty() or input_scheduler.reserved_total()!=0.0: return {"error":"pending_commands"}
	if redo_commands.is_empty(): return {"error":"no_redo"}
	var item: Dictionary=redo_commands[-1]
	if item.tick!=completed_ticks: return {"error":"requires_checkpoint_replay"}
	var command: Dictionary=item.command.duplicate(true)
	# Redo is a new acknowledged transaction, with a fresh native int64 identity.
	# The geometry, seed, amount, policy and speed remain exactly the same.
	command.command_id=command_queue.last_command_id+1
	command.generation=generation;command.sim_tick=completed_ticks
	water_policy=item.policy;signed_speed_m_s=item.speed
	redo_running=true
	var result: Dictionary=await apply_gpu_command(command)
	redo_running=false
	if result.get("status")==1: redo_commands.pop_back()
	return result

func _restore_preimage(token: int) -> void:
	var ok: bool=not closed and token==generation and gpu_history.restore_latest(completed_ticks)
	call_deferred("_recovery_complete",ok)

func _publish_undo(old_generation: int, revision: int, chunks: PackedInt32Array) -> void:
	if closed or generation!=old_generation+1:
		call_deferred("_recovery_complete",false);return
	solver.owner_generation=generation;solver.state_revision=revision
	collision_proxy.generation=generation
	gpu_history.discard_latest()
	# Earlier preimages belong to the same surviving prefix and immutable bed
	# inputs. Rebase their identities after the atomic generation transition.
	for record in gpu_history.records: record.generation=generation
	_publish_render()
	var ok: bool=collision_proxy.request_chunks_render(chunks,revision,generation)
	call_deferred("_recovery_complete",ok)

func _recovery_complete(ok: bool) -> void: recovery_ok=ok;recovery_done=true

func reset_domain() -> void:
	if recovery_running: return
	await super.reset_domain()
	if ready_for_ticks: execution_prefix.clear();undo_events.clear();redo_commands.clear();paused=true

func _render_release() -> void:
	if solver!=null and not solver.receipt_pending and not collision_proxy.staging_texture.is_valid() and gpu_history!=null:
		gpu_history.release();gpu_history=null
	super._render_release()

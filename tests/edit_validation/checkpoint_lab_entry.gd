extends "res://tests/edit_validation/recovery_lab_entry.gd"
signal restore_candidate_ready
signal restore_published
signal replay_worker_created(worker)

const CheckpointCodec=preload("res://scripts/simulation/edit_validation/gpu_checkpoint_codec.gd")
const RedoCodec=preload("res://scripts/simulation/edit_validation/gpu_redo_codec.gd")
var checkpoint_running := false
var legacy_prefix_present := false
var checkpoint_events := []
var restore_candidate
var restore_build_pending := false
var restore_candidate_done := false
var inject_restore_failure_once := false
var discarded_candidate_count := 0
var observe_restore_boundaries := false
var restore_phase := "idle"
var replay_anchor := {}
var replay_events := []
var replay_mode := false
var replay_worker
var observe_replay_boundaries := false
var replay_disposals := []

func _configuration_error(checkpoint: Dictionary) -> StringName:
	var config: Variant=checkpoint.get("gpu_edit_configuration")
	if not config is Dictionary or config.get("version")!=1 or config.get("fixture")!="edit_checkpoint_lab_v1": return &"invalid_checkpoint_configuration"
	var current:=checkpoint_configuration()
	for key in ["engine","sources","spirv","sim_hz","profile_path","profile_sha256","boundary","erosion","visual_history"]:
		if config.get(key)!=current[key]: return &"incompatible_checkpoint_configuration"
	if typeof(config.get("local_dispatch"))!=TYPE_BOOL or typeof(config.get("fast_full_wet"))!=TYPE_BOOL or config.get("water_policy") not in [0,1,2,3] or typeof(config.get("signed_speed_m_s")) not in [TYPE_FLOAT,TYPE_INT] or not is_finite(float(config.signed_speed_m_s)) or absf(float(config.signed_speed_m_s))>1.0: return &"invalid_checkpoint_configuration"
	if typeof(config.get("visual_time_s")) not in [TYPE_FLOAT,TYPE_INT] or config.visual_time_s!=float(checkpoint.tick)/profile.sim_hz or not config.get("effective_profile") is Dictionary: return &"invalid_checkpoint_configuration"
	if checkpoint.shadow.get("domain_id")!=domain.domain_id: return &"out_of_domain"
	if checkpoint.has("gpu_edit_redo"):
		var redo:=RedoCodec.unpack(checkpoint.gpu_edit_redo,checkpoint.gpu_edit_sidecar,domain.domain_id)
		if not redo.error.is_empty(): return redo.error
	if checkpoint.has("gpu_edit_replay_anchor"):
		var anchor: Variant=checkpoint.gpu_edit_replay_anchor
		if not anchor is Dictionary or anchor.has("gpu_edit_replay_anchor") or not anchor.get("gpu_edit_sidecar") is Dictionary: return &"invalid_replay_anchor"
		var anchor_error: StringName=CheckpointCodec.validate(anchor.gpu_edit_sidecar)
		if anchor_error.is_empty(): anchor_error=CheckpointCodec.validate_projection(anchor)
		if anchor_error.is_empty(): anchor_error=_configuration_error(anchor)
		if not anchor_error.is_empty(): return anchor_error
		if anchor.tick>checkpoint.tick or anchor.gpu_edit_sidecar.prefix!=checkpoint.gpu_edit_sidecar.prefix.slice(0,anchor.gpu_edit_sidecar.prefix.size()): return &"invalid_replay_anchor_prefix"
	return &""

func _render_build_candidate(checkpoint: Dictionary, candidate_domain, token: int) -> void:
	if closed or token!=generation:
		restore_build_pending=false;call_deferred("_candidate_ready");return
	var candidate=_create_solver()
	var config: Dictionary=checkpoint.gpu_edit_configuration
	candidate.local_dispatch=config.local_dispatch;candidate.fast_full_wet=config.fast_full_wet
	var ok: bool=candidate.initialize(RenderingServer.get_rendering_device(),candidate_domain,spirvs[0],spirvs[1],spirvs[2],spirvs[3],spirvs[4],spirvs[5],spirvs[6],spirvs[7],checkpoint.fields.momentum_x,checkpoint.fields.momentum_z)
	if ok: ok=candidate.restore_native_fields(checkpoint.gpu_edit_sidecar.raw_fields,checkpoint.revision)
	if inject_restore_failure_once: inject_restore_failure_once=false;ok=false
	if ok: restore_candidate=candidate
	else: candidate.release();discarded_candidate_count+=1
	restore_build_pending=false
	call_deferred("_candidate_ready")

func _candidate_ready() -> void:
	if observe_restore_boundaries: restore_candidate_ready.emit()
	restore_candidate_done=true

func _notify_restore_published() -> void: restore_published.emit()

func _closed_restore_error() -> StringName:
	if restore_phase=="published": return &"closed_after_restore_publish"
	if restore_phase=="metadata_committed": return &"closed_after_restore_metadata"
	return &"closed"

func _render_commit_candidate(token: int) -> void:
	if closed or token!=generation or restore_candidate==null:
		call_deferred("_recovery_complete",false);return
	var old_solver=solver
	if gpu_history!=null: gpu_history.release()
	solver=restore_candidate;restore_candidate=null
	gpu_history=History.new(solver)
	collision_proxy.solver=solver;collision_proxy.generation=token
	_publish_render()
	old_solver.release()
	restore_phase="published"
	if observe_restore_boundaries: call_deferred("_notify_restore_published")
	call_deferred("_recovery_complete",true)

func restore_checkpoint(path: String) -> StringName:
	if checkpoint_running or recovery_running or busy or input_running or closed or not ready_for_ticks: return &"backend_unavailable"
	if not paused: return &"requires_pause"
	if not command_queue.pending.is_empty() or input_scheduler.reserved_total()!=0.0: return &"pending_commands"
	var loaded:=CheckpointCodec.load(path)
	if not loaded.error.is_empty(): return loaded.error
	return await restore_checkpoint_data(loaded.checkpoint)

func restore_checkpoint_data(checkpoint: Dictionary) -> StringName:
	if checkpoint_running or recovery_running or busy or input_running or closed or not ready_for_ticks: return &"backend_unavailable"
	if not paused: return &"requires_pause"
	if not command_queue.pending.is_empty() or input_scheduler.reserved_total()!=0.0: return &"pending_commands"
	if not checkpoint.get("gpu_edit_sidecar") is Dictionary: return &"missing_candidate_sidecar"
	var validation: StringName=CheckpointCodec.validate(checkpoint.gpu_edit_sidecar)
	if validation.is_empty(): validation=CheckpointCodec.validate_projection(checkpoint)
	if not validation.is_empty(): return validation
	var loaded: Dictionary={"checkpoint":checkpoint,"sidecar":checkpoint.gpu_edit_sidecar}
	var error:=_configuration_error(loaded.checkpoint)
	if not error.is_empty(): return error
	var previous_accepting: bool=input_scheduler.accepting
	restore_phase="building"
	checkpoint_running=true;input_scheduler.accepting=false;ready_for_ticks=false;busy=true;active_brush=&""
	while collision_proxy.staging_texture.is_valid() or not collision_proxy.pending_revisions.is_empty() or pending_state_readbacks>0 or pending_cfl_readbacks>0:
		if closed: busy=false;return _finish_checkpoint(&"closed",true,false)
		await get_tree().process_frame
	var candidate_domain=Domain.new(256,0.125)
	if not candidate_domain.restore(loaded.checkpoint.shadow):
		busy=false;ready_for_ticks=true;return _finish_checkpoint(&"invalid_checkpoint_shadow",true,previous_accepting)
	var next_generation: int=maxi(generation,loaded.sidecar.generation)+1
	candidate_domain.generation=next_generation
	restore_candidate_done=false;restore_build_pending=true
	RenderingServer.call_on_render_thread(_render_build_candidate.bind(loaded.checkpoint,candidate_domain,generation))
	while not restore_candidate_done and not closed: await get_tree().process_frame
	if closed:
		busy=false;return _finish_checkpoint(_closed_restore_error(),true,false)
	if restore_candidate==null:
		busy=false;ready_for_ticks=true;return _finish_checkpoint(&"candidate_failed",true,previous_accepting)
	# All candidate allocations and copies were accepted in isolation. Commit
	# CPU metadata before switching publication; no new input is accepted yet.
	generation=next_generation;domain=candidate_domain;completed_ticks=loaded.sidecar.tick
	restore_phase="metadata_committed"
	command_queue=Queue.new(domain);command_queue.last_command_id=loaded.sidecar.highwater_id
	execution_prefix=loaded.sidecar.prefix.duplicate(true)
	for item in execution_prefix:
		if item.result.status==1: command_queue.applied_log.append(item.command.duplicate(true))
	input_scheduler=Scheduler.new(self);input_scheduler.accepting=false
	input_serial=command_queue.last_command_id;reported_terminal=0
	input_events.clear();input_results.clear();input_rejections.clear();collision_needed.clear()
	redo_commands.clear();undo_events.clear();shadow_sand_revision=-1;legacy_prefix_present=false
	if loaded.checkpoint.has("gpu_edit_redo"): redo_commands=RedoCodec.unpack(loaded.checkpoint.gpu_edit_redo,loaded.sidecar,domain.domain_id).records
	replay_anchor=loaded.checkpoint.get("gpu_edit_replay_anchor",loaded.checkpoint).duplicate(true)
	var config: Dictionary=loaded.checkpoint.gpu_edit_configuration
	local_dispatch=config.local_dispatch;fast_full_wet=config.fast_full_wet
	water_policy=config.water_policy;signed_speed_m_s=config.signed_speed_m_s
	effective_profile=config.effective_profile.duplicate(true);effective_profile.generation=generation
	recovery_done=false
	RenderingServer.call_on_render_thread(_render_commit_candidate.bind(generation))
	while not recovery_done and not closed: await get_tree().process_frame
	if closed: busy=false;return _finish_checkpoint(_closed_restore_error(),true,false)
	var chunks:=PackedInt32Array()
	for chunk in 64: chunks.append(chunk)
	# Revision ordering is scoped to generation. A saved revision may be lower
	# than the discarded branch, so no old per-chunk tags may suppress restore.
	collision_proxy.applied_revisions.clear();collision_proxy.applied_usec.clear();collision_proxy.applied_stage_usec.clear()
	var collision_ok: bool=recovery_ok and collision_proxy.apply_shadow_chunks(chunks,solver.state_revision,generation,domain.rock,domain.sand)
	if not collision_ok:
		busy=false;_fail("checkpoint collision restoration failed")
		return _finish_checkpoint(&"collision_restore_failed",true,false)
	await get_tree().physics_frame;await get_tree().physics_frame
	busy=false;ready_for_ticks=not closed and last_error.is_empty()
	return _finish_checkpoint(&"" if ready_for_ticks else _closed_restore_error(),true,ready_for_ticks)

func _render_release() -> void:
	if restore_build_pending:
		release_wait_count+=1;call_deferred("_retry_release");return
	if restore_candidate!=null:
		restore_candidate.release();restore_candidate=null;discarded_candidate_count+=1
	super._render_release()

func apply_gpu_command(command: Dictionary) -> Dictionary:
	if checkpoint_running: return {"error":"checkpoint_busy"}
	return await super.apply_gpu_command(command)

func apply_legacy_command(command: Dictionary) -> Dictionary:
	if checkpoint_running: return {"error":"checkpoint_busy"}
	if busy or input_running or closed or not ready_for_ticks or not command_queue.pending.is_empty(): return {"error":"backend_unavailable"}
	if command.get("kind") not in [&"smooth",&"compact"] or typeof(command.get("sim_tick"))!=TYPE_INT or command.sim_tick!=completed_ticks: return {"error":"invalid_command"}
	var finite: Dictionary=command.duplicate(false)
	if not finite.has("amount_m3"): finite.amount_m3=0.0
	if not Protocol.finite_command(finite): return {"error":"invalid_command"}
	var accepting: bool=input_scheduler.accepting
	checkpoint_running=true;input_scheduler.accepting=false
	var stock: float=domain.tool_inventory_m3
	# CPU fallback consumes the current R32/R16 completion, including a fresh
	# setup seed whose half values may differ from its original CPU float32.
	await synchronize_cpu_shadow()
	var result: Dictionary={"error":"closed"} if closed else await super.apply_legacy_command(command)
	if not result.has("error") and result.results.size()==1:
		var legacy: Dictionary=result.results[0]
		var envelope: Dictionary={"command_id":command.command_id,"generation":generation,"status":1 if legacy.status==&"applied" else 2,"applied_tick":completed_ticks,"legacy_result":legacy.duplicate(true)}
		execution_prefix.append({"backend":"legacy_cpu","command":command.duplicate(true),"result":envelope,"policy":0,"speed":0.0,"available_m3":stock,"stock_before":stock,"execution_tick":completed_ticks})
		if not redo_running: redo_commands.clear()
		legacy_prefix_present=false
		if legacy.status==&"applied" and not closed:
			var neighbors:=PackedInt32Array()
			for chunk in legacy.dirty_chunks:
				for dz in range(-1,2):
					for dx in range(-1,2):
						var x: int=chunk%8+dx;var z: int=chunk/8+dz
						var id:=z*8+x
						if x>=0 and x<8 and z>=0 and z<8 and id not in neighbors: neighbors.append(id)
			for chunk in neighbors: collision_needed[chunk]=solver.state_revision
			if not collision_proxy.apply_shadow_chunks(neighbors,solver.state_revision,generation,domain.rock,domain.sand): _fail("legacy neighbor collision update failed")
			await get_tree().physics_frame;await get_tree().physics_frame
	checkpoint_running=false
	if not closed and last_error.is_empty(): input_scheduler.accepting=accepting
	return result

func advance_ticks(count: int) -> void:
	if checkpoint_running: return
	await super.advance_ticks(count)

func set_paused(value: bool) -> void:
	if checkpoint_running and not value: return
	await super.set_paused(value)

func undo_latest() -> Dictionary:
	if checkpoint_running: return {"error":"checkpoint_busy"}
	var last:=execution_prefix.size()-1
	while last>=0 and execution_prefix[last].result.status!=1: last-=1
	if last>=0 and execution_prefix[last].get("backend","gpu")=="legacy_cpu": return await _undo_by_replay()
	var archived: Dictionary={}
	var accepting_before: bool=input_scheduler.accepting
	# Explicit paused undo, outside the edit hot path. Retain only hashes and
	# native execution inputs, so a later time advance can verify this branch.
	if paused and not busy and not input_running and not recovery_running and not closed and ready_for_ticks and command_queue.pending.is_empty() and input_scheduler.reserved_total()==0.0 and gpu_history!=null and not gpu_history.records.is_empty() and gpu_history.records[-1].tick==completed_ticks:
		checkpoint_running=true;input_scheduler.accepting=false
		var raw: Dictionary=await snapshot_state()
		if closed or raw.size()!=STATE_FIELDS.size():
			_finish_checkpoint(&"closed" if closed else &"capture_failed",true,accepting_before)
			return {"error":"closed" if closed else "capture_failed"}
		var hashes: Dictionary={}
		for field in raw: hashes[field]=RedoCodec.digest(raw[field])
		archived={"tick":completed_ticks,"prefix":execution_prefix.duplicate(true),"ledger":_ledger_values(),"field_sha256":hashes}
	var result: Dictionary=await super.undo_latest()
	if not archived.is_empty():
		if result.get("ok",false):
			redo_commands[-1].replay_target=archived
			redo_commands[-1].same_tick_transaction=true
			while redo_commands.size()>32: redo_commands.pop_front()
		_finish_checkpoint(&"" if result.get("ok",false) else &"undo_failed",true,accepting_before)
	if result.get("error") in ["requires_checkpoint_replay","no_gpu_history"]: return await _undo_by_replay()
	return result

func _replay_native_item(item: Dictionary) -> Dictionary:
	if not replay_mode or busy or closed or not command_queue.pending.is_empty(): return {"error":"not_isolated_replay"}
	if not item.has("available_m3") or not item.has("execution_tick"): return {"error":"missing_replay_input"}
	if completed_ticks!=item.execution_tick or domain.tool_inventory_m3!=item.stock_before: return {"error":"replay_input_mismatch"}
	var command: Dictionary=item.command.duplicate(true)
	if command.domain_id!=domain.domain_id: return {"error":"out_of_domain"}
	command.generation=generation
	if item.get("backend","gpu")=="legacy_cpu":
		# The original CPU path remains the implementation under replay.
		var result: Dictionary=await apply_legacy_command(command)
		if result.has("error") or result.results.size()!=1: return {"error":"legacy_replay_failed"}
		if result.results[0]!=item.result.legacy_result: return {"error":"legacy_replay_result_mismatch"}
		return {"error":&""}
	water_policy=item.policy;signed_speed_m_s=item.speed
	# This is replay of an already validated acceptance, not public admission.
	# Execution order can contain older IDs and requests from earlier ticks.
	command_queue.pending.append(command)
	command_queue.last_command_id=maxi(command_queue.last_command_id,command.command_id)
	var result: Dictionary=await execute_admitted_gpu_command(command,item.available_m3)
	for key in ["status","actual_sand_m3","nominal_sand_m3","edited_cells","clamp_count","capacity_status","displaced_water_m3","retained_water_m3","impulse_x_m4_s","impulse_z_m4_s","invalid_flags","error_code","dirty_mask","dirty_rect"]:
		if result.get(key)!=item.result.get(key): return {"error":"replay_receipt_mismatch","field":key,"actual":result,"expected":item.result}
	return {"error":&""}

func _run_replay(items: Array, target_tick: int, verify_target: Dictionary={}) -> Dictionary:
	var worker=load("res://tests/edit_validation/edit_checkpoint_lab.tscn").instantiate()
	worker.history_enabled=false;worker.replay_mode=true;worker.visible=false
	worker.set_process_unhandled_input(false)
	worker.get_node("CollisionProxy/GpuTerrainCollision").collision_layer=0
	worker.get_node("Camera").current=false
	worker.get_node("EvidenceOverlay").visible=false
	replay_worker=worker;get_tree().root.add_child(worker)
	if observe_replay_boundaries: replay_worker_created.emit(worker)
	while not closed and is_instance_valid(worker) and not worker.ready_for_ticks and worker.last_error.is_empty(): await get_tree().process_frame
	if closed or not is_instance_valid(worker) or not worker.last_error.is_empty(): return {"error":"replay_setup_failed"}
	var error: StringName=await worker.restore_checkpoint_data(replay_anchor)
	if not error.is_empty(): return {"error":error}
	for item in items.slice(replay_anchor.gpu_edit_sidecar.prefix.size()):
		if closed: return {"error":"closed"}
		if not item.has("execution_tick") or item.execution_tick<worker.completed_ticks: return {"error":"missing_or_reordered_replay_input"}
		await worker.set_paused(false);await worker.advance_ticks(item.execution_tick-worker.completed_ticks);await worker.set_paused(true)
		if closed or not is_instance_valid(worker) or worker.closed: return {"error":"closed"}
		var replayed: Dictionary=await worker._replay_native_item(item)
		if not replayed.error.is_empty(): return replayed
	var archived_exact:=true
	if not verify_target.is_empty():
		if worker.completed_ticks>verify_target.tick or verify_target.tick>target_tick: return {"error":"invalid_redo_verify_boundary"}
		await worker.set_paused(false);await worker.advance_ticks(verify_target.tick-worker.completed_ticks);await worker.set_paused(true)
		if closed or not is_instance_valid(worker) or worker.closed: return {"error":"closed"}
		var archived_raw: Dictionary=await worker.snapshot_state()
		archived_exact=worker._ledger_values()==verify_target.ledger
		for field in archived_raw: archived_exact=archived_exact and RedoCodec.digest(archived_raw[field])==verify_target.field_sha256[field]
		if not archived_exact: return {"error":"replay_target_mismatch"}
	await worker.set_paused(false);await worker.advance_ticks(target_tick-worker.completed_ticks);await worker.set_paused(true)
	if closed or not is_instance_valid(worker) or worker.closed or not worker.last_error.is_empty(): return {"error":"replay_failed"}
	var raw: Dictionary=await worker.snapshot_state()
	var built:=CheckpointCodec.build(raw,worker._ledger_values(),worker.execution_prefix,worker.completed_ticks,worker.generation,worker.solver.state_revision,command_queue.last_command_id)
	if not built.error.is_empty(): return built
	built.checkpoint.gpu_edit_configuration=worker.checkpoint_configuration()
	built.checkpoint.gpu_edit_replay_anchor=replay_anchor.duplicate(true)
	return {"error":&"","checkpoint":built.checkpoint,"history_bytes":worker.gpu_history.bytes_owned,"archived_target_exact":archived_exact}

func _dispose_replay_worker() -> void:
	if replay_worker!=null:
		var worker=replay_worker;replay_worker=null
		if not worker.closed: await worker.shutdown()
		else:
			while not worker.render_done: await get_tree().process_frame
		replay_disposals.append({"solver_released":worker.solver==null,"pending_state":worker.pending_state_readbacks,"pending_cfl":worker.pending_cfl_readbacks,"state_callback_us":worker.state_readback_callback_us,"cfl_callback_us":worker.cfl_readback_callback_us,"release_us":worker.release_record_us})
		worker.queue_free()

func _undo_by_replay() -> Dictionary:
	if not paused: return {"error":"requires_pause"}
	if busy or input_running or closed or not ready_for_ticks: return {"error":"backend_unavailable"}
	if not command_queue.pending.is_empty() or input_scheduler.reserved_total()!=0.0: return {"error":"pending_commands"}
	var index:=execution_prefix.size()-1
	while index>=0 and execution_prefix[index].result.status!=1: index-=1
	if index<0: return {"error":"no_undo"}
	if replay_anchor.is_empty() or replay_anchor.gpu_edit_sidecar.prefix.size()>index: return {"error":"no_checkpoint_before_command"}
	var previous_accepting: bool=input_scheduler.accepting
	checkpoint_running=true;input_scheduler.accepting=false
	var selection: Dictionary={"policy":water_policy,"speed":signed_speed_m_s}
	var current_raw: Dictionary=await snapshot_state()
	ready_for_ticks=false;busy=true
	var current_ledger:=_ledger_values()
	var original: Dictionary=await _run_replay(execution_prefix,completed_ticks)
	await _dispose_replay_worker()
	var exact: bool=original.error.is_empty()
	if exact:
		for field in current_raw: exact=exact and current_raw[field]==original.checkpoint.gpu_edit_sidecar.raw_fields[field]
		exact=exact and current_ledger==original.checkpoint.gpu_edit_sidecar.ledger
	if not exact or closed:
		busy=false;ready_for_ticks=not closed
		_finish_checkpoint(&"closed" if closed else &"replay_current_mismatch",true,previous_accepting)
		return {"error":"closed" if closed else "replay_current_mismatch","detail":original.get("error")}
	var removed: Dictionary=execution_prefix[index].duplicate(true)
	var alternate: Dictionary=await _run_replay(execution_prefix.slice(0,index),completed_ticks)
	await _dispose_replay_worker()
	if not alternate.error.is_empty() or closed:
		busy=false;ready_for_ticks=not closed
		_finish_checkpoint(&"closed" if closed else &"replay_target_failed",true,previous_accepting)
		return {"error":"closed" if closed else "replay_target_failed","detail":alternate.get("error")}
	var record: Dictionary={"command":removed.command,"policy":removed.policy,"speed":removed.speed,"tick":removed.execution_tick,"replay_checkpoint":original.checkpoint}
	alternate.checkpoint.gpu_edit_configuration.water_policy=selection.policy
	alternate.checkpoint.gpu_edit_configuration.signed_speed_m_s=selection.speed
	var redo_before: Array=redo_commands.duplicate(true)
	checkpoint_running=false;busy=false;ready_for_ticks=true
	var restored: StringName=await restore_checkpoint_data(alternate.checkpoint)
	if restored.is_empty():
		redo_commands=redo_before;redo_commands.append(record)
		while redo_commands.size()>32: redo_commands.pop_front()
	replay_events.append({"kind":"undo","original_fields_exact":exact,"removed_command_id":removed.command.command_id,"target_tick":completed_ticks,"worker_history_bytes":alternate.history_bytes,"error":String(restored)})
	return {"ok":restored.is_empty(),"error":String(restored),"generation":generation,"tick":completed_ticks,"command_id":removed.command.command_id,"original_fields_exact":exact}

func shutdown() -> void:
	if replay_worker!=null:
		closed=true
		await _dispose_replay_worker()
	await super.shutdown()

func redo_latest() -> Dictionary:
	if checkpoint_running: return {"error":"checkpoint_busy"}
	if not redo_commands.is_empty() and redo_commands[-1].get("same_tick_transaction",false) and redo_commands[-1].tick==completed_ticks: return await super.redo_latest()
	if not redo_commands.is_empty() and (redo_commands[-1].has("replay_checkpoint") or redo_commands[-1].has("replay_target")): return await _redo_by_replay()
	return await super.redo_latest()

func _checkpoint_matches(checkpoint: Dictionary, raw: Dictionary, ledger: Dictionary) -> bool:
	for field in raw:
		if raw[field]!=checkpoint.gpu_edit_sidecar.raw_fields[field]: return false
	return ledger==checkpoint.gpu_edit_sidecar.ledger

func _redo_by_replay() -> Dictionary:
	if not paused: return {"error":"requires_pause"}
	if busy or input_running or closed or not ready_for_ticks: return {"error":"backend_unavailable"}
	if not command_queue.pending.is_empty() or input_scheduler.reserved_total()!=0.0: return {"error":"pending_commands"}
	var record: Dictionary=redo_commands[-1]
	var expected_target: Dictionary=RedoCodec.summarize(record)
	if expected_target.tick>completed_ticks: return {"error":"redo_branch_tick_mismatch"}
	var stack: Array=redo_commands.duplicate(true)
	var accepting_before: bool=input_scheduler.accepting
	checkpoint_running=true;input_scheduler.accepting=false
	var raw: Dictionary=await snapshot_state()
	var ledger:=_ledger_values()
	ready_for_ticks=false;busy=true
	var baseline: Dictionary=await _run_replay(execution_prefix,completed_ticks)
	await _dispose_replay_worker()
	var exact: bool=baseline.error.is_empty() and _checkpoint_matches(baseline.checkpoint,raw,ledger)
	if not exact or closed:
		busy=false;ready_for_ticks=not closed
		_finish_checkpoint(&"closed" if closed else &"replay_current_mismatch",true,accepting_before)
		return {"error":"closed" if closed else "replay_current_mismatch"}
	var target: Dictionary=await _run_replay(expected_target.prefix,completed_ticks,expected_target)
	await _dispose_replay_worker()
	var target_exact: bool=target.error.is_empty() and target.archived_target_exact
	if not target_exact or closed:
		busy=false;ready_for_ticks=not closed
		_finish_checkpoint(&"closed" if closed else &"replay_target_mismatch",true,accepting_before)
		return {"error":"closed" if closed else "replay_target_mismatch"}
	target.checkpoint.gpu_edit_configuration.water_policy=record.policy
	target.checkpoint.gpu_edit_configuration.signed_speed_m_s=record.speed
	checkpoint_running=false;busy=false;ready_for_ticks=true
	var error: StringName=await restore_checkpoint_data(target.checkpoint)
	if error.is_empty(): stack.pop_back();redo_commands=stack
	replay_events.append({"kind":"redo","original_fields_exact":exact,"target_fields_exact":target_exact,"target_tick":completed_ticks,"worker_history_bytes":target.history_bytes,"error":String(error)})
	return {"ok":error.is_empty(),"error":String(error),"tick":completed_ticks,"generation":generation,"original_fields_exact":exact,"target_fields_exact":target_exact}

func reset_domain() -> void:
	if checkpoint_running: return
	await super.reset_domain()
	if ready_for_ticks:
		legacy_prefix_present=false;checkpoint_events.clear();replay_events.clear()
		await _capture_replay_anchor()

func seed_test_fields(fields: Dictionary, stock_m3: float=2.0) -> void:
	await super.seed_test_fields(fields,stock_m3)
	if ready_for_ticks: await _capture_replay_anchor()

func _ledger_values() -> Dictionary:
	var ledger: Dictionary={}
	for key in ["tool_inventory_m3","water_source_m3","water_sink_m3","sand_source_m3","sand_sink_m3"]: ledger[key]=domain.get(key)
	return ledger

func _capture_replay_anchor() -> void:
	checkpoint_running=true;ready_for_ticks=false;busy=true;input_scheduler.accepting=false
	readbacks.clear()
	var token:=generation
	RenderingServer.call_on_render_thread(_render_read.bind(STATE_FIELDS.duplicate(),token))
	while readbacks.size()<STATE_FIELDS.size() and not closed and last_error.is_empty(): await get_tree().process_frame
	if not closed and last_error.is_empty():
		var built:=CheckpointCodec.build(readbacks,_ledger_values(),execution_prefix,completed_ticks,generation,solver.state_revision,command_queue.last_command_id)
		if built.error.is_empty():
			replay_anchor=built.checkpoint;replay_anchor.gpu_edit_configuration=checkpoint_configuration()
		else: _fail("replay anchor capture failed: "+String(built.error))
	busy=false;checkpoint_running=false;ready_for_ticks=not closed and last_error.is_empty()
	input_scheduler.accepting=ready_for_ticks

func checkpoint_configuration() -> Dictionary:
	var sources: Dictionary={}
	for name in SHADERS: sources["res://shaders/simulation/"+name+".glsl"]=FileAccess.get_sha256("res://shaders/simulation/"+name+".glsl")
	for path in ["res://scripts/simulation/edit_validation/gpu_checkpoint_codec.gd","res://scripts/simulation/edit_validation/lab_solver.gd","res://scripts/simulation/edit_validation/gpu_sand_editor.gd","res://scripts/simulation/edit_validation/gpu_water_editor.gd","res://shaders/simulation/shallow_collision_pack.glsl","res://tests/edit_validation/lab_surface.gdshader"]: sources[path]=FileAccess.get_sha256(path)
	for metadata in shader_metadata: sources[metadata.path]=metadata.source_sha256
	sources["res://scripts/simulation/edit_validation/gpu_redo_codec.gd"]=FileAccess.get_sha256("res://scripts/simulation/edit_validation/gpu_redo_codec.gd")
	sources["res://tests/edit_validation/gpu_brush_lab_entry.gd"]=FileAccess.get_sha256("res://tests/edit_validation/gpu_brush_lab_entry.gd")
	for path in ["res://scripts/simulation/edit_validation/edit_protocol.gd","res://scripts/simulation/edit_validation/gpu_edit_scheduler.gd","res://scripts/simulation/edit_validation/gpu_edit_history.gd","res://scripts/simulation/gpu_shallow_solver.gd","res://scripts/simulation/sand_water_domain.gd","res://scripts/sand/tool_command_queue.gd","res://tests/edit_validation/edit_lab.gd","res://tests/edit_validation/interaction_lab_entry.gd","res://tests/edit_validation/recovery_lab_entry.gd","res://tests/edit_validation/checkpoint_lab_entry.gd"]: sources[path]=FileAccess.get_sha256(path)
	return {"version":1,"fixture":"edit_checkpoint_lab_v1","engine":Engine.get_version_info(),"sources":sources,"spirv":shader_metadata.duplicate(true),"sim_hz":profile.sim_hz,"profile_path":profile.resource_path,"profile_sha256":FileAccess.get_sha256(profile.resource_path),"effective_profile":effective_profile.duplicate(true),"boundary":"closed","erosion":false,"local_dispatch":local_dispatch,"fast_full_wet":fast_full_wet,"water_policy":water_policy,"signed_speed_m_s":signed_speed_m_s,"visual_time_s":float(completed_ticks)/profile.sim_hz,"visual_history":"none_in_numeric_fixture"}

func _finish_checkpoint(error: StringName, previous_pause: bool, previous_accepting: bool) -> StringName:
	checkpoint_events.append({"error":String(error),"tick":completed_ticks,"generation":generation,"pending":command_queue.pending.size(),"reserved":input_scheduler.reserved_total(),"restore_phase":restore_phase,"at_us":Time.get_ticks_usec()})
	checkpoint_running=false
	if not closed and last_error.is_empty(): paused=previous_pause;input_scheduler.accepting=previous_accepting
	return error

func save_checkpoint(path: String) -> StringName:
	if checkpoint_running or recovery_running or closed or not ready_for_ticks: return &"backend_unavailable"
	if profile.grid_size!=256 or profile.cell_size_m!=0.125: return &"unsupported_checkpoint_grid"
	if legacy_prefix_present: return &"legacy_prefix_not_supported_yet"
	var previous_pause:=paused
	var previous_accepting: bool=input_scheduler.accepting
	checkpoint_running=true;paused=true;input_scheduler.accepting=false;active_brush=&""
	while (busy or input_running or input_scheduler.pumping) and not closed and last_error.is_empty(): await get_tree().process_frame
	if closed: return _finish_checkpoint(&"closed",previous_pause,previous_accepting)
	if not last_error.is_empty(): return _finish_checkpoint(&"backend_failed",previous_pause,previous_accepting)
	await input_scheduler.drain_due()
	# Future admitted work cannot be silently omitted or moved to another tick.
	# Leave it intact and fail this save until its scheduled tick is complete.
	if not command_queue.pending.is_empty() or input_scheduler.reserved_total()!=0.0: return _finish_checkpoint(&"pending_commands",previous_pause,previous_accepting)
	var raw: Dictionary=await snapshot_state()
	if closed: return _finish_checkpoint(&"closed",previous_pause,previous_accepting)
	if not last_error.is_empty() or raw.size()!=STATE_FIELDS.size(): return _finish_checkpoint(&"capture_failed",previous_pause,previous_accepting)
	var ledger: Dictionary={}
	for key in ["tool_inventory_m3","water_source_m3","water_sink_m3","sand_source_m3","sand_sink_m3"]: ledger[key]=domain.get(key)
	var built:=CheckpointCodec.build(raw,ledger,execution_prefix,completed_ticks,generation,solver.state_revision,command_queue.last_command_id,command_queue.pending.size(),input_scheduler.reserved_total())
	if not built.error.is_empty(): return _finish_checkpoint(built.error,previous_pause,previous_accepting)
	built.checkpoint.gpu_edit_configuration=checkpoint_configuration()
	if not replay_anchor.is_empty(): built.checkpoint.gpu_edit_replay_anchor=replay_anchor.duplicate(true)
	built.checkpoint.gpu_edit_redo=RedoCodec.pack(redo_commands)
	var redo_check:=RedoCodec.unpack(built.checkpoint.gpu_edit_redo,built.checkpoint.gpu_edit_sidecar,domain.domain_id)
	if not redo_check.error.is_empty(): return _finish_checkpoint(redo_check.error,previous_pause,previous_accepting)
	return _finish_checkpoint(CheckpointCodec.save(path,built.checkpoint),previous_pause,previous_accepting)

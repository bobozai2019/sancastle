extends RefCounted

const Slots=preload("res://scripts/simulation/edit_validation/frame_pipeline/async_slots.gd")
const Water=preload("res://scripts/simulation/edit_validation/frame_pipeline/async_water.gd")
const Coupled=preload("res://scripts/simulation/edit_validation/frame_pipeline/async_coupled.gd")
const Visuals=preload("res://scripts/simulation/edit_validation/frame_pipeline/async_visuals.gd")
const Collision=preload("res://scripts/simulation/edit_validation/frame_pipeline/async_collision.gd")
const Tools=preload("res://scripts/simulation/edit_validation/frame_pipeline/async_tools.gd")
var owner
var slots
var water:=Water.new()
var coupled:=Coupled.new()
var visuals:=Visuals.new()
var collision
var tools
var gravel_admitted_count:=-1
var records:={}
var ready:=false
var transitioning:=false
var frozen:=false
var legacy:=false
var hold_completions:=false # Test observer: bounded backpressure, no behavior fallback.
var hold_collision:=false
var accumulator:=0.0
var water_owed:=false
var last_edit_frame:=-1
var state_seq:=0
var actual_time:=0.0
var accepted_commands:=0
var rejected_commands:=0
var submitted_edits:=0
var submitted_water:=0
var nominal_upper_supply:=0.0
var events: Array[Dictionary]=[]
var waves_key:=""
var wave_start_times:={}
var explicit_ticks:=0
var fault_reason:=""
var cleanup_pending:={}
var unconfirmed_ownership:=false
var aborted_units:=0
var unrecorded_units:=0
var inject_initialize_failure_phase:=""

func _init(entry, epoch: int=-1) -> void:
	owner=entry
	slots=Slots.new(entry.generation if epoch<0 else epoch)
	collision=Collision.new(entry.collision_proxy)
	collision.failure_callback=_collision_failed

func initialize_render(resources: Dictionary={}) -> bool:
	var solver=resources.get("solver",owner.solver)
	if not solver.enable_async():return false
	if inject_initialize_failure_phase=="transport":water.last_error="injected_transport_boundary";return false
	if not water.initialize(solver):return false
	if inject_initialize_failure_phase=="water":water.last_error="injected_water_boundary";return false
	if owner.enable_erosion and not coupled.initialize(water,resources.get("sediment_coupler",owner.sediment_coupler),resources.get("material_coupler",owner.material_coupler)):return false
	if not visuals.initialize(water,resources.get("foam_field",owner.foam_field),resources.get("gravel_field",owner.gravel_field),resources.get("local_front_field",owner.local_front_field),owner.prototype_local_front_wide_field):return false
	var brush=resources.get("shape_gpu",owner.get("shape_gpu"))
	if brush!=null:
		tools=Tools.new()
		if not tools.initialize(solver,brush,resources.get("gravel_field",owner.gravel_field),visuals):water.last_error=tools.last_error;return false
	if inject_initialize_failure_phase=="visuals":water.last_error="injected_visuals_boundary";return false
	var tide:=Vector3(0.10,0.11,0.35)
	if owner.scene_key!="main":
		tide=Vector3(owner.CaptureLayout.SEA_OFFSET,0.049701884388923645,1.0)
		water.tide_phase=284.71783447265625
		water.tide_mode=2 if owner.scene_key=="test1_backwash" else 1
		if owner.scene_key=="test1_geometry":
			var profile: Dictionary=owner.GeometryLayout.water_cycle()
			if profile.is_empty():water.last_error="invalid_geometry_water_cycle";return false
			tide=Vector3(profile.rest_level_m,profile.runup_height_m,0.0)
			water.tide_phase=0.0
			water.tide_period=profile.period_s
			water.tide_mode=3
	if not water.configure_boundary(tide,[]):return false
	if not water._compile("bridge","res://scripts/simulation/edit_validation/frame_pipeline/async_bridge.glsl"):return false
	water.kernels.bridge.binding=water._make_binding(water.kernels.bridge.shader,0,[],[solver.async_transport.control])
	return collision.initialize(solver)

func _event(name: String, id: Dictionary={}, extra: Dictionary={}) -> void:
	var row:=id.duplicate(true)
	row.merge(extra,true)
	row.event=name
	row.frame_id=Engine.get_process_frames()
	events.append(row)
	if events.size()>128:events.pop_front()

static func ordinary(command: Dictionary) -> bool:
	return command.get("schema_version",1)==1 and command.get("sand_destination","bed") in ["bed","suspended_v1"] and command.get("kind") in [&"remove_sand",&"place_sand"]

func poll() -> void:
	if not fault_reason.is_empty():return
	if hold_completions:return
	var ids:=records.keys()
	ids.sort()
	var changed:=false
	for batch in ids:
		var record: Dictionary=records[batch]
		var slot: Dictionary=slots.slots[record.identity.slot_id]
		if slot.state!=Slots.State.GPU_COMPLETE:break
		var result: Dictionary=slots.consume(record.identity)
		changed=true
		_book_submission(record)
		if result.state_seq>=state_seq:
			state_seq=result.state_seq
			actual_time=result.advanced_time_s
			owner.completed_ticks=result.sim_tick
			owner.shadow_domain.sim_tick=result.sim_tick
			owner.solver.state_revision=result.revision
			owner.visual_time_s=actual_time
			accepted_commands=result.accepted_commands
			rejected_commands=result.rejected_commands
			if owner.gravel_field!=null:
				owner.gravel_field.completed_tick=result.sim_tick
				owner.gravel_field.revision=result.revision
		for command in record.commands:
			var terminal: Dictionary=record.get("tool_result",{"submitted":true,"gpu_complete":true,"state_seq":result.state_seq,"ledger_precision":"approximate"}).duplicate(true)
			terminal.state_seq=result.state_seq
			if command.get("schema_version")==2 and terminal.get("status")==1:
				owner.domain.sand_source_m3+=terminal.external_source_delta_m3
				owner.domain.sand_sink_m3+=terminal.external_sink_delta_m3
			owner.input_scheduler._record(owner.input_scheduler.terminal,{"command":command,"result":terminal})
			owner.input_scheduler.reservations.erase(command.command_id)
			owner.input_scheduler.policies.erase(command.command_id)
			if owner.has_method("_async_tool_settled"):owner._async_tool_settled(command,terminal)
		_event("cpu_consume",record.identity,{"state_seq":result.state_seq,"sim_tick":result.sim_tick,"kind":record.kind})
		RenderingServer.call_on_render_thread(_retire_render.bind(record.identity))
		records.erase(batch)
	owner.input_results=owner.input_scheduler.terminal.duplicate(true)
	if changed and owner.has_method("_update_status"):owner._update_status()

func pump(delta: float) -> void:
	if not ready or legacy or frozen or owner.closing or not owner.last_error.is_empty():return
	var automatic: bool=owner.playing and not transitioning and not owner.async_checkpoint_running and not owner.beach_restore_running and not owner.shutdown_requested
	if automatic:
		accumulator=minf(accumulator+delta,owner.SIM_DELTA*4.0)
	else:
		accumulator=0.0
		water_owed=false
	_update_waves()
	var water_submitted:=false
	if explicit_ticks>0:
		water_submitted=_submit_water()
		if water_submitted:explicit_ticks-=1
	# A low-frequency boundary drains accepted scheduled input too. Advance only
	# as far as its due tick, accounting for the bounded water work already queued.
	if not water_submitted and (owner.async_checkpoint_running or owner.beach_restore_running) and not owner.command_queue.pending.is_empty():
		var due: int=owner.command_queue.pending[0].sim_tick
		var queued_water:=0
		for record in records.values():
			if record.kind=="water":queued_water+=1
		if owner.completed_ticks+queued_water<due:water_submitted=_submit_water()
	if not water_submitted and water_owed and automatic:water_submitted=_submit_water()
	if last_edit_frame!=Engine.get_process_frames():_submit_edit()
	if not water_submitted and automatic and accumulator>=owner.SIM_DELTA:
		water_submitted=_submit_water()
		water_owed=not water_submitted
	collision.pump()

func _acquire(kind: String, commands: Array) -> Dictionary:
	var acquired: Dictionary=slots.acquire()
	if not acquired.error.is_empty():
		if acquired.error=="identity_exhausted":_fail_pipeline("identity_exhausted")
		return {}
	var id: Dictionary=acquired.identity
	slots.submitted(id)
	records[id.batch_seq]={"identity":id,"kind":kind,"commands":commands,"booked":false}
	_event("submit",id,{"kind":kind,"count":commands.size()})
	return id

func _submit_edit() -> bool:
	# Admission closes before shutdown. Already accepted units, including an
	# owned stroke's END marker, must still drain through this same stream.
	if owner.command_queue.pending.is_empty():return false
	if not ordinary(owner.command_queue.pending[0]):return _submit_tool()
	var commands:=[]
	var envelopes:=[]
	var first_policy:=-1
	for command in owner.command_queue.pending:
		if commands.size()>=owner.edit_frame_batch_limit or command.sim_tick>owner.completed_ticks or not ordinary(command):break
		var selection: Dictionary=owner.input_scheduler.policies[command.command_id]
		if first_policy<0:first_policy=selection.policy
		if selection.policy!=first_policy:break
		commands.append(command.duplicate(true))
		envelopes.append(owner._encode_gpu_command(command,owner.ticket_id+commands.size(),0,selection,owner.sand_command_available(command)))
	if commands.is_empty():return false
	var id:=_acquire("edit",commands)
	if id.is_empty():return false
	for command in commands:owner.command_queue.pending.pop_front()
	owner.ticket_id+=commands.size()
	last_edit_frame=Engine.get_process_frames()
	submitted_edits+=1
	RenderingServer.call_on_render_thread(_submit_render.bind(id,"edit",envelopes))
	for envelope in envelopes:collision.mark_command(envelope)
	return true

func _submit_tool() -> bool:
	var command: Dictionary=owner.command_queue.pending[0]
	if command.sim_tick>owner.completed_ticks:return false
	if tools==null:_fail_pipeline("tool_backend_unavailable");return false
	var id:=_acquire("tool",[command.duplicate(true)])
	if id.is_empty():return false
	owner.command_queue.pending.pop_front()
	owner.ticket_id+=1
	records[id.batch_seq].ticket=owner.ticket_id
	last_edit_frame=Engine.get_process_frames()
	submitted_edits+=1
	RenderingServer.call_on_render_thread(_submit_tool_render.bind(id,command.duplicate(true),owner.ticket_id))
	if Tools.mode(command) in [Tools.Mode.SHAPE,Tools.Mode.SMOOTH,Tools.Mode.COMPACT]:collision.mark_all()
	return true

func _submit_tool_render(id: Dictionary, command: Dictionary, ticket: int) -> void:
	if not fault_reason.is_empty():call_deferred("_submission_done",id,"cancelled_before_recording");return
	var error: String=tools.submit(id,command,ticket,_arrived)
	if error.is_empty():owner._bind_async_textures_render()
	call_deferred("_submission_done",id,error)

func _submit_water() -> bool:
	var id:=_acquire("water",[])
	if id.is_empty():return false
	accumulator=maxf(0.0,accumulator-owner.SIM_DELTA)
	water_owed=false
	submitted_water+=1
	RenderingServer.call_on_render_thread(_submit_render.bind(id,"water",[]))
	if owner.enable_erosion:collision.mark_all()
	return true

func _submit_render(id: Dictionary, kind: String, envelopes: Array) -> void:
	if not fault_reason.is_empty():call_deferred("_submission_done",id,"cancelled_before_recording");return
	var error: String=owner.solver.dispatch_async_batch(id,envelopes,_arrived) if kind=="edit" else water.dispatch(id,owner.SIM_DELTA,_arrived)
	if error.is_empty():owner._bind_async_textures_render()
	call_deferred("_submission_done",id,error)

func _submission_done(id: Dictionary, error: String) -> void:
	if id.generation!=owner.generation or not records.has(id.batch_seq):return
	if error.is_empty():_book_submission(records[id.batch_seq]);return
	if error!="readback_submit_failed":
		_record_aborted_commands(records[id.batch_seq],false,"submission:"+error)
		slots.abandon_unrecorded(id)
		records.erase(id.batch_seq)
		cleanup_pending.erase(id.batch_seq)
		unrecorded_units+=1
		_event("unrecorded_abort",id,{"reason":error})
		_refresh_unknown()
	else:_book_submission(records[id.batch_seq])
	_fail_pipeline("submission:"+error)

func _book_submission(record: Dictionary) -> void:
	if record.booked:return
	record.booked=true
	for command in record.commands:
		if not ordinary(command):
			if command.get("schema_version")==2:nominal_upper_supply+=2.0*float(command.add_budget_m3)+1.0
			continue
		var amount: float=command.amount_m3*command.strength
		if command.kind==&"place_sand":
			owner.domain.sand_source_m3+=amount
			nominal_upper_supply+=2.0*amount+1.0
		else:owner.domain.sand_sink_m3+=amount

func _arrived(bytes: PackedByteArray, id: Dictionary) -> void:
	call_deferred("_receive",bytes,id)

func _receive(bytes: PackedByteArray, id: Dictionary) -> void:
	var record: Dictionary=records.get(id.get("batch_seq",-1),{})
	if not record.is_empty() and not Slots.Wire.same_lease(record.identity,id):return
	var tool: bool=record.get("kind")=="tool"
	if tool and bytes.size()!=Slots.Wire.COMPLETION_BYTES+256:_fail_pipeline("completion:tool_size");return
	var error: String=slots.completed(bytes.slice(0,Slots.Wire.COMPLETION_BYTES) if tool else bytes,id)
	if error in ["stale_lease","duplicate_or_wrong_state"]:return
	if not error.is_empty():_fail_pipeline("completion:"+error);return
	if slots.slots[id.slot_id].completion.error_flags!=0:_fail_pipeline("completion:gpu_error_flags");return
	if tool:
		var decoded: Dictionary=tools.decode(bytes.slice(Slots.Wire.COMPLETION_BYTES),record.commands[0],record.ticket)
		if decoded.has("error"):_fail_pipeline("completion:"+String(decoded.error));return
		var completed: Dictionary=slots.slots[id.slot_id].completion
		if decoded.output_revision!=completed.revision or decoded.applied_tick!=completed.sim_tick:_fail_pipeline("completion:tool_state_mismatch");return
		record.tool_result=decoded
	if not fault_reason.is_empty():_request_cleanup(id);return
	_event("gpu_complete",id)

func _fail_pipeline(reason: String, report: bool=true) -> void:
	if fault_reason.is_empty():
		fault_reason=reason
		explicit_ticks=0;slots.stop_admission()
		owner.ready_for_ticks=false
		collision.closing=true;collision.pending.clear()
		owner.input_scheduler.accepting=false
		owner.input_scheduler.cancel_pending("pipeline_failed")
		if report:owner._fail("GPU pipeline fatal: "+reason)
	for record in records.values():_request_cleanup(record.identity)

func _request_cleanup(id: Dictionary) -> void:
	if not records.has(id.batch_seq) or cleanup_pending.get(id.batch_seq,"") in ["pending","retiring"]:return
	cleanup_pending[id.batch_seq]="pending"
	RenderingServer.call_on_render_thread(_terminal_render.bind(id))

func _terminal_render(id: Dictionary) -> void:
	water.solver.async_transport.request_terminal(id,_terminal_arrived)

func _terminal_arrived(id: Dictionary, confirmed: bool, reason: String) -> void:
	call_deferred("_terminal_result",id,confirmed,reason)

func _terminal_result(id: Dictionary, confirmed: bool, reason: String) -> void:
	if not records.has(id.batch_seq) or not Slots.Wire.same_lease(records[id.batch_seq].identity,id):return
	if not confirmed:
		cleanup_pending[id.batch_seq]="unavailable";_refresh_unknown()
		_event("ownership_unconfirmed",id,{"reason":reason})
		return
	cleanup_pending[id.batch_seq]="retiring"
	_event("terminal_proof",id,{"reason":reason})
	RenderingServer.call_on_render_thread(_abort_retire_render.bind(id))

func _abort_retire_render(id: Dictionary) -> void:
	var ok: bool=water.solver.retire_async(id)
	call_deferred("_abort_retired",id,ok)

func _abort_retired(id: Dictionary, ok: bool) -> void:
	if not records.has(id.batch_seq) or not Slots.Wire.same_lease(records[id.batch_seq].identity,id):return
	if not ok or not slots.abort_after_last_consumer(id):
		cleanup_pending[id.batch_seq]="unavailable";_refresh_unknown();return
	var record: Dictionary=records[id.batch_seq]
	_book_submission(record)
	_record_aborted_commands(record,true,fault_reason)
	records.erase(id.batch_seq);cleanup_pending.erase(id.batch_seq)
	aborted_units+=1;_refresh_unknown()
	_event("error_abort",id)

func _record_aborted_commands(record: Dictionary, submitted: bool, reason: String) -> void:
	for command in record.commands:
		owner.input_scheduler._record(owner.input_scheduler.terminal,{"command":command,"result":{"submitted":submitted,"aborted":true,"error":reason,"ledger_precision":"approximate"}})
		owner.input_scheduler.reservations.erase(command.command_id);owner.input_scheduler.policies.erase(command.command_id)

func _refresh_unknown() -> void:
	unconfirmed_ownership="unavailable" in cleanup_pending.values()

func retry_fault_cleanup() -> void:
	for record in records.values():_request_cleanup(record.identity)
	collision.retry_failed_fences()

func _collision_failed(reason: String) -> void:
	_fail_pipeline("collision:"+reason)

func _retire_render(id: Dictionary) -> void:
	if not is_instance_valid(owner) or id.generation!=owner.generation or water.solver==null or water.solver.rd==null:return
	if not water.solver.retire_async(id):call_deferred("_retire_failed",id)

func _retire_failed(id: Dictionary) -> void:
	if not is_instance_valid(owner) or id.generation!=owner.generation:return
	owner._fail("GPU pipeline lease retirement failed")

func _update_waves() -> void:
	var key:=str(owner.wave_requests)
	if key==waves_key:return
	waves_key=key
	var packets:=[]
	for request in owner.wave_requests:
		if request.generation!=owner.generation:continue
		if not wave_start_times.has(request.request_id):wave_start_times[request.request_id]=actual_time+(int(request.start_tick)-owner.completed_ticks-1.5)*owner.SIM_DELTA
		var start: float=wave_start_times[request.request_id]
		packets.append(Vector4(start,request.duration_s,request.amplitude_m,float(int(request.seed)&1023)*TAU/1024.0))
	RenderingServer.call_on_render_thread(_waves_render.bind(packets))

func _waves_render(packets: Array) -> void:
	if not water.configure_boundary(water.tide,packets):call_deferred("_wave_error")

func _wave_error() -> void:
	owner._fail("GPU wave configuration: "+water.last_error)

func idle(include_collision: bool=false) -> bool:
	return explicit_ticks==0 and records.is_empty() and slots.active_count()==0 and (not include_collision or (collision.pending.is_empty() and collision.active_count()==0))

func physics_consume() -> void:
	if not hold_collision:collision.physics_consume()

func bridge() -> void:
	var id:=_acquire("bridge",[])
	if id.is_empty():owner._fail("GPU legacy bridge has no free slot");return
	RenderingServer.call_on_render_thread(_bridge_render.bind(id,owner.solver.state_revision))
	while records.has(id.batch_seq) and owner.last_error.is_empty():await owner.get_tree().process_frame

func _bridge_render(id: Dictionary, revision: int) -> void:
	var solver=owner.solver
	if solver.current_index!=0:
		for field in solver.textures:
			if solver.textures[field] is Array:solver._copy_texture(solver.textures[field][solver.current_index],solver.textures[field][0])
		solver.current_index=0
	visuals.rebind_slots()
	var payload:=PackedByteArray()
	payload.resize(128)
	var error: String=solver.async_transport.submit(id,payload,_record_bridge.bind(revision),_arrived)
	if error.is_empty():owner._bind_async_textures_render()
	call_deferred("_submission_done",id,error)

func _record_bridge(_input: RID, _control: RID, _count: int, revision: int) -> void:
	var data:=PackedByteArray()
	data.resize(16)
	data.encode_u64(0,revision)
	var rd: RenderingDevice=owner.solver.rd
	var list:=rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list,water.kernels.bridge.pipeline)
	rd.compute_list_bind_uniform_set(list,water.kernels.bridge.binding,0)
	rd.compute_list_set_push_constant(list,data,16)
	rd.compute_list_dispatch(list,1,1,1)
	rd.compute_list_end()

func release_render() -> bool:
	if water.solver==owner.solver and owner._async_has_external_owners():return false
	if not records.is_empty() or slots.active_count()!=0:return false
	if water.solver!=null and water.solver.async_transport.has_owned():return false
	if not collision.release_render():return false
	if tools!=null:tools.release();tools=null
	coupled.detach()
	visuals.detach()
	water.release()
	return true

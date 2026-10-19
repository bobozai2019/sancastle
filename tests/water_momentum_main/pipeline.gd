extends RefCounted

const L=preload("res://scripts/simulation/unified_edit/layout.gd")
const I=preload("res://scripts/simulation/unified_edit/intent.gd")
const W=preload("res://scripts/simulation/unified_edit/protocol.gd")
const C=preload("res://scripts/simulation/unified_edit/configuration.gd")
const Slots=preload("res://scripts/simulation/unified_edit/slots.gd")
const Diagnostics=preload("res://scripts/simulation/unified_edit/diagnostics.gd")
const Transport=preload("res://scripts/simulation/unified_edit/transport.gd")
const State=preload("res://scripts/simulation/unified_edit/state.gd")
const Executor=preload("res://tests/water_momentum_main/executor.gd")
const Water=preload("res://scripts/simulation/unified_edit/water.gd")
const Coupled=preload("res://scripts/simulation/unified_edit/coupled.gd")
const Height=preload("res://scripts/simulation/unified_edit/height.gd")
const Views=preload("res://scripts/simulation/unified_edit/views.gd")
const Visuals=preload("res://scripts/simulation/unified_edit/visuals.gd")
const Boundary=preload("res://scripts/simulation/unified_edit/boundary.gd")
const Adapter=preload("res://scripts/simulation/unified_edit/api_adapter.gd")
const ADAPTER_SOURCES=["res://scripts/simulation/unified_edit/api_adapter.gd","res://scripts/simulation/brushes/brush_protocol.gd","res://scripts/sand/brushes/brush_spec.gd","res://scripts/sand/brushes/brush_registry.gd","res://scripts/sand/brushes/brush_definition.gd","res://assets/brushes/protocol_v2.json","res://assets/brushes/castle_v1.tres","res://assets/brushes/wall_v1.tres","res://assets/brushes/shovel_v1.tres"]
const Checkpoint=preload("res://scripts/simulation/unified_edit/checkpoint_codec.gd")
const RestoreVerifier=preload("res://scripts/simulation/unified_edit/restore_verifier.gd")
const Accounting=preload("res://scripts/simulation/unified_edit/checkpoint_accounting.gd")
const Capture=preload("res://scripts/simulation/unified_edit/checkpoint_capture.gd")
const Display=preload("res://scripts/simulation/unified_edit/display_intent.gd")
const MAX_PENDING:=64
const MAX_RESULTS:=512
const SOURCE_PATHS=["res://scripts/simulation/unified_edit/diagnostics.gd","res://scripts/simulation/unified_edit/checkpoint_accounting.gd","res://scripts/simulation/unified_edit/checkpoint_capture.gd","res://scripts/simulation/unified_edit/restore_verifier.gd","res://scripts/simulation/unified_edit/idle_fence.glsl","res://scripts/simulation/unified_edit/gpu.gd","res://scripts/simulation/unified_edit/slots.gd","res://scripts/simulation/unified_edit/transport.gd","res://scripts/simulation/unified_edit/state.gd","res://scripts/simulation/unified_edit/unit_half.gd","res://scripts/simulation/unified_edit/publish.glsl","res://scripts/simulation/unified_edit/water.gd","res://tests/water_momentum_main/executor.gd","res://tests/water_momentum_main/pipeline.gd","res://scripts/simulation/unified_edit/work_begin.glsl","res://scripts/simulation/unified_edit/work_seal.glsl","res://scripts/simulation/unified_edit/edit.glsl","res://scripts/simulation/unified_edit/cfl_decide.glsl","res://scripts/simulation/edit_validation/frame_pipeline/async_cfl_tiles.glsl","res://scripts/simulation/edit_validation/frame_pipeline/async_sim_finish.glsl","res://scripts/simulation/edit_validation/frame_pipeline/async_normalize.glsl","res://scripts/simulation/edit_validation/frame_pipeline/async_boundary.glsl","res://shaders/simulation/shallow_edge_flux.glsl","res://shaders/simulation/shallow_drain_scale.glsl","res://shaders/simulation/shallow_update_state.glsl"]+Coupled.SOURCES+Executor.Response.SOURCES+Height.SOURCES+Views.SOURCES+Visuals.SOURCES+Boundary.SOURCES+Display.SOURCES
var visuals:=Visuals.new()
var boundary:=Boundary.new()
var accounting:=Accounting.new()
var checkpoint_capture
var checkpoint_serial:=0
var last_checkpoint_info: Dictionary={}
var _checkpoint_callback: Callable
var _checkpoint_path:=""
var _checkpoint_end_ids: Dictionary={}
var restore_verifier:=RestoreVerifier.new()
var _restore: Dictionary={}
var slots:=Slots.new()
var transport:=Transport.new()
var state:=State.new()
var executor:=Executor.new()
var water:=Water.new()
var coupled:=Coupled.new()
var heights:=Height.new()
var views:=Views.new()
var _registry
var _configuration: Dictionary={}
var _generation:=0
var _highwater:=0
var _scheduled_tick:=0
var _cleanup_pending: Dictionary={}
var _pending: Array[Dictionary]=[]
var _records: Dictionary={}
var _results: Dictionary={}
var _result_reservations:=0
var _reserved_ids: Dictionary={}
var _ready:=false
var _closing:=false
var _fault: StringName=&""
var completed_tick:=0
var completed_revision:=0
var completed_state_seq:=0
var advanced_time_s:=0.0
var initialized:=false
var released:=false
var initialization_started:=false
var initialization_error: StringName=&""
var initialization_cleanup_pending:=false
var initialization_cleanup_unknown:=false
var initialization_ownership: Dictionary={}
var inject_initialization_failure_after: StringName=&""
var hold_completions:=false
var arrival_order: Array[int]=[]
var diagnostics: Diagnostics

func configure(registry, configuration: Dictionary, generation: Variant) -> StringName:
	if _registry!=null or released or initialization_started or _closing:return &"pipeline_already_configured"
	var error:=C.validate(configuration,true)
	if not error.is_empty():return error
	if not I.counter(generation,1):return &"invalid_generation"
	if not Checkpoint.Old.number(configuration.environment.get("ordinary_cohesion_yield_height_m",0.0),0.0,2.0):return &"invalid_runtime_ordinary_cohesion"
	error=Visuals.configuration_error(configuration)
	if not error.is_empty():return error
	error=Boundary.configuration_error(configuration)
	if not error.is_empty():return error
	if registry.catalog_snapshot()!=configuration.profiles:return &"configuration_catalog_mismatch"
	for path in SOURCE_PATHS+ADAPTER_SOURCES:
		if configuration.sources.get(path)!=FileAccess.get_sha256(path):return &"incomplete_runtime_configuration_sources"
	error=slots.initialize(configuration.domain_id,generation)
	if not error.is_empty():return error
	_registry=registry;_configuration=configuration.duplicate(true);_generation=generation
	boundary.configure(configuration,generation)
	return &""

func configure_restore(registry, configuration: Dictionary, epoch: Variant, checkpoint: Dictionary) -> StringName:
	if _registry!=null:return &"pipeline_already_configured"
	var error:=Checkpoint.validate(checkpoint,configuration)
	if not error.is_empty():return error
	error=Boundary.configuration_error(configuration)
	if not error.is_empty():return error
	if not I.counter(epoch,1) or epoch<=checkpoint.generation:return &"restore_generation_not_new"
	if checkpoint.simulation.prescribed_tide_boundary!=configuration.environment.get("boundary",{"enabled":false}).get("enabled",false):return &"restore_boundary_configuration_mismatch"
	if not checkpoint.simulation.prescribed_tide_boundary and not checkpoint.wave_requests.is_empty():return &"restore_boundary_disabled_waves"
	error=Visuals.configuration_error(configuration)
	if not error.is_empty():return error
	if configuration.effects.gravel_enabled and checkpoint.visual_extensions.gravel_v1.profile_values!=Visuals.profile_for(configuration):return &"restore_gravel_profile_mismatch"
	if checkpoint.cohesion_yield_height_m!=configuration.environment.get("ordinary_cohesion_yield_height_m",0.0):return &"restore_ordinary_cohesion_configuration_mismatch"
	error=configure(registry,configuration,epoch)
	if not error.is_empty():return error
	_restore=checkpoint.duplicate(true)
	_restore.native.control.encode_s64(8,epoch)
	for wave in _restore.wave_requests:wave.generation=epoch
	boundary.configure(configuration,epoch,_restore)
	_highwater=checkpoint.highwater_id;_scheduled_tick=checkpoint.sim_tick
	completed_state_seq=checkpoint.state_seq;completed_tick=checkpoint.sim_tick;completed_revision=checkpoint.revision;advanced_time_s=checkpoint.advanced_time_s
	return &""

func restore_domain():
	return null if _restore.is_empty() else RestoreVerifier.domain_from(_restore,_generation)

func initialize_render(domain) -> void:
	if initialization_started or released:return
	initialization_started=true
	if _closing:_initialization_failed_render(&"initialization_cancelled");return
	if _registry!=null:state.cohesion_yield_height_m=float(_configuration.environment.get("ordinary_cohesion_yield_height_m",0.0))
	var error: StringName=&""
	# Capabilities are added with their real implementation, never silently off.
	if _registry==null:error=&"unimplemented_runtime_capability"
	elif domain==null or domain.generation!=_generation or String(domain.domain_id)!=_configuration.domain_id:error=&"initial_domain_mismatch"
	elif not transport.initialize(RenderingServer.get_rendering_device(),_configuration.domain_id,_generation,PackedByteArray() if _restore.is_empty() else _restore.native.control):error=StringName("transport/"+transport.last_error)
	elif inject_initialization_failure_after==&"transport":error=&"injected_initialization/transport"
	elif not state.initialize(transport.rd,domain,transport,{} if _restore.is_empty() else _restore.native):error=StringName("state/"+state.last_error)
	elif inject_initialization_failure_after==&"state":error=&"injected_initialization/state"
	elif not accounting.initialize(domain,_restore).is_empty():error=&"invalid_checkpoint_initial_metadata"
	elif not executor.initialize(state,transport,_registry):error=StringName("executor/"+executor.last_error)
	elif inject_initialization_failure_after==&"executor":error=&"injected_initialization/executor"
	elif not water.initialize(state):error=StringName("water/"+water.last_error)
	elif not boundary.initialize_render(water):error=StringName("boundary/"+water.last_error)
	elif inject_initialization_failure_after==&"water":error=&"injected_initialization/water"
	elif _configuration.simulation.enable_erosion and not coupled.initialize(state,water,_configuration.material):error=StringName("coupled/"+coupled.last_error)
	elif inject_initialization_failure_after==&"coupled":error=&"injected_initialization/coupled"
	elif not visuals.initialize(water,_configuration,domain,_restore):error=StringName("visuals/"+visuals.last_error)
	elif inject_initialization_failure_after==&"visuals":error=&"injected_initialization/visuals"
	elif not heights.initialize(state,transport,_generation):error=StringName("height/"+heights.last_error)
	elif inject_initialization_failure_after==&"height":error=&"injected_initialization/height"
	elif not _initialize_views():error=StringName("views/"+views.last_error)
	elif inject_initialization_failure_after==&"views":error=&"injected_initialization/views"
	if not error.is_empty():_initialization_failed_render(error)
	elif _restore.is_empty():call_deferred("_initialized",error)
	else:
		state.state_revision=_restore.revision
		restore_verifier.verify_render(state,executor,views,transport,_restore.native,_restore_verified_render,visuals,_restore.visual_extensions,boundary)

func _initialize_views() -> bool:
	views.visual_textures=visuals.published.duplicate()
	return views.initialize(state,executor,transport,_registry,_configuration,_generation,heights.dirty)

func _restore_verified_render(error: StringName) -> void:
	# RD readback callbacks can still be inside the device's callback delivery
	# phase. A dispatch/readback appended there observed the old idle buffer on
	# D3D12. Return through the main owner before scheduling the cleanup recorder.
	call_deferred("_restore_verified",error)

func _restore_verified(error: StringName) -> void:
	if error.is_empty() and _closing:error=&"initialization_cancelled"
	if error.is_empty():_initialized(error)
	else:RenderingServer.call_on_render_thread(_initialization_failed_render.bind(error))

func _initialization_failed_render(error: StringName) -> void:
	initialization_error=error;initialization_ownership=ownership_counts()
	_request_initialization_cleanup_render()

func _initialized(error: StringName) -> void:
	if error.is_empty() and not _fault.is_empty():
		RenderingServer.call_on_render_thread(_initialization_failed_render.bind(_fault));return
	if error.is_empty() and _closing:
		RenderingServer.call_on_render_thread(_initialization_failed_render.bind(&"initialization_cancelled"));return
	initialized=true;_ready=error.is_empty()
	if error.is_empty() and not _restore.is_empty():views.observe_complete({"state_seq":completed_state_seq})
	if not error.is_empty():_fail(error)

func cancel_initialization() -> bool:
	if initialized or released:return false
	_closing=true;views.close_preview();return true

func ownership_counts() -> Dictionary:
	return {"transport":transport.owned.size(),"state":state.owned.size(),"executor":executor.owned.size(),"water_response":executor.response.owned.size(),"water":water.owned.size(),"coupled":coupled.owned.size(),"height":heights.owned.size(),"views":views.owned.size(),"probe":views.probe.owned.size()}

func _request_initialization_cleanup_render() -> void:
	if initialization_error.is_empty() or initialization_cleanup_pending:return
	initialization_cleanup_pending=true
	if transport.rd==null:_initialization_proved_render(true)
	else:transport.request_idle_proof(_initialization_proved_render)

func _initialization_proved_render(confirmed: bool) -> void:
	var cleaned:=confirmed and _release_owners_render()
	call_deferred("_initialization_cleanup_result",cleaned)

func _initialization_cleanup_result(cleaned: bool) -> void:
	initialization_cleanup_pending=false;initialization_cleanup_unknown=not cleaned
	if not initialized:_initialized(initialization_error)
	if cleaned:released=true;slots.stop_admission()

func retry_initialization_cleanup() -> void:
	if not initialization_error.is_empty() and initialization_cleanup_unknown and not initialization_cleanup_pending:RenderingServer.call_on_render_thread(_request_initialization_cleanup_render)

func submit_intent(request: Dictionary) -> Dictionary:
	if not _fault.is_empty():return {"accepted":false,"error":&"backend_failed"}
	if _closing:return {"accepted":false,"error":&"closing"}
	if not _ready:return {"accepted":false,"error":&"backend_unavailable"}
	if checkpoint_capture!=null:return {"accepted":false,"error":&"checkpoint_busy"}
	if _pending.size()>=MAX_PENDING:return {"accepted":false,"error":&"queue_full"}
	if _result_reservations>=MAX_RESULTS:return {"accepted":false,"error":&"results_backpressure"}
	var frozen:=I.freeze(_registry,request,_configuration.domain_id,_generation)
	if not frozen.error.is_empty():return {"accepted":false,"error":frozen.error}
	var error:=C.allows_intent(_configuration,frozen.value)
	if not error.is_empty():return {"accepted":false,"error":error}
	return _enqueue(frozen.value)

func submit_control(mode: Variant, identity: Dictionary) -> Dictionary:
	if not _fault.is_empty():return {"accepted":false,"error":&"backend_failed"}
	if _closing:return {"accepted":false,"error":&"closing"}
	if not _ready:return {"accepted":false,"error":&"backend_unavailable"}
	if checkpoint_capture!=null:return {"accepted":false,"error":&"checkpoint_busy"}
	if _pending.size()>=MAX_PENDING:return {"accepted":false,"error":&"queue_full"}
	if _result_reservations>=MAX_RESULTS:return {"accepted":false,"error":&"results_backpressure"}
	var converted:=Adapter.control(mode,identity)
	if not converted.error.is_empty():return {"accepted":false,"error":converted.error}
	if identity.domain_id!=_configuration.domain_id or identity.generation!=_generation:return {"accepted":false,"error":&"stale_generation_or_domain"}
	return _enqueue(converted.value)

func _enqueue(frozen: Dictionary) -> Dictionary:
	if frozen.command_id<=_highwater:return {"accepted":false,"error":&"non_monotonic_command_id"}
	if frozen.sim_tick<completed_tick:return {"accepted":false,"error":&"stale_tick"}
	if frozen.control_kind==0 and frozen.configuration.stroke_policy!=0:
		var buffered:=0
		for work in _pending:
			if work.kind==L.WorkKind.EDIT and work.command.stroke_id==frozen.stroke_id and work.command.control_kind==0:buffered+=1
		if buffered>=frozen.configuration.sampling.max_buffer_points:return {"accepted":false,"error":&"stroke_buffer_full"}
	_highwater=frozen.command_id
	_result_reservations+=1
	_reserved_ids[frozen.command_id]={"submitted":false}
	var at:=_pending.size()
	while frozen.control_kind==0 and at>0 and _pending[at-1].kind==L.WorkKind.EDIT and _pending[at-1].command.control_kind==0 and _pending[at-1].command.sim_tick>frozen.sim_tick:at-=1
	_pending.insert(at,{"kind":L.WorkKind.EDIT,"command":frozen.duplicate(true),"boundary_packets":boundary.packets()})
	if diagnostics!=null:diagnostics.mark(&"enqueue",frozen.command_id,{"control":frozen.control_kind,"pending":_pending.size()})
	return {"accepted":true,"error":&"","command_id":_highwater}

func submit_legacy(command: Dictionary, policy: Variant=3, speed: Variant=0.0) -> Dictionary:
	if _registry==null:return {"accepted":false,"error":&"backend_unavailable"}
	var adapted:=Adapter.adapt(_registry,command,StringName(_configuration.domain_id),_generation,policy,speed)
	if not adapted.error.is_empty():return {"accepted":false,"error":adapted.error}
	return submit_intent(adapted.request)

func submit_display_intent(request: Dictionary) -> Dictionary:
	if not _fault.is_empty():return {"accepted":false,"error":&"backend_failed"}
	if _closing or not _ready:return {"accepted":false,"error":&"backend_unavailable"}
	if checkpoint_capture!=null:return {"accepted":false,"error":&"checkpoint_busy"}
	if _pending.size()>=MAX_PENDING:return {"accepted":false,"error":&"queue_full"}
	if _result_reservations>=MAX_RESULTS:return {"accepted":false,"error":&"results_backpressure"}
	var frozen:=Display.freeze(request,_configuration,_generation)
	if not frozen.error.is_empty():return {"accepted":false,"error":frozen.error}
	var command: Dictionary=frozen.value
	if command.command_id<=_highwater:return {"accepted":false,"error":&"non_monotonic_command_id"}
	if command.sim_tick<completed_tick:return {"accepted":false,"error":&"stale_tick"}
	var reserved:=visuals.active_count
	for work in _pending:
		if work.kind==Display.WORK_KIND:reserved+=work.command.count
	for record in _records.values():
		if record.kind==Display.WORK_KIND:reserved+=record.commands[0].count
	if reserved+command.count>visuals.profile.capacity:return {"accepted":false,"error":&"gravel_capacity_full"}
	_highwater=command.command_id;_result_reservations+=1;_reserved_ids[_highwater]={"submitted":false}
	_pending.append({"kind":Display.WORK_KIND,"command":command,"boundary_packets":boundary.packets()})
	return {"accepted":true,"error":&"","command_id":_highwater}

func request_tick(dt: float) -> StringName:
	if not _fault.is_empty():return &"backend_failed"
	if _closing:return &"closing"
	if not _ready:return &"backend_unavailable"
	if checkpoint_capture!=null:return &"checkpoint_busy"
	if _pending.size()>=MAX_PENDING:return &"queue_full"
	if not is_finite(dt) or dt<=0.0 or dt>1.0/30.0+1e-9:return &"invalid_dt"
	_pending.append({"kind":L.WorkKind.WATER_TICK,"dt":dt,"boundary_packets":boundary.packets()})
	return &""

func request_wave(request: Dictionary) -> Dictionary:
	if not _fault.is_empty():return {"accepted":false,"error":&"backend_failed"}
	if _closing or not _ready:return {"accepted":false,"error":&"backend_unavailable"}
	if checkpoint_capture!=null:return {"accepted":false,"error":&"checkpoint_busy"}
	var floor_tick:=maxi(_scheduled_tick,completed_tick)
	for work in _pending:
		if work.kind==L.WorkKind.WATER_TICK:
			if floor_tick<L.INT64_MAX:floor_tick+=1
		else:floor_tick=maxi(floor_tick,work.command.sim_tick)
	return boundary.admit(request,completed_tick,floor_tick,advanced_time_s)

func cancel_pending(command_id: int) -> bool:
	if _checkpoint_end_ids.has(command_id):return false
	for index in _pending.size():
		if _pending[index].kind!=L.WorkKind.WATER_TICK and _pending[index].command.command_id==command_id:
			_pending.remove_at(index);_results[command_id]={"error":&"cancelled_before_recording","cancelled":true};return true
	return false

func pump() -> void:
	if not _ready or not _fault.is_empty():
		_checkpoint_progress();return
	if diagnostics!=null:diagnostics.mark(&"pump_begin",0,{"pending":_pending.size(),"active":active_count()})
	_poll()
	if not _fault.is_empty():
		_checkpoint_progress();return
	heights.pump()
	_checkpoint_progress()
	# All ready work may record ahead; no per-command CPU completion gate.
	while not _pending.is_empty():
		var acquired:=slots.acquire()
		if not acquired.error.is_empty():
			if diagnostics!=null:diagnostics.mark(&"slot_blocked",0,{"pending":_pending.size(),"states":slots._slots.map(func(value):return value.state)})
			if acquired.error==&"identity_exhausted":_fail(acquired.error)
			break
		var id: Dictionary=acquired.identity
		if diagnostics!=null:diagnostics.mark(&"batch_build",id.batch_seq,{"slot":id.slot_id})
		var kind: int=_pending[0].kind
		var commands: Array=[];var encoded: Array[PackedByteArray]=[];var dt:=0.0
		var wave_packets: Array=_pending[0].get("boundary_packets",boundary.packets()).duplicate()
		var implicit_tick: bool=kind!=L.WorkKind.WATER_TICK and _pending[0].command.sim_tick>_scheduled_tick
		if implicit_tick:kind=L.WorkKind.WATER_TICK;dt=1.0/30.0
		if kind==L.WorkKind.EDIT:
			while not _pending.is_empty() and _pending[0].kind==kind and _pending[0].command.sim_tick<=_scheduled_tick and commands.size()<L.MAX_COMMANDS:
				if not commands.is_empty() and _pending[0].command.command_id<=commands.back().command_id:break
				var frozen: Dictionary=_pending.pop_front().command
				commands.append(frozen);encoded.append(W.encode_command(frozen,_registry))
		elif kind==Display.WORK_KIND:
			commands.append(_pending.pop_front().command)
		else:
			if not implicit_tick:dt=_pending.pop_front().dt
			_scheduled_tick+=1
		var packet:=Display.pack(id,commands[0]) if kind==Display.WORK_KIND else (W.pack_batch(id,encoded) if kind==L.WorkKind.EDIT else W.pack_tick(id))
		if packet.is_empty() or not slots.queued(id,commands,kind).is_empty():
			slots.cancel_unsubmitted(id);_fail(&"internal_batch_invalid");return
		_records[id.batch_seq]={"identity":id.duplicate(true),"commands":commands.duplicate(true),"kind":kind,"booked":false}
		if diagnostics!=null:diagnostics.mark(&"batch_queued",id.batch_seq,{"kind":kind,"slot":id.slot_id,"commands":commands.map(func(value):return value.command_id)})
		RenderingServer.call_on_render_thread(_submit_render.bind(id,packet,kind,dt,wave_packets))
	if diagnostics!=null:diagnostics.mark(&"pump_end")

func _submit_render(id: Dictionary, packet: PackedByteArray, kind: int, dt: float, wave_packets: Array=[]) -> void:
	if diagnostics!=null:diagnostics.mark(&"submit_begin",id.batch_seq)
	if kind==L.WorkKind.WATER_TICK and boundary.enabled and not water.configure_boundary(water.tide,wave_packets):
		call_deferred("_submission_failed",id,{"recorded":false,"error":&"boundary_wave_upload"});return
	var decoded:=W.decode_batch(packet,id)
	var recorder: Callable=_record_work.bind(kind,dt,decoded.commands)
	if diagnostics!=null and state.profile_passes:state.rd.capture_timestamp("ue_batch_"+str(id.batch_seq)+"_start")
	var submitted:=transport.submit(id,packet,recorder,_arrived_render,_finish_work)
	if diagnostics!=null and state.profile_passes:state.rd.capture_timestamp("ue_batch_"+str(id.batch_seq)+"_end")
	if diagnostics!=null:diagnostics.mark(&"submit_end",id.batch_seq,{"recorded":submitted.recorded,"error":submitted.error})
	if submitted.recorded:call_deferred("_recording_known",id)
	if not submitted.error.is_empty():call_deferred("_submission_failed",id,submitted)

func _recording_known(id: Dictionary) -> void:
	if _records.has(id.batch_seq) and _records[id.batch_seq].identity==id:_book_record(_records[id.batch_seq])

func _book_record(record: Dictionary) -> void:
	if record.booked:return
	record.booked=true
	if record.kind!=Display.WORK_KIND:accounting.book_record(record.commands)
	for command in record.commands:
		if _reserved_ids.has(command.command_id):_reserved_ids[command.command_id].submitted=true

func _record_work(input: RID, control: RID, output: RID, count: int, kind: int, dt: float, commands: Array) -> void:
	heights.begin_work()
	if kind==L.WorkKind.EDIT:
		executor.record(input,control,output,count,commands);visuals.record_edit()
	elif kind==Display.WORK_KIND:visuals.record_display(input,commands[0])
	else:water.record_tick(input,control,output,count,dt)

func _finish_work() -> void:
	heights.finish_work()
	if state.profile_passes:state.rd.capture_timestamp("sandcastle_async_publish_start")
	state.publish_sand()
	views.publish()
	visuals.publish()
	if state.profile_passes:state.rd.capture_timestamp("sandcastle_async_publish_end")

func _arrived_render(bytes: PackedByteArray, id: Dictionary) -> void:
	if diagnostics!=null:diagnostics.mark(&"readback_callback",id.batch_seq)
	call_deferred("_receive",bytes,id)

func _receive(bytes: PackedByteArray, id: Dictionary) -> void:
	if diagnostics!=null:diagnostics.mark(&"receive_begin",id.batch_seq)
	arrival_order.append(id.batch_seq)
	if arrival_order.size()>128:arrival_order.pop_front()
	var error:=slots.completed(bytes,id)
	if diagnostics!=null:diagnostics.mark(&"receive_end",id.batch_seq,{"error":error})
	if not error.is_empty() and error not in [&"stale_lease",&"duplicate_or_wrong_state"]:_fail(error)

func _submission_failed(id: Dictionary, result: Dictionary) -> void:
	if result.recorded:slots.unknown(id,result.error)
	else:
		if _records.has(id.batch_seq):
			for command in _records[id.batch_seq].commands:
				if _checkpoint_end_ids.has(command.command_id):_checkpoint_end_ids.erase(command.command_id)
				else:_results[command.command_id]={"error":&"aborted_before_recording","cancelled":true,"submitted":false,"reason":result.error}
		slots.abandon_unrecorded(id);_records.erase(id.batch_seq)
	_fail(result.error)

func _poll() -> void:
	if hold_completions:return
	var batches:=_records.keys();batches.sort()
	for batch in batches:
		var record: Dictionary=_records[batch];var id: Dictionary=record.identity
		if slots.slot_snapshot(id.slot_id).state!=Slots.State.GPU_COMPLETE:
			if diagnostics!=null:diagnostics.mark(&"ordered_wait",id.batch_seq,{"states":slots._slots.map(func(value):return value.state)})
			break
		if diagnostics!=null:diagnostics.mark(&"consume_begin",id.batch_seq)
		var completion:=slots.consume(id)
		_book_record(record)
		var header: Dictionary=completion.header
		if header.state_seq<=completed_state_seq or header.sim_tick<completed_tick or header.revision<completed_revision:_fail(&"completion_regression");return
		completed_state_seq=header.state_seq;completed_tick=header.sim_tick;completed_revision=header.revision;advanced_time_s=header.advanced_time_s
		views.observe_complete(header)
		heights.notify_complete()
		for index in record.commands.size():
			var command: Dictionary=record.commands[index];var value: Dictionary=completion.results[index]
			if record.kind==Display.WORK_KIND:visuals.active_count=value.active_count
			else:accounting.settle(command,value)
			if _checkpoint_end_ids.has(command.command_id):
				_checkpoint_end_ids.erase(command.command_id)
				if checkpoint_capture!=null:checkpoint_capture.metadata.end_result=value.duplicate(true)
			else:_results[command.command_id]=value.duplicate(true)
		if diagnostics!=null:diagnostics.mark(&"settle_end",id.batch_seq,{"state_seq":completed_state_seq,"tick":completed_tick})
		RenderingServer.call_on_render_thread(_retire_render.bind(id))
		_records.erase(batch)

func _retire_render(id: Dictionary) -> void:
	if diagnostics!=null:diagnostics.mark(&"retire_render",id.batch_seq)
	call_deferred("_retired",id,transport.retire(id))

func _retired(id: Dictionary, success: bool) -> void:
	if not success or not slots.retired(id):_fail(&"retirement_failed")
	if diagnostics!=null:diagnostics.mark(&"slot_free",id.batch_seq,{"success":success,"fault":_fault})

func _fail(error: StringName) -> void:
	if _fault.is_empty():_fault=error
	slots.fail(error)
	if checkpoint_capture!=null:checkpoint_capture.cancel()

func fault_reason() -> StringName:return _fault
func active_count() -> int:return slots.active_count()
func pending_count() -> int:return _pending.size()
func result(command_id: int) -> Dictionary:return _results.get(command_id,{}).duplicate(true)

# A terminal result remains available until explicitly consumed. Admission
# reserves bounded space, so cancellation and GPU recording cannot lose results.
func take_result(command_id: int) -> Dictionary:
	if not _results.has(command_id):return {}
	var value: Dictionary=_results[command_id].duplicate(true)
	_results.erase(command_id);_reserved_ids.erase(command_id);_result_reservations-=1
	if diagnostics!=null:diagnostics.mark(&"result_taken",command_id,{"outcome":value.get("outcome",-1)})
	return value

func result_reservations() -> int:return _result_reservations

# Domain replacement may retire GPU resources before the UI claims outcomes.
# Transfer CPU terminal ownership explicitly; unknown recording stays unknown,
# never an invented GPU outcome or a replay permission.
func drain_closed_results() -> Dictionary:
	if not released:return {}
	var values: Dictionary=_results.duplicate(true)
	for id in _reserved_ids:
		if not values.has(id):values[id]={"error":&"recorded_result_unknown" if _reserved_ids[id].submitted else &"aborted_before_recording","unknown":bool(_reserved_ids[id].submitted),"submitted":bool(_reserved_ids[id].submitted),"generation":_generation,"command_id":id}
	_results.clear();_reserved_ids.clear();_result_reservations=0
	return values

func command_highwater() -> int:return _highwater

func ledger_snapshot() -> Dictionary:
	return {"precision":Checkpoint.PRECISION,"values":accounting.ledger.duplicate(true),"water_state_seq":accounting.water_state_seq,"initial_sand_total_m3":accounting.initial_sand_total_m3,"nominal_upper_supply":accounting.nominal_upper_supply}

func request_checkpoint(selection: Dictionary, callback: Callable, save_path: String="") -> Dictionary:
	if not _fault.is_empty():return {"accepted":false,"error":&"backend_failed"}
	if _closing:return {"accepted":false,"error":&"closing"}
	if not _ready:return {"accepted":false,"error":&"backend_unavailable"}
	if checkpoint_capture!=null:return {"accepted":false,"error":&"checkpoint_busy"}
	if not callback.is_valid():return {"accepted":false,"error":&"invalid_checkpoint_callback"}
	if not C.exact(selection,["policy","speed","brush"]) or typeof(selection.policy)!=TYPE_INT or selection.policy not in [0,1,2,3] or not Checkpoint.Old.number(selection.speed,-1.0,1.0):return {"accepted":false,"error":&"invalid_checkpoint_selection"}
	var error:=Checkpoint.Selection.selection_error(selection.brush)
	if not error.is_empty():return {"accepted":false,"error":error}
	error=C.validate(_configuration,true)
	if not error.is_empty():return {"accepted":false,"error":error}
	if state.prescribed_tide_boundary!=boundary.enabled or water.boundary_enabled!=boundary.enabled:return {"accepted":false,"error":&"checkpoint_boundary_state_mismatch"}
	if not save_path.is_empty() and FileAccess.file_exists(save_path):return {"accepted":false,"error":&"already_exists"}
	if checkpoint_serial==L.INT64_MAX:return {"accepted":false,"error":&"checkpoint_identity_exhausted"}
	checkpoint_serial+=1;_checkpoint_callback=callback;_checkpoint_path=save_path
	checkpoint_capture=Capture.new();checkpoint_capture.configure(self,selection,_checkpoint_captured)
	last_checkpoint_info={"capture_id":checkpoint_serial,"generation":_generation,"phase":&"draining","error":&""}
	return {"accepted":true,"error":&"","capture_id":checkpoint_serial}

func save_checkpoint(path: String, selection: Dictionary, callback: Callable) -> Dictionary:
	if path.is_empty():return {"accepted":false,"error":&"invalid_checkpoint_path"}
	return request_checkpoint(selection,callback,path)

func checkpoint_status() -> Dictionary:
	if checkpoint_capture==null:return last_checkpoint_info.duplicate(true)
	return {"capture_id":checkpoint_serial,"generation":_generation,"phase":checkpoint_capture.phase,"pending":checkpoint_capture.pending,"unknown":checkpoint_capture.unknown,"cancelled":checkpoint_capture.cancelled,"error":checkpoint_capture.error}

func retry_checkpoint_lifetime() -> void:
	if checkpoint_capture!=null:checkpoint_capture.retry_lifetime()

func cancel_checkpoint() -> bool:
	if checkpoint_capture==null:return false
	checkpoint_capture.cancel();return true

func _checkpoint_progress() -> void:
	if checkpoint_capture==null:return
	if not _fault.is_empty() or _closing:
		if not checkpoint_capture.scheduled:checkpoint_capture.finish_unrecorded(_fault if not _fault.is_empty() else &"closing")
		else:checkpoint_capture.cancel()
		return
	if checkpoint_capture.scheduled or not _pending.is_empty() or active_count()!=0:return
	if checkpoint_capture.cancelled:checkpoint_capture.finish_unrecorded(&"checkpoint_cancelled");return
	var error:=C.validate(_configuration,true)
	if not error.is_empty():checkpoint_capture.finish_unrecorded(error);return
	if not accounting.stroke.is_empty():
		if checkpoint_capture.metadata.has("end_id"):checkpoint_capture.finish_unrecorded(&"checkpoint_stroke_end_rejected");return
		if _highwater==L.INT64_MAX:checkpoint_capture.finish_unrecorded(&"identity_exhausted");return
		var control:=I.control(_configuration.domain_id,_generation,_highwater+1,completed_tick,L.ControlKind.END,accounting.stroke.stroke_id,accounting.stroke.baseline_token)
		if not control.error.is_empty():checkpoint_capture.finish_unrecorded(control.error);return
		_highwater+=1;_checkpoint_end_ids[_highwater]=true;checkpoint_capture.metadata.end_id=_highwater;checkpoint_capture.phase=&"ending_stroke"
		_pending.append({"kind":L.WorkKind.EDIT,"command":control.value});return
	var simulation: Dictionary=_configuration.simulation.duplicate(true);simulation.prescribed_tide_boundary=state.prescribed_tide_boundary
	checkpoint_capture.metadata.merge({"version":Checkpoint.VERSION,"protocol_family":C.FAMILY,"pipeline_protocol_version":L.VERSION,"grid_size":256,"cell_size_m":0.125,"domain_id":_configuration.domain_id,"generation":_generation,"state_seq":completed_state_seq,"sim_tick":completed_tick,"revision":completed_revision,"advanced_time_s":advanced_time_s,"highwater_id":_highwater,"ticket_id":maxi(accounting.ticket_floor,slots._lease_seq),"configuration":_configuration.duplicate(true),"simulation":simulation,"ledger_precision":Checkpoint.PRECISION,"ledger":accounting.ledger.duplicate(true),"initial_sand_total_m3":accounting.initial_sand_total_m3,"nominal_upper_supply":accounting.nominal_upper_supply,"cohesion_yield_height_m":state.cohesion_yield_height_m,"wave_requests":boundary.requests.duplicate(true),"wave_highwater_id":maxi(accounting.wave_highwater_id,boundary.highwater),"wave_start_times":boundary.start_times.duplicate(true),"boundary_packets":boundary.packets(),"visual_extensions":{"gravel_v1":{"version":2,"enabled":false}},"source_provenance":accounting.provenance.duplicate(true),"material_ever_used":accounting.material_ever_used,"inactive_foam":accounting.inactive_foam.duplicate(true)},true)
	checkpoint_capture.scheduled=true;checkpoint_capture.phase=&"scheduled";RenderingServer.call_on_render_thread(checkpoint_capture.render_capture)

func _checkpoint_captured(result: Dictionary) -> void:
	var capture=checkpoint_capture
	if result.error.is_empty() and (not _fault.is_empty() or _closing):result={"error":_fault if not _fault.is_empty() else &"closing"}
	if result.error.is_empty():result=capture.assemble(self,result.raw)
	if result.error.is_empty() and not _checkpoint_path.is_empty():
		result.error=Checkpoint.save(_checkpoint_path,result.checkpoint,_configuration)
		if result.error.is_empty():result.saved_path=_checkpoint_path
	last_checkpoint_info={"capture_id":checkpoint_serial,"generation":_generation,"phase":&"finished","error":result.error,"records":capture.records.duplicate(true),"registered":capture.registered,"end_id":capture.metadata.get("end_id",0),"end_result":capture.metadata.get("end_result",{}).duplicate(true),"state_seq":capture.metadata.get("state_seq",completed_state_seq),"highwater_id":_highwater}
	var callback:=_checkpoint_callback;_checkpoint_callback=Callable();checkpoint_capture=null;_checkpoint_path=""
	result.capture_id=checkpoint_serial
	if callback.is_valid():callback.call(result)

func close_admission() -> void:
	_closing=true # Existing accepted pending work still drains before stop slots.
	views.close_preview()
	if checkpoint_capture!=null:
		checkpoint_capture.cancel()
		if not checkpoint_capture.scheduled:checkpoint_capture.finish_unrecorded(&"closing")

func release_render() -> void:
	if not initialization_error.is_empty() and not released:call_deferred("_release_result",false);return
	if released:return
	if not _pending.is_empty() or slots.active_count()!=0:call_deferred("_release_result",false);return
	call_deferred("_release_result",_release_owners_render())

func _release_owners_render() -> bool:
	if transport.has_owned():return false
	if checkpoint_capture!=null or restore_verifier.pending!=0 or heights.active_count()!=0 or not views.can_release():return false
	if not views.release_if_idle():return false
	if not heights.release_if_idle():return false
	visuals.detach();water.release();coupled.release();executor.release();state.release()
	return transport.try_release()

func _release_result(success: bool) -> void:
	if success:slots.stop_admission();_ready=false;released=true
	else:_fail(&"release_while_owned")

func cleanup_fault() -> void:
	if _fault.is_empty():return
	_closing=true;_ready=false
	for work in _pending:
		if work.kind!=L.WorkKind.WATER_TICK:
			if _checkpoint_end_ids.has(work.command.command_id):_checkpoint_end_ids.erase(work.command.command_id)
			else:_results[work.command.command_id]={"error":&"aborted_before_recording","cancelled":true}
	_pending.clear()
	for index in L.WORK_SLOTS:
		var slot:=slots.slot_snapshot(index)
		if slot.state in [Slots.State.FREE,Slots.State.CPU_RECLAIM]:continue
		var id: Dictionary=slot.identity
		if slot.state==Slots.State.CPU_FILLING:slots.cancel_unsubmitted(id);continue
		if _cleanup_pending.has(id.lease_id):continue
		_cleanup_pending[id.lease_id]=id.duplicate(true)
		RenderingServer.call_on_render_thread(_cleanup_render.bind(id))

func _cleanup_render(id: Dictionary) -> void:
	transport.request_terminal(id,_terminal_render)

func _terminal_render(id: Dictionary, confirmed: bool) -> void:
	var retired: bool=confirmed and transport.retire(id)
	call_deferred("_cleanup_ack",id,retired)

func _cleanup_ack(id: Dictionary, confirmed: bool) -> void:
	_cleanup_pending.erase(id.lease_id)
	if not confirmed:return # Ownership retained; explicit retry may probe again.
	if slots.abort_after_retired(id,true):
		if _records.has(id.batch_seq):
			for command in _records[id.batch_seq].commands:_checkpoint_end_ids.erase(command.command_id)
		_records.erase(id.batch_seq)

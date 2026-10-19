extends Node3D

# Two scene-authored consumer slots. Only Pipeline owns authority and pumps work;
# this owner coordinates lifetime and changes the active slot in a physics phase.
const Pipeline=preload("res://tests/water_momentum_main/pipeline.gd")
const Intent=preload("res://scripts/simulation/unified_edit/intent.gd")
const Codec=preload("res://scripts/simulation/unified_edit/checkpoint_codec.gd")
const SOURCES=["res://tests/water_momentum_main/domain_runtime.gd","res://scripts/simulation/unified_edit/height_surface.gd","res://scenes/unified_edit_runtime.tscn","res://scenes/unified_edit_height_surface.tscn"]
var current
var candidate
var current_index:=-1
var candidate_index:=-1
var surfaces: Array=[]
var registry
var configuration: Dictionary={}
var bindings: Array=[]
var retired: Array[Dictionary]=[]
var terminal_archive: Dictionary={}
var phase: StringName=&"new"
var last_error: StringName=&""
var epoch_highwater:=0
var events: Array[Dictionary]=[]
var closing:=false
var closed:=false
var inject_candidate_initialization_after: StringName=&""
var inject_commit_validation_failure:=false
var _cancelled:=false
var _callback: Callable
var _release_pending: Dictionary={}
var _stage_attached:=false
var _discarding:=false

func _ready() -> void:surfaces=[get_node("SurfaceA"),get_node("SurfaceB")]

func _event(kind: StringName, detail: Dictionary={}) -> void:
	events.append({"kind":kind,"frame":Engine.get_process_frames(),"physics_frame":Engine.get_physics_frames(),"detail":detail.duplicate(true)})
	if events.size()>256:events.pop_front()

func boot(catalog, config: Dictionary, domain, material_bindings: Array, callback: Callable) -> StringName:
	if phase!=&"new" or surfaces.size()!=2:return &"runtime_already_started"
	for path in SOURCES:
		if config.get("sources",{}).get(path)!=FileAccess.get_sha256(path):return &"incomplete_runtime_owner_sources"
	if domain==null or not Intent.counter(domain.generation,1) or not callback.is_valid():return &"invalid_runtime_boot"
	var next:=Pipeline.new();var error:=next.configure(catalog,config,domain.generation)
	if not error.is_empty():return error
	registry=catalog;configuration=config.duplicate(true);bindings=material_bindings.duplicate(true);epoch_highwater=domain.generation
	candidate=next;candidate_index=0;_callback=callback;phase=&"building";_event(&"boot_build",{"generation":epoch_highwater})
	RenderingServer.call_on_render_thread(candidate.initialize_render.bind(domain));return &""

func restore_checkpoint(checkpoint: Dictionary, callback: Callable) -> StringName:
	if closing or current==null:return &"runtime_unavailable"
	if candidate!=null or not retired.is_empty() or current.checkpoint_capture!=null:return &"transition_busy"
	if not callback.is_valid():return &"invalid_transition_callback"
	var error:=Codec.validate(checkpoint,configuration)
	if not error.is_empty():return error
	var epoch:=Intent.next_identity(maxi(epoch_highwater,checkpoint.generation))
	if not epoch.error.is_empty():return epoch.error
	var next:=Pipeline.new();error=next.configure_restore(registry,configuration,epoch.value,checkpoint)
	if not error.is_empty():return error
	epoch_highwater=epoch.value;candidate=next;candidate_index=1-current_index;_callback=callback;_cancelled=false;_discarding=false;_stage_attached=false;last_error=&"";phase=&"building"
	candidate.inject_initialization_failure_after=inject_candidate_initialization_after
	_event(&"restore_build",{"from_generation":current._generation,"generation":epoch_highwater,"saved_state_seq":checkpoint.state_seq})
	RenderingServer.call_on_render_thread(candidate.initialize_render.bind(candidate.restore_domain()));return &""

func cancel_restore() -> bool:
	if candidate==null:return false
	_cancelled=true
	if not candidate.initialized:candidate.cancel_initialization()
	return true

func ready_for_input() -> bool:return not closing and current!=null and candidate==null and current._ready and current.fault_reason().is_empty()
func generation() -> int:return 0 if current==null else current._generation
func highwater() -> int:return 0 if current==null else current.command_highwater()

func submit_intent(value: Dictionary) -> Dictionary:
	if not ready_for_input():return {"accepted":false,"error":&"transition_busy"}
	if result_reservations()>=Pipeline.MAX_RESULTS:return {"accepted":false,"error":&"results_backpressure"}
	return current.submit_intent(value)

func submit_control(kind: Variant, value: Dictionary) -> Dictionary:
	if not ready_for_input():return {"accepted":false,"error":&"transition_busy"}
	if result_reservations()>=Pipeline.MAX_RESULTS:return {"accepted":false,"error":&"results_backpressure"}
	return current.submit_control(kind,value)

func submit_display_intent(value: Dictionary) -> Dictionary:
	if not ready_for_input():return {"accepted":false,"error":&"transition_busy"}
	if result_reservations()>=Pipeline.MAX_RESULTS:return {"accepted":false,"error":&"results_backpressure"}
	return current.submit_display_intent(value)

func result_reservations() -> int:
	var count: int=0 if current==null else current.result_reservations()
	for values in terminal_archive.values():count+=values.size()
	for row in retired:count+=row.pipeline.result_reservations()
	return count

func result(epoch: int, id: int) -> Dictionary:
	if current!=null and current._generation==epoch:return current.result(id)
	for row in retired:
		if row.pipeline._generation==epoch:return row.pipeline.result(id)
	return terminal_archive.get(epoch,{}).get(id,{}).duplicate(true)

func take_result(epoch: int, id: int) -> Dictionary:
	if current!=null and current._generation==epoch:return current.take_result(id)
	for row in retired:
		if row.pipeline._generation==epoch:return row.pipeline.take_result(id)
	var values: Dictionary=terminal_archive.get(epoch,{})
	var value: Dictionary=values.get(id,{}).duplicate(true)
	values.erase(id)
	if values.is_empty():terminal_archive.erase(epoch)
	return value

func request_tick(dt: float) -> StringName:
	return current.request_tick(dt) if ready_for_input() else &"transition_busy"

func request_wave(value: Dictionary) -> Dictionary:
	return current.request_wave(value) if ready_for_input() else {"accepted":false,"error":&"transition_busy"}

func save_checkpoint(path: String, selection: Dictionary, callback: Callable) -> Dictionary:
	if not ready_for_input():return {"accepted":false,"error":&"transition_busy"}
	return current.save_checkpoint(path,selection,callback)

func request_preview(value: Dictionary, callback: Callable, freshness: int=Pipeline.Views.Freshness.CURRENT) -> Dictionary:
	if not ready_for_input() or not callback.is_valid():return {"accepted":false,"error":&"transition_busy"}
	return current.views.request_preview(value,_preview_received.bind(current._generation,callback),current.completed_state_seq,freshness)

func invalidate_preview() -> void:
	if current!=null:current.views.invalidate_preview()

func retry_preview_readback() -> void:
	if current!=null:current.views.retry_preview_readback()

func request_probe(request: Dictionary, callback: Callable) -> Dictionary:
	if closing or current==null:return {"accepted":false,"error":&"closing"}
	if not ready_for_input():return {"accepted":false,"error":&"busy"}
	if not callback.is_valid():return {"accepted":false,"error":&"invalid_request"}
	return current.views.request_probe(request,_probe_received.bind(current._generation,callback))

func _probe_received(value: Dictionary, epoch: int, callback: Callable) -> void:
	if not callback.is_valid():return
	if current==null or current._generation!=epoch:value.error=&"stale_generation"
	callback.call(value)

func _preview_received(value: Dictionary, epoch: int, callback: Callable) -> void:
	if not callback.is_valid():return
	if current==null or current._generation!=epoch:callback.call({"error":&"stale_generation","generation":epoch});return
	callback.call(value)

func _process(_delta: float) -> void:
	if closed:return
	if current!=null:
		current.pump()
		# A failed old recorder cannot drain through ordinary pump. Recover its
		# leases with real terminal proof while the replacement is being built.
		if candidate!=null and not current.fault_reason().is_empty():current.cleanup_fault()
	if candidate!=null:
		candidate.pump();_advance_candidate()
	for row in retired:_advance_retired(row)
	for index in range(retired.size()-1,-1,-1):
		var row: Dictionary=retired[index]
		if row.pipeline.released:
			var terminal: Dictionary=row.pipeline.drain_closed_results()
			if not terminal.is_empty():terminal_archive[row.pipeline._generation]=terminal
			surfaces[row.index].clear_consumer();_release_pending.erase(row.pipeline.get_instance_id());_event(&"retired",{"generation":row.pipeline._generation});retired.remove_at(index)
	if closing and candidate==null and current==null and retired.is_empty():closed=true;phase=&"closed";_event(&"closed")

func _advance_candidate() -> void:
	if _cancelled and not candidate.initialized:candidate.cancel_initialization()
	if not candidate.initialized:return
	if not candidate.fault_reason().is_empty() or _cancelled or closing:
		if not _discarding:
			last_error=candidate.fault_reason() if not candidate.fault_reason().is_empty() else &"transition_cancelled"
			_discarding=true;_event(&"candidate_discard",{"error":last_error,"generation":candidate._generation})
		_discard_candidate();return
	if not _stage_attached:
		if not surfaces[candidate_index].prepare_consumer(candidate.heights):_reject_candidate(&"staging_surface_owned");return
		candidate.heights.proxy=surfaces[candidate_index];candidate.heights.notify_complete();_stage_attached=true;phase=&"preparing_physics"
	if _physical_ready(candidate,candidate_index):phase=&"commit_ready"

func _physical_ready(pipeline, index: int) -> bool:
	if pipeline.heights.active_count()!=0 or pipeline.heights.hinted or pipeline.heights.applied_state_seq.size()!=64:return false
	if surfaces[index].generation!=pipeline._generation or surfaces[index].applied_revisions.size()!=64:return false
	for chunk in 64:
		if pipeline.heights.applied_state_seq.get(chunk)!=pipeline.completed_state_seq or surfaces[index].applied_revisions.get(chunk)!=pipeline.completed_state_seq:return false
	return true

func _physics_process(_delta: float) -> void:
	if closing:
		for surface in surfaces:surface.set_collision_enabled(false)
		return
	if phase!=&"commit_ready" or candidate==null or _discarding:return
	if current!=null and (current.active_count()!=0 or current.pending_count()!=0 or current.checkpoint_capture!=null):return
	var error:=_validate_bindings(candidate)
	if inject_commit_validation_failure:error=&"injected_commit_preflight"
	if not error.is_empty():_reject_candidate(error);return
	var previous=current;var previous_index:=current_index
	# All validation finishes before any visible mutation. The old detach restores
	# baseline parameters synchronously; the new writer binds before frame draw.
	if previous!=null:previous.views.start_detach_bindings()
	for row in bindings:candidate.views.bind_material(row.material,row.parameters)
	if previous_index>=0:surfaces[previous_index].set_collision_enabled(false)
	surfaces[candidate_index].set_collision_enabled(true)
	current=candidate;current_index=candidate_index;candidate=null;candidate_index=-1;_stage_attached=false;phase=&"active"
	_event(&"commit",{"generation":current._generation,"state_seq":current.completed_state_seq,"previous_generation":0 if previous==null else previous._generation})
	if previous!=null:_retire(previous,previous_index,true)
	var callback:=_callback;_callback=Callable()
	if callback.is_valid():callback.call({"error":&"","generation":current._generation,"state_seq":current.completed_state_seq,"retirement_pending":not retired.is_empty()})

func _validate_bindings(pipeline) -> StringName:
	for row in bindings:
		if not row is Dictionary or row.size()!=2 or not row.get("material") is ShaderMaterial or not row.get("parameters") is Dictionary:return &"invalid_material_binding_plan"
		var error: StringName=pipeline.views.validate_material(row.material,row.parameters)
		if not error.is_empty():return error
	return &""

func _reject_candidate(error: StringName) -> void:last_error=error;_cancelled=true;_discarding=true;phase=&"discarding";_event(&"candidate_rejected",{"error":error})

func _discard_candidate() -> void:
	phase=&"discarding"
	if not candidate.initialization_error.is_empty():
		if not candidate.released:phase=&"unknown_candidate_cleanup";return
	else:
		candidate.close_admission();candidate.heights.close()
		if not candidate.fault_reason().is_empty():candidate.cleanup_fault()
		if candidate.heights.active_count()!=0 or candidate.active_count()!=0 or candidate.checkpoint_capture!=null:return
		if not candidate.views.can_release():
			if not candidate.views.detach_pending:candidate.views.start_detach_bindings()
			return
		_request_release(candidate)
		if not candidate.released:return
	var epoch: int=candidate._generation
	if _stage_attached:surfaces[candidate_index].clear_consumer()
	_release_pending.erase(candidate.get_instance_id());candidate=null;candidate_index=-1;_stage_attached=false;_discarding=false;_cancelled=false;phase=&"active" if current!=null else &"failed"
	var callback:=_callback;_callback=Callable();_event(&"discarded",{"generation":epoch,"error":last_error})
	if callback.is_valid():callback.call({"error":last_error,"generation":epoch})

func _retire(pipeline, index: int, detached_started: bool=false) -> void:
	pipeline.close_admission();pipeline.heights.close()
	if not detached_started:pipeline.views.start_detach_bindings()
	retired.append({"pipeline":pipeline,"index":index});_event(&"retire_started",{"generation":pipeline._generation})

func _advance_retired(row: Dictionary) -> void:
	var pipeline=row.pipeline
	pipeline.pump()
	if not pipeline.fault_reason().is_empty():pipeline.cleanup_fault()
	if pipeline.active_count()!=0 or pipeline.pending_count()!=0 or pipeline.heights.active_count()!=0 or pipeline.checkpoint_capture!=null or not pipeline.views.can_release():return
	pipeline.heights.proxy=null;_request_release(pipeline)

func _request_release(pipeline) -> void:
	if pipeline.released or _release_pending.has(pipeline.get_instance_id()):return
	_release_pending[pipeline.get_instance_id()]=true;RenderingServer.call_on_render_thread(pipeline.release_render)

func retry_retirement() -> void:
	# The front-end maintenance cadence also serves the live owner's readers.
	# A failed registration retains ownership until this same proof/read retries.
	if current!=null:
		current.retry_checkpoint_lifetime();current.heights.retry_readbacks();current.views.retry_preview_readback()
	if candidate!=null:
		candidate.retry_initialization_cleanup();candidate.retry_checkpoint_lifetime();candidate.heights.retry_readbacks();candidate.views.retry_preview_readback()
	for row in retired:
		row.pipeline.retry_checkpoint_lifetime();row.pipeline.heights.retry_readbacks();row.pipeline.views.retry_preview_readback()
		if not row.pipeline.views.detach_pending and not row.pipeline.views.detached_confirmed:row.pipeline.views.start_detach_bindings()

func shutdown() -> void:
	if closing:return
	closing=true;phase=&"closing";_cancelled=true
	if candidate!=null and not candidate.initialized:candidate.cancel_initialization()
	if current!=null:_retire(current,current_index);current=null;current_index=-1

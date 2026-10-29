extends "res://tests/edit_validation/beach_interaction_entry.gd"

const Store=preload("res://scripts/simulation/checkpoint_store.gd")
const Codec=preload("res://scripts/simulation/edit_validation/gpu_checkpoint_codec.gd")
var gpu_save_running := false
var legacy_command_running := false
var observe_legacy_boundaries := false
signal legacy_shadow_ready
signal legacy_patch_submitted
var inject_legacy_patch_failure_once := false
var source_signature := {}
const RestoreBundle=preload("res://scripts/simulation/edit_validation/beach_restore_bundle.gd")
var beach_restore_running := false
var beach_restore_candidate
var beach_restore_phase := "idle"
var beach_restore_commit_done := false
var inject_beach_restore_failure := false
var beach_restore_events := []
signal beach_restore_submitted
signal beach_restore_metadata_committed
signal beach_restore_published
signal beach_restore_collision_ready
var observe_beach_restore := false
var beach_restore_verifications := []

static func _index_sources(path: String, result: Dictionary) -> void:
	for directory in DirAccess.get_directories_at(path): _index_sources(path.path_join(directory),result)
	for file in DirAccess.get_files_at(path):
		if file.get_extension() in ["gd","glsl","gdshader","tscn","tres","json","png","jpg","webp"]:
			var full:=path.path_join(file);result[full]=FileAccess.get_sha256(full)

static func replay_capture_tick() -> int:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--beach-replay-capture-tick="): return clampi(arg.get_slice("=",1).to_int(),1,14)
	return 5

static func configuration_signature() -> Dictionary:
	var sources:= {}
	for path in ["res://scripts/simulation","res://scripts/visual","res://scripts/collision","res://scripts/water/reference","res://tests/edit_validation","res://tests/visual_water_alignment/prototypes","res://scenes","res://assets/test1_beach","res://shaders/simulation"]: _index_sources(path,sources)
	var driver: String=ProjectSettings.get_setting("rendering/rendering_device/driver.windows","default")
	var arguments:=OS.get_cmdline_args()
	var index:=arguments.find("--rendering-driver")
	if index>=0 and index+1<arguments.size(): driver=arguments[index+1]
	var trace_detail := 0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--beach-material-trace-detail-substep="): trace_detail=arg.get_slice("=",1).to_int()
	return {"skip_idle_components_requested":"--skip-idle-components" in OS.get_cmdline_user_args(),"bounded_collision_requested":"--beach-bounded-collision" in OS.get_cmdline_user_args(),"staged_slope_requested":"--beach-staged-slope" in OS.get_cmdline_user_args(),"slope_output_requested":"--beach-slope-output" in OS.get_cmdline_user_args(),"slope_counter_requested":"--beach-slope-counter" in OS.get_cmdline_user_args(),"slope_record_requested":"--beach-slope-record" in OS.get_cmdline_user_args(),"gpu_validation_requested":"--gpu-validation" in OS.get_cmdline_args(),"sources":sources,"engine":Engine.get_version_info(),"adapter":RenderingServer.get_video_adapter_name(),"driver":driver,"material_barriers":"--beach-material-barriers" in OS.get_cmdline_user_args(),"split_material_lists":"--beach-split-material-lists" in OS.get_cmdline_user_args(),"replay_capture_tick":replay_capture_tick(),"replay_capture":"--beach-replay-capture" in OS.get_cmdline_user_args(),"material_copy_fence":"--beach-material-copy-fence" in OS.get_cmdline_user_args(),"material_trace_continuation_only":"--beach-material-trace-continuation-only" in OS.get_cmdline_user_args(),"material_trace_detail_substep":trace_detail,"material_trace_commit_only":"--beach-material-trace-commit-only" in OS.get_cmdline_user_args(),"material_stage_trace":"--beach-material-stage-trace" in OS.get_cmdline_user_args(),"precise_slope":"--beach-precise-slope" in OS.get_cmdline_user_args(),"reuse_collision_shapes":"--reuse-collision-shapes" in OS.get_cmdline_user_args(),"cached_capacity":"--cached-capacity" in OS.get_cmdline_user_args(),"compensated_capacity":"--compensated-capacity" in OS.get_cmdline_user_args(),"prefetch_velocity":"--prefetch-velocity" in OS.get_cmdline_user_args(),"packed_runs":"--packed-runs" in OS.get_cmdline_user_args(),"connected_runs":"--connected-runs" in OS.get_cmdline_user_args(),"fast_full_wet":"--fast-full-wet" in OS.get_cmdline_user_args(),"profile_sha256":FileAccess.get_sha256("res://assets/test1_beach/test1_beach_release.json")}

static func validate_gpu_checkpoint(checkpoint: Dictionary, signature: Dictionary) -> StringName:
	var error:=BeachCodec.validate(checkpoint)
	if not error.is_empty(): return error
	var edit: Variant=checkpoint.get("gpu_beach_edit")
	if not edit is Dictionary or edit.get("version")!=2 or edit.get("configuration")!=signature or not edit.get("prefix") is Array or not edit.get("ledger") is Dictionary or edit.get("pending_count")!=0 or edit.get("reserved_m3")!=0.0: return &"invalid_beach_edit_header"
	var selection: Variant=edit.get("selection")
	if not selection is Dictionary or selection.get("policy") not in [0,1,2,3] or typeof(selection.get("speed")) not in [TYPE_FLOAT,TYPE_INT] or not is_finite(float(selection.speed)) or absf(float(selection.speed))>1.0: return &"invalid_beach_selection"
	if not checkpoint.command_ids.is_empty(): return &"invalid_beach_legacy_projection"
	var sidecar: Dictionary={"version":1,"fixture":"edit_recovery_numeric_v1","grid_size":256,"cell_size_m":0.125,"tick":checkpoint.tick,"generation":checkpoint.shadow.generation,"revision":checkpoint.revision,"highwater_id":checkpoint.highwater_id,"pending_count":0,"reserved_m3":0.0,"raw_fields":checkpoint.gpu_beach_native.fields,"ledger":edit.ledger,"prefix":edit.prefix,"visual_history":{}}
	error=Codec.validate(sidecar)
	if not error.is_empty(): return error
	for item in edit.prefix:
		if item.command.domain_id!=checkpoint.shadow.domain_id or not item.has("available_m3") or not item.has("execution_tick"): return &"invalid_beach_replay_input"
	for key in ["tool_inventory_m3","sand_source_m3","sand_sink_m3"]:
		if edit.ledger[key]!=checkpoint.shadow[key]: return &"invalid_beach_ledger_projection"
	for key in ["water_source_m3","water_sink_m3"]:
		if edit.ledger[key]!=checkpoint[key]: return &"invalid_beach_ledger_projection"
	return &""

func _ready() -> void:
	source_signature=configuration_signature()
	if not replay_checkpoint.is_empty():
		var error:=validate_gpu_checkpoint(replay_checkpoint,source_signature)
		if not error.is_empty(): last_error=String(error);push_error(last_error);return
		generation=maxi(generation,int(replay_checkpoint.shadow.generation)+1)
	super._ready()
	if not replay_checkpoint.is_empty() and last_error.is_empty():
		gpu_prefix=replay_checkpoint.gpu_beach_edit.prefix.duplicate(true)
		water_policy=replay_checkpoint.gpu_beach_edit.selection.policy;signed_speed_m_s=replay_checkpoint.gpu_beach_edit.selection.speed
		command_queue.applied_log.clear()
		for item in gpu_prefix:
			if item.result.status==1: command_queue.applied_log.append(item.command.duplicate(true))
		command_queue.last_command_id=replay_checkpoint.highwater_id
		input_serial=command_queue.last_command_id

func _start_checkpoint_capture() -> void:
	# Preserve the legacy SANDCP01 projection's empty int32/sorted command list.
	# Actual native identities and execution order live in the checksummed sidecar.
	var applied: Array[Dictionary]=command_queue.applied_log
	command_queue.applied_log=[];command_id=command_queue.last_command_id
	super._start_checkpoint_capture()
	command_queue.applied_log=applied
	if not checkpoint_capture.is_empty():
		var ledger:= {}
		for key in ["tool_inventory_m3","sand_source_m3","sand_sink_m3"]: ledger[key]=shadow_domain.get(key)
		ledger.water_source_m3=solver.water_source_m3;ledger.water_sink_m3=solver.water_sink_m3
		checkpoint_capture.gpu_beach_edit={"version":2,"configuration":source_signature.duplicate(true),"prefix":gpu_prefix.duplicate(true),"ledger":ledger,"selection":{"policy":water_policy,"speed":signed_speed_m_s},"pending_count":0,"reserved_m3":0.0}

func _checkpoint_field_ready(data: PackedByteArray, field: String, revision: int, token: int) -> void:
	var applied: Array[Dictionary]=command_queue.applied_log
	command_queue.applied_log=[]
	super._checkpoint_field_ready(data,field,revision,token)
	command_queue.applied_log=applied

func save_gpu_checkpoint(path: String) -> StringName:
	if legacy_command_running or gpu_save_running or shutdown_requested or closing or not ready_for_ticks or FileAccess.file_exists(path): return &"backend_unavailable"
	var was_playing:=playing;var was_accepting: bool=input_scheduler.accepting
	gpu_save_running=true;playing=false;input_scheduler.accepting=false;gpu_brush=&""
	while busy or input_running or input_scheduler.pumping: await get_tree().process_frame
	await input_scheduler.drain_due()
	if not command_queue.pending.is_empty() or input_scheduler.reserved_total()!=0.0: return _finish_gpu_save(&"pending_commands",was_playing,was_accepting)
	# Parent save freezes the original ledger/shadow and all visual histories.
	pending_save_path=path;last_save_error=&"";_start_checkpoint_capture()
	while not pending_save_path.is_empty() and last_error.is_empty() and not closing: await get_tree().process_frame
	var result: StringName=last_save_error if last_error.is_empty() else &"capture_failed"
	if not result.is_empty():
		while pending_beach_native_readbacks>0: await get_tree().process_frame
		checkpoint_capture_pending=false;pending_save_path="";checkpoint_capture.clear()
	return _finish_gpu_save(result,was_playing,was_accepting)

func _finish_gpu_save(error: StringName, was_playing: bool, was_accepting: bool) -> StringName:
	gpu_save_running=false
	if not closing and not shutdown_requested and last_error.is_empty(): playing=was_playing;input_scheduler.accepting=was_accepting
	elif not last_error.is_empty(): ready_for_ticks=false;playing=false;input_scheduler.accepting=false
	return error

func _process(delta: float) -> void:
	if legacy_command_running: return
	super._process(delta)

func apply_legacy_command(command: Dictionary) -> Dictionary:
	if not last_error.is_empty(): return {"error":"backend_failed"}
	if gpu_save_running or beach_restore_running or legacy_command_running: return {"error":"checkpoint_busy"}
	if busy or input_running or shutdown_requested or closing or not ready_for_ticks or not command_queue.pending.is_empty(): return {"error":"backend_unavailable"}
	if command.get("kind") not in [&"smooth",&"compact"] or typeof(command.get("sim_tick"))!=TYPE_INT or command.sim_tick!=completed_ticks: return {"error":"invalid_command"}
	command=command.duplicate(true)
	var finite: Dictionary=command.duplicate(false)
	if not finite.has("amount_m3"): finite.amount_m3=0.0
	if not Protocol.finite_command(finite): return {"error":"invalid_command"}
	var was_playing:=playing;var accepting: bool=input_scheduler.accepting
	legacy_command_running=true;playing=false;input_scheduler.accepting=false
	var stock: float=shadow_domain.tool_inventory_m3
	# Both material half fields must come from the same completed GPU revision.
	_request_shadow_sync("legacy_cpu")
	while not shadow_sync_reason.is_empty() and last_error.is_empty() and not closing: await get_tree().process_frame
	var result: Dictionary={"error":"closed"}
	if not closing and last_error.is_empty():
		if observe_legacy_boundaries: legacy_shadow_ready.emit()
		var error: StringName=command_queue.submit(command)
		if not error.is_empty(): result={"error":String(error)}
		else:
			var before_sand: PackedFloat32Array=shadow_domain.sand.duplicate()
			var before_compaction: PackedFloat32Array=shadow_domain.compaction.duplicate()
			var before_applied: Array[Dictionary]=command_queue.applied_log.duplicate()
			var before_undo: Array[Dictionary]=command_queue.undo_stack.duplicate()
			var before_redo: Array[Dictionary]=command_queue.redo_stack.duplicate()
			var before_revision: int=solver.state_revision
			var results: Array[Dictionary]=command_queue.apply_due_commands(completed_ticks)
			result={"results":results}
			var patch: Dictionary=_patch_for_results(results)
			if patch.count>0:
				# Exercise the solver's real size validation before any GPU submission.
				if inject_legacy_patch_failure_once:
					inject_legacy_patch_failure_once=false;patch.data=PackedByteArray()
				_dispatch_paused_patch_data(patch)
				if observe_legacy_boundaries: legacy_patch_submitted.emit()
				while tick_pending and last_error.is_empty() and not closing: await get_tree().process_frame
			if last_error=="paused tool patch dispatch failed" and solver.state_revision==before_revision:
				# dispatch_tool_patch returns false only before recording compute work.
				# Keep the admitted ID consumed, but discard provisional CPU application.
				shadow_domain.sand=before_sand;shadow_domain.compaction=before_compaction
				command_queue.applied_log=before_applied;command_queue.undo_stack=before_undo;command_queue.redo_stack=before_redo
			if results.size()==1 and last_error.is_empty():
				var legacy: Dictionary=results[0]
				var envelope: Dictionary={"command_id":command.command_id,"generation":generation,"status":1 if legacy.status==&"applied" else 2,"applied_tick":completed_ticks,"legacy_result":legacy.duplicate(true)}
				gpu_prefix.append({"backend":"legacy_cpu","command":command.duplicate(true),"result":envelope,"policy":0,"speed":0.0,"available_m3":stock,"stock_before":stock,"execution_tick":completed_ticks})
				if legacy.status==&"applied" and not closing:
					var neighbors:=PackedInt32Array()
					for chunk in legacy.dirty_chunks:
						for dz in range(-1,2):
							for dx in range(-1,2):
								var x: int=chunk%8+dx;var z: int=chunk/8+dz;var id: int=z*8+x
								if x>=0 and x<8 and z>=0 and z<8 and id not in neighbors: neighbors.append(id)
					for chunk in neighbors: collision_needed[chunk]=solver.state_revision
					if not collision_proxy.apply_shadow_chunks(neighbors,solver.state_revision,generation,shadow_domain.rock,shadow_domain.sand): _fail("legacy neighbor collision update failed")
					tool_revision_by_command_id[command.command_id]=solver.state_revision
					await get_tree().physics_frame;await get_tree().physics_frame
	legacy_command_running=false
	if not last_error.is_empty(): ready_for_ticks=false;playing=false;input_scheduler.accepting=false
	if not closing and not shutdown_requested and last_error.is_empty(): playing=was_playing;input_scheduler.accepting=accepting
	return result if last_error.is_empty() else {"error":last_error}

func apply_gpu_command(command: Dictionary) -> Dictionary:
	if gpu_save_running or beach_restore_running or legacy_command_running: return {"error":"checkpoint_busy"}
	if not last_error.is_empty(): return {"error":"backend_failed"}
	return await super.apply_gpu_command(command)

func _start_tick() -> void:
	if gpu_save_running or beach_restore_running or legacy_command_running or not last_error.is_empty(): return
	super._start_tick()

func shutdown() -> void:
	shutdown_requested=true
	if input_scheduler!=null: input_scheduler.accepting=false
	while gpu_save_running or beach_restore_running or legacy_command_running: await get_tree().process_frame
	await super.shutdown()

func restore_gpu_checkpoint(path: String) -> StringName:
	var loaded:=Store.load(path)
	if not loaded.error.is_empty(): return loaded.error
	return await restore_gpu_checkpoint_data(loaded.checkpoint)

func restore_gpu_checkpoint_data(checkpoint: Dictionary) -> StringName:
	if legacy_command_running or gpu_save_running or beach_restore_running or shutdown_requested or closing or not ready_for_ticks or busy or input_running or input_scheduler.pumping: return &"backend_unavailable"
	if playing: return &"requires_pause"
	if not command_queue.pending.is_empty() or input_scheduler.reserved_total()!=0.0: return &"pending_commands"
	# Retain a private, immutable transaction input across asynchronous build.
	checkpoint=checkpoint.duplicate(true)
	var error:=Store._validate({"format_version":Store.FORMAT_VERSION,"enable_erosion":enable_erosion,"checkpoint":checkpoint,"prefix_commands":[]})
	if error.is_empty(): error=validate_gpu_checkpoint(checkpoint,source_signature)
	if not error.is_empty(): return error
	# This bundle implements the current complete release profile. Reject other
	# optional histories before touching the active branch.
	if enable_structures or prototype_rise_front_field or prototype_contact_history_field or prototype_batched_ledger_bookkeeping or prototype_ledger_ring_capacity>0 or prototype_ledger_batch_ticks>0 or not prototype_local_front_field or not enable_erosion: return &"unsupported_restore_profile"
	var accepting_before: bool=input_scheduler.accepting
	beach_restore_running=true;input_scheduler.accepting=false;gpu_brush=&"";ready_for_ticks=false
	beach_restore_phase="building"
	while collision_proxy.staging_texture.is_valid() or not collision_proxy.pending_revisions.is_empty() or pending_beach_native_readbacks>0: await get_tree().process_frame
	var candidate_domain:=Domain.new(GRID_SIZE,CELL_SIZE_M)
	if not candidate_domain.restore(checkpoint.shadow): return _finish_beach_restore(&"invalid_checkpoint_shadow",accepting_before)
	var next_generation: int=maxi(generation,int(checkpoint.shadow.generation))+1
	candidate_domain.generation=next_generation
	beach_restore_candidate=RestoreBundle.new()
	RenderingServer.call_on_render_thread(_render_beach_restore_build.bind(checkpoint,candidate_domain))
	while not beach_restore_candidate.done or beach_restore_candidate.pending>0: await get_tree().process_frame
	error=beach_restore_candidate.error
	beach_restore_verifications.append({"expected":beach_restore_candidate.expected.size(),"observed":beach_restore_candidate.observed.size(),"pending":beach_restore_candidate.pending,"error":String(error)})
	if inject_beach_restore_failure:
		inject_beach_restore_failure=false
		if error.is_empty(): error=&"candidate_injected_failure"
	if shutdown_requested: error=&"closed_before_restore_commit"
	if not error.is_empty():
		RenderingServer.call_on_render_thread(_render_beach_restore_discard)
		while not beach_restore_candidate.released: await get_tree().process_frame
		beach_restore_candidate=null
		return _finish_beach_restore(error,accepting_before)
	# No new input or ticks can observe the metadata/publication interval.
	beach_restore_phase="metadata_committed"
	generation=next_generation;shadow_domain=candidate_domain;completed_ticks=checkpoint.tick
	command_queue=CommandQueue.new(shadow_domain);command_queue.last_command_id=checkpoint.highwater_id
	gpu_prefix=checkpoint.gpu_beach_edit.prefix.duplicate(true)
	for item in gpu_prefix:
		if item.result.status==1: command_queue.applied_log.append(item.command.duplicate(true))
	input_scheduler=Scheduler.new(self);input_scheduler.accepting=false;input_serial=command_queue.last_command_id
	water_policy=checkpoint.gpu_beach_edit.selection.policy;signed_speed_m_s=checkpoint.gpu_beach_edit.selection.speed
	wave_requests.clear()
	for original in checkpoint.wave_requests:
		var wave: Dictionary=original.duplicate(true);wave.generation=generation;wave_requests.append(wave)
	wave_highwater_id=checkpoint.wave_highwater_id
	sand_cohesion_yield_height_m=checkpoint.sand_cohesion_yield_height_m
	support_loss_highwater_id=checkpoint.get("support_loss_highwater_id",0);support_loss_events.clear();support_loss_applied_id=0
	for original in checkpoint.get("support_loss_events",[]):
		var event: Dictionary=original.duplicate(true);event.generation=generation;support_loss_events.append(event);support_loss_applied_id=maxi(support_loss_applied_id,int(event.request_id))
	accumulator=0.0;replay_target_tick=-1;replay_checkpoint.clear();replay_ready=false;replay_collision_requested=false
	shadow_revision=checkpoint.revision;shadow_sand_revision=checkpoint.revision
	collision_needed.clear();input_events.clear();input_results.clear();input_rejections.clear()
	beach_restore_commit_done=false
	if observe_beach_restore: beach_restore_metadata_committed.emit()
	RenderingServer.call_on_render_thread(_render_beach_restore_commit)
	while not beach_restore_commit_done: await get_tree().process_frame
	if not last_error.is_empty(): return _finish_beach_restore(&"restore_commit_failed",false)
	collision_proxy.applied_revisions.clear();collision_proxy.applied_usec.clear();collision_proxy.applied_stage_usec.clear()
	var chunks:=PackedInt32Array();for chunk in 64: chunks.append(chunk)
	if not collision_proxy.apply_shadow_chunks(chunks,solver.state_revision,generation,checkpoint.gpu_beach_native.fields.rock.to_float32_array(),checkpoint.gpu_beach_native.fields.sand.to_float32_array()):
		_fail("full beach restore collision failed");return _finish_beach_restore(&"collision_restore_failed",false)
	set_visual_time(float(completed_ticks)/30.0)
	if observe_beach_restore: beach_restore_collision_ready.emit()
	await get_tree().physics_frame;await get_tree().physics_frame
	beach_restore_candidate=null;beach_restore_phase="complete"
	return _finish_beach_restore(&"closed_after_restore_commit" if shutdown_requested else &"",accepting_before)

func _render_beach_restore_build(checkpoint: Dictionary, candidate_domain) -> void:
	if not beach_restore_candidate.build(self,checkpoint,candidate_domain): beach_restore_candidate.error=&"candidate_build_failed"
	beach_restore_candidate.done=true
	if observe_beach_restore: call_deferred("_notify_beach_restore_submitted")

func _notify_beach_restore_submitted() -> void: beach_restore_submitted.emit()

func _beach_restore_field(bundle, bytes: PackedByteArray, key: String) -> void: bundle.record(bytes,key)

func _render_beach_restore_discard() -> void: beach_restore_candidate.release()

func _render_beach_restore_commit() -> void:
	var old=RestoreBundle.new()
	old.solver=solver;old.foam_field=foam_field;old.local_front_field=local_front_field;old.sand_audit=sand_audit;old.sediment_coupler=sediment_coupler;old.material_coupler=material_coupler;old.stable_q=stable_q
	old.collision={"shader":collision_proxy.shader,"pipeline":collision_proxy.pipeline,"chunk_buffer":collision_proxy.chunk_buffer,"uniform_set":collision_proxy.uniform_set}
	var candidate=beach_restore_candidate
	solver=candidate.solver;foam_field=candidate.foam_field;local_front_field=candidate.local_front_field;sand_audit=candidate.sand_audit;sediment_coupler=candidate.sediment_coupler;material_coupler=candidate.material_coupler;stable_q=candidate.stable_q
	collision_proxy.solver=solver;collision_proxy.rd=solver.rd;collision_proxy.generation=generation
	collision_proxy.shader=candidate.collision.shader;collision_proxy.pipeline=candidate.collision.pipeline;collision_proxy.chunk_buffer=candidate.collision.chunk_buffer;collision_proxy.uniform_set=RID()
	native_restore_complete=true
	_publish_textures()
	old.release()
	candidate.solver=null;candidate.foam_field=null;candidate.local_front_field=null;candidate.sand_audit=null;candidate.sediment_coupler=null;candidate.material_coupler=null;candidate.stable_q={};candidate.collision={}
	beach_restore_phase="published"
	call_deferred("_beach_restore_committed")

func _beach_restore_committed() -> void:
	beach_restore_commit_done=true
	if observe_beach_restore: beach_restore_published.emit()

func _finish_beach_restore(error: StringName, accepting_before: bool) -> StringName:
	beach_restore_running=false
	ready_for_ticks=not shutdown_requested and not closing and last_error.is_empty()
	input_scheduler.accepting=accepting_before and ready_for_ticks
	beach_restore_events.append({"error":String(error),"phase":beach_restore_phase,"generation":generation,"tick":completed_ticks})
	return error









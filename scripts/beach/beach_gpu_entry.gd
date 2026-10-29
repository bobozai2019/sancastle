extends "res://scripts/beach/beach_checkpoint_entry.gd"

const ReleaseConfig=preload("res://scripts/beach/release_config.gd")
const Protocol=preload("res://scripts/simulation/edit_validation/edit_protocol.gd")
var edit_spirvs: Array[RDShaderSPIRV]=[]
var water_spirvs: Array[RDShaderSPIRV]=[]
var gpu_busy := false
@export_range(1, 3, 1) var edit_physics_wait_count := 2
@export var edit_tick_overlap_enabled := false
@export var edit_frame_pipeline_enabled := false
@export_range(1,64,1) var edit_frame_batch_limit := 8
var frame_pipeline
var edit_overlap_window_open := false
var edit_overlap_ticks_started := 0
@export var unrestricted_sand_tools := false
@export_enum("保持水深", "保守位移", "速度响应", "位移与速度") var water_policy := 3
@export_range(-1.0, 1.0, 0.05) var signed_speed_m_s := 0.25
var ticket_id := 0
var pending_gpu_command := {}
var pending_gpu_revision := -1
var gpu_receipt := {}
var gpu_receipt_raw := PackedByteArray()
var gpu_settled := false
var gpu_published := false
var gpu_events := []
const DIAGNOSTIC_HISTORY_LIMIT := 128

func _record_diagnostic(history: Array, item: Dictionary) -> void:
	history.append(item)
	if history.size() > DIAGNOSTIC_HISTORY_LIMIT: history.pop_front()
var observe_gpu_wait_phases := false
var gpu_wait_phases := []

func _record_gpu_wait_phase(phase: String) -> void:
	if observe_gpu_wait_phases:
		gpu_wait_phases.append({"phase":phase,"at_us":Time.get_ticks_usec(),"command_id":pending_gpu_command.get("command_id",-1),"tick":completed_ticks,"revision":solver.state_revision,"physics_frame":Engine.get_physics_frames(),"collision_replace_ms":collision_proxy.last_replace_ms})

var gpu_prefix := []
var stable_q := {}
var collision_needed := {}
var shutdown_requested := false
var gpu_release_done := false
var gpu_release_us := -1
var observe_coupled_parameters := false
var coupled_parameter_trace := []
var compiled_shader_identity := []
var defer_shader_identity := false

func _ready() -> void:
	collision_proxy.reuse_chunk_shapes=false
	for group in [["sand_prepare","sand_reduce","sand_apply","sand_commit","sand_publish"],["water_prepare","water_displace","water_merge_receipt","water_commit","water_publish","water_velocity_apply","water_velocity_reduce","water_full_wet"]]:
		for name in group:
			var selected: String=ReleaseConfig.SHADERS.get(name,name)
			var file: RDShaderFile=load("res://shaders/simulation/edit_validation/"+selected+".glsl")
			if file==null: _fail("beach edit shader missing");return
			var spirv:=file.get_spirv()
			if not spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE).is_empty(): _fail("beach edit shader compile");return
			if name.begins_with("sand"): edit_spirvs.append(spirv)
			else: water_spirvs.append(spirv)
	super._ready()
	if not defer_shader_identity: collect_compiled_shader_identity()

func collect_compiled_shader_identity() -> void:
	compiled_shader_identity.clear()
	for code in spirvs+edit_spirvs+water_spirvs:
		var bytes: PackedByteArray=code.call("get_stage_bytecode",RenderingDevice.SHADER_STAGE_COMPUTE)
		var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(bytes)
		compiled_shader_identity.append(hash.finish().hex_encode())

func _dispatch_coupled_substep(delta_s: float) -> bool:
	if observe_coupled_parameters:
		coupled_parameter_trace.append({"tick":completed_ticks,"revision":solver.state_revision,"index":solver.current_index,"delta_s":delta_s,"cell_size_m":solver.cell_size_m,"cohesion":material_coupler.cohesion_yield_height_m})
	return super._dispatch_coupled_substep(delta_s)

func replay_parameter_evidence() -> Dictionary:
	var pushes: Array=[]
	if material_coupler!=null and "push_trace" in material_coupler:
		for item in material_coupler.push_trace:
			pushes.append({"revision":item.revision,"index":item.index,"stage":str(item.stage),"bytes_hex":item.bytes.hex_encode()})
	return {"substeps":coupled_parameter_trace.duplicate(true),"material_pushes":pushes,"compiled_shader_sha256":compiled_shader_identity.duplicate()}

func _create_solver() -> SandcastleGpuShallowSolver:
	var editor=_make_gpu_editor()
	editor.edit_spirvs=edit_spirvs;editor.water_spirvs=water_spirvs;editor.local_dispatch=true
	editor.fast_full_wet="--fast-full-wet" in ReleaseConfig.ARGUMENTS or "--connected-runs" in ReleaseConfig.ARGUMENTS or "--packed-runs" in ReleaseConfig.ARGUMENTS
	if "--compensated-capacity" in ReleaseConfig.ARGUMENTS and not "--packed-runs" in ReleaseConfig.ARGUMENTS: editor.fast_full_wet=false
	editor.profile_passes="--profile-edit-passes" in ReleaseConfig.ARGUMENTS
	editor.connected_runs="--connected-runs" in ReleaseConfig.ARGUMENTS or "--packed-runs" in ReleaseConfig.ARGUMENTS
	return editor

func _make_gpu_editor():
	return preload("res://scripts/simulation/edit_validation/gpu_water_editor.gd").new()

func _create_material_coupler() -> SandcastleGpuMaterialCoupler:
	return preload("res://scripts/simulation/edit_validation/staged_slope_coupler.gd").new()

func _material_trace_record(bytes: PackedByteArray, key: Variant) -> void:
	material_coupler.trace.record_data(bytes,key)

func _read_material_trace() -> void:
	material_coupler.trace.read(self,solver,&"_material_trace_record")

func collect_material_trace() -> Dictionary:
	RenderingServer.call_on_render_thread(_read_material_trace)
	await get_tree().process_frame
	while material_coupler.trace.pending>0 or material_coupler.trace.data.size()<material_coupler.trace.records.size(): await get_tree().process_frame
	return {"data":material_coupler.trace.data.duplicate(true),"metadata":material_coupler.metadata.duplicate(true)}

func _process(delta: float) -> void:
	if frame_pipeline!=null:frame_pipeline.poll()
	if gpu_busy:
		if playing: accumulator=minf(accumulator+delta,SIM_DELTA*4.0)
		_try_edit_overlap_tick()
		return
	super._process(delta)

func _try_edit_overlap_tick() -> void:
	if frame_pipeline!=null and frame_pipeline.submitting:return
	if not edit_tick_overlap_enabled or not edit_overlap_window_open or not playing or tick_pending or accumulator<SIM_DELTA: return
	if not ready_for_ticks or closing or shutdown_requested or checkpoint_capture_pending or sand_prefetch_in_flight or not shadow_sync_reason.is_empty() or not last_error.is_empty(): return
	if pending_gpu_command.is_empty() or pending_gpu_command.get("schema_version",1)!=1: return
	if solver==null or solver.receipt_pending or solver.publication_pending: return
	# These owners add their own transactions above this base class. Respect
	# them without replacing the current playable/brush/gravel inheritance.
	for flag in ["gpu_save_running","beach_restore_running","legacy_command_running","gravel_drop_pending"]:
		if flag in self and bool(get(flag)): return
	if "shape_stroke_id" in self and int(get("shape_stroke_id"))!=0: return
	accumulator-=SIM_DELTA
	tick_pending=true;water_tick_in_flight=true;tide_ready=false;cfl_ready=false;finish_dispatched=false
	var level: float=Scenarios.tide_level(float(completed_ticks)*SIM_DELTA)
	var wave_height_m:=_wave_height_at_tick(completed_ticks+1)
	edit_overlap_ticks_started+=1
	RenderingServer.call_on_render_thread(_render_begin_tick.bind(level+wave_height_m,wave_height_m,PackedByteArray(),0,PackedInt32Array(),PackedInt32Array(),generation))

func _start_tick() -> void:
	if gpu_busy or shutdown_requested or frame_collision_pending(): return
	super._start_tick()

func frame_collision_pending() -> bool:
	return frame_pipeline!=null and not frame_pipeline.pending.is_empty()

func can_submit_frame_batch() -> bool:
	if not edit_frame_pipeline_enabled or not unrestricted_sand_tools or solver==null or not solver.has_method("dispatch_receipt_batch"):return false
	if gpu_busy or tick_pending or checkpoint_capture_pending or sand_prefetch_in_flight or not shadow_sync_reason.is_empty() or closing or shutdown_requested or not ready_for_ticks or not last_error.is_empty():return false
	# Pending requests must snapshot their revision before the next GPU write.
	# The active staging texture already owns an immutable GPU snapshot.
	if not collision_proxy.pending_revisions.is_empty():return false
	if "shape_stroke_id" in self and int(get("shape_stroke_id"))!=0:return false
	for flag in ["legacy_command_running","beach_restore_running","gravel_drop_pending"]:
		if flag in self and bool(get(flag)):return false
	if frame_pipeline==null:frame_pipeline=preload("res://scripts/simulation/edit_validation/frame_pipeline/controller.gd").new(self)
	return true

func execute_gpu_frame_batch(count: int, configurations: Array) -> Dictionary:
	if not can_submit_frame_batch():return {"error":"backend_unavailable","results":[]}
	return await frame_pipeline.execute(count,configurations)

func request_checkpoint_save(path: String) -> StringName:
	if gpu_busy or shutdown_requested: return &"save_busy"
	# The native envelope must eventually carry this complete execution prefix.
	if not gpu_prefix.is_empty(): return &"gpu_beach_prefix_not_serialized"
	return super.request_checkpoint_save(path)

func _publish_textures() -> void:
	if replay_checkpoint.has("gpu_beach_native") and not native_restore_complete: return
	if not solver._may_publish(): return
	solver.publish_sand()
	for field in ["momentum_x","momentum_z"]:
		if not stable_q.has(field): stable_q[field]=solver._create_texture(RenderingDevice.DATA_FORMAT_R32_SFLOAT,PackedByteArray())
		if solver.rd.texture_copy(solver.current_texture(field),stable_q[field],Vector3.ZERO,Vector3.ZERO,Vector3(GRID_SIZE,GRID_SIZE,1),0,0,0,0)!=OK: call_deferred("_fail","beach stable momentum publication failed");return
	super._publish_textures()
	sand_texture.texture_rd_rid=solver.published_sand;water_texture.texture_rd_rid=solver.published_water
	momentum_x_texture.texture_rd_rid=stable_q.momentum_x;momentum_z_texture.texture_rd_rid=stable_q.momentum_z

func apply_gpu_command(command: Dictionary) -> Dictionary:
	if frame_collision_pending():return {"error":"backend_unavailable"}
	if gpu_busy or shutdown_requested or closing or not ready_for_ticks or tick_pending or checkpoint_capture_pending or not command_queue.pending.is_empty() or not shadow_sync_reason.is_empty() or sand_prefetch_in_flight: return {"error":"backend_unavailable"}
	if command.get("sand_destination") == "suspended_v1" and (not unrestricted_sand_tools or not enable_erosion): return {"error":"backend_unavailable"}
	if not Protocol.finite_command(command) or command.get("kind") not in [&"place_sand",&"remove_sand"] or command.get("sim_tick")!=completed_ticks or not is_finite(signed_speed_m_s) or absf(signed_speed_m_s)>1.0 or water_policy not in [0,1,2,3]: return {"error":"invalid_command"}
	var error: StringName=command_queue.submit(command)
	if not error.is_empty(): return {"error":String(error)}
	return await execute_admitted_gpu_command(command,sand_command_available(command))

func sand_command_available(command: Dictionary) -> float:
	# External editing supplies only this request; there is no virtual bucket.
	if unrestricted_sand_tools:
		return maxf(0.0, float(command.amount_m3) * float(command.strength)) + Protocol.LEGACY_EPS
	return shadow_domain.tool_inventory_m3

func execute_admitted_gpu_command(command: Dictionary, available_m3: float) -> Dictionary:
	if gpu_busy or shutdown_requested or closing or not ready_for_ticks or tick_pending or checkpoint_capture_pending or not shadow_sync_reason.is_empty() or sand_prefetch_in_flight or command_queue.pending.is_empty(): return {"error":"backend_unavailable"}
	var front: Dictionary=command_queue.pending[0]
	if not is_finite(available_m3) or front.command_id!=command.command_id or front.generation!=generation or front.sim_tick>completed_ticks: return {"error":"invalid_command"}
	command=front
	var execution_tick:=completed_ticks
	edit_overlap_window_open=false
	pending_gpu_command=command_queue.pending.pop_front();pending_gpu_revision=solver.state_revision
	gpu_busy=true;gpu_settled=false;gpu_published=false;gpu_receipt={};gpu_receipt_raw=PackedByteArray();ticket_id+=1
	_record_gpu_wait_phase("dispatch")
	var stock: float=shadow_domain.tool_inventory_m3
	var selection: Dictionary={"policy":water_policy,"speed":signed_speed_m_s}
	var data:=_encode_gpu_command(command,ticket_id,pending_gpu_revision,selection,available_m3)
	RenderingServer.call_on_render_thread(_render_gpu_command.bind(data,generation))
	while gpu_receipt.is_empty() and not closing and last_error.is_empty(): await get_tree().process_frame
	_record_gpu_wait_phase("receipt_ready")
	if gpu_receipt.get("status")==1 and not closing and last_error.is_empty():
		RenderingServer.call_on_render_thread(_render_gpu_publish.bind(generation))
		while not gpu_published and not closing and last_error.is_empty(): await get_tree().process_frame
		_record_gpu_wait_phase("publication_ready")
		while not closing and last_error.is_empty():
			var complete:=true
			for chunk in collision_needed: complete=complete and int(collision_proxy.applied_revisions.get(chunk,-1))>=int(collision_needed[chunk])
			if complete: break
			await get_tree().process_frame
		_record_gpu_wait_phase("collision_ready")
		await get_tree().physics_frame
		_record_gpu_wait_phase("physics_one")
		for boundary in range(1,clampi(edit_physics_wait_count,1,3)):
			await get_tree().physics_frame
			_record_gpu_wait_phase("physics_two" if boundary==1 else "physics_three")
	if gpu_settled:
		var record := {"command":command.duplicate(true),"result":gpu_receipt.duplicate(true),"policy":selection.policy,"speed":selection.speed,"stock_before":stock,"available_m3":available_m3,"execution_tick":execution_tick}
		if unrestricted_sand_tools: record.sand_accounting = "external_v1"
		gpu_prefix.append(_prepare_prefix_record(record))
	edit_overlap_window_open=false
	gpu_busy=false;pending_gpu_command={}
	return gpu_receipt.duplicate(true) if gpu_settled else {"error":"closed" if closing else last_error}

func _prepare_prefix_record(record:Dictionary) -> Dictionary:
	return record

func _encode_gpu_command(command: Dictionary, ticket: int, revision: int, selection: Dictionary, available: float) -> PackedByteArray:
	return Protocol.encode(command,ticket,revision,GRID_SIZE,shadow_domain.cell_size_m,selection.policy,available,selection.speed)

func _render_gpu_command(data: PackedByteArray, token: int) -> void:
	if closing or token!=generation: return
	if not solver.dispatch_sand_command(data,_on_gpu_receipt.bind(token)): call_deferred("_fail","beach GPU dispatch failed")

func _on_gpu_receipt(bytes: PackedByteArray, token: int) -> void: call_deferred("_settle_gpu_receipt",bytes,token)

func _settle_gpu_receipt(bytes: PackedByteArray, token: int) -> void:
	if closing or token!=generation or gpu_settled or pending_gpu_command.is_empty(): return
	var receipt:=Protocol.decode_receipt(bytes)
	if not Protocol.receipt_matches(receipt,ticket_id,pending_gpu_command.command_id,token,pending_gpu_revision) or receipt.status not in [1,2]: _fail("beach GPU receipt mismatch");return
	if receipt.status==1:
		if unrestricted_sand_tools:
			if pending_gpu_command.kind==&"remove_sand": shadow_domain.sand_sink_m3 += receipt.actual_sand_m3
			else: shadow_domain.sand_source_m3 += receipt.actual_sand_m3
		else:
			shadow_domain.tool_inventory_m3+=receipt.actual_sand_m3 if pending_gpu_command.kind==&"remove_sand" else -receipt.actual_sand_m3
		command_queue.applied_log.append(pending_gpu_command.duplicate(true))
		shadow_sand_revision=-1;shadow_revision=-1
		collision_needed.clear()
		for chunk in _gpu_chunks(receipt): collision_needed[chunk]=receipt.output_revision
	gpu_settled=true;gpu_receipt=receipt;gpu_receipt_raw=bytes.duplicate()
	_record_diagnostic(gpu_events, {"phase":"settled","at_us":Time.get_ticks_usec(),"revision":receipt.output_revision,"stock":shadow_domain.tool_inventory_m3})

func _gpu_chunks(receipt: Dictionary) -> PackedInt32Array:
	if "--beach-bounded-collision" in ReleaseConfig.ARGUMENTS:
		return preload("res://scripts/simulation/edit_validation/collision_chunk_selection.gd").bounded(receipt.dirty_mask,receipt.dirty_rect)
	var chunks:=PackedInt32Array()
	for chunk in 64:
		if (int(receipt.dirty_mask[chunk/32])&(1<<(chunk%32)))==0: continue
		for dz in range(-1,2):
			for dx in range(-1,2):
				var x: int=chunk%8+dx;var z: int=chunk/8+dz
				if x>=0 and x<8 and z>=0 and z<8 and z*8+x not in chunks: chunks.append(z*8+x)
	chunks.sort();return chunks

func _render_gpu_publish(token: int) -> void:
	if closing or token!=generation: return
	if not gpu_settled or not solver.authorize_publication(ticket_id,gpu_receipt.output_revision,token): call_deferred("_fail","beach GPU unsettled publication");return
	_publish_textures()
	if not collision_proxy.request_chunks_render(_gpu_chunks(gpu_receipt),solver.state_revision,token): call_deferred("_fail","beach GPU collision request failed");return
	call_deferred("_gpu_publication_done",token)

func _gpu_publication_done(token: int) -> void:
	if closing or token!=generation: return
	edit_overlap_window_open=true
	gpu_published=true;_record_diagnostic(gpu_events, {"phase":"published","at_us":Time.get_ticks_usec(),"revision":solver.state_revision})

func _render_release() -> void:
	if gpu_release_done: return
	if pending_beach_native_readbacks>0 or (solver!=null and solver.receipt_pending) or collision_proxy.staging_texture.is_valid():
		call_deferred("_retry_gpu_release");return
	for rid in stable_q.values():
		if rid.is_valid(): solver.rd.free_rid(rid)
	stable_q.clear()
	collision_proxy._release_render()
	super._render_release()
	gpu_release_us=Time.get_ticks_usec()
	call_deferred("_gpu_release_finished")

func _gpu_release_finished() -> void: gpu_release_done=true

func shutdown() -> void:
	if gpu_release_done: return
	shutdown_requested=true;playing=false;set_process_unhandled_input(false)
	# Already started work completes through CPU settlement and publication.
	# Stop new admission before waiting, then close the collision epoch.
	while gpu_busy or tick_pending or frame_collision_pending() or checkpoint_capture_pending or sand_prefetch_in_flight or not shadow_sync_reason.is_empty(): await get_tree().process_frame
	closing=true;ready_for_ticks=false
	collision_proxy.closing=true;collision_proxy.generation+=1;collision_proxy.pending_revisions.clear()
	await collision_proxy.stop_prepare_and_drain()
	RenderingServer.call_on_render_thread(_render_release)
	while not gpu_release_done: await get_tree().process_frame

func _retry_gpu_release() -> void:
	await get_tree().process_frame
	RenderingServer.call_on_render_thread(_render_release)

extends "res://scripts/beach/gravel_playable_entry.gd"

const AsyncEditor=preload("res://scripts/simulation/edit_validation/frame_pipeline/async_editor.gd")
const AsyncController=preload("res://scripts/simulation/edit_validation/frame_pipeline/async_controller.gd")
const AsyncScheduler=preload("res://scripts/simulation/edit_validation/frame_pipeline/async_scheduler.gd")
const ClockVariants=preload("res://scripts/simulation/edit_validation/frame_pipeline/async_clock_variants.gd")
const AsyncCheckpoint=preload("res://scripts/simulation/edit_validation/frame_pipeline/async_checkpoint_codec.gd")
const AsyncCapture=preload("res://scripts/simulation/edit_validation/frame_pipeline/async_checkpoint_capture.gd")
const AsyncRestore=preload("res://scripts/simulation/edit_validation/frame_pipeline/async_restore_bundle.gd")
const AsyncMigration=preload("res://scripts/simulation/edit_validation/frame_pipeline/async_legacy_migration.gd")
const AsyncTerminal=preload("res://scripts/simulation/edit_validation/frame_pipeline/async_terminal_guard.gd")
const AsyncShadow=preload("res://scripts/simulation/edit_validation/frame_pipeline/async_shadow_read.gd")
@export var async_pipeline_enabled:=false
@export var async_water_shader: Shader
@export var async_terrain_shader: Shader
var async_controller
var async_backend_ready:=false
var async_clock_wrapper:=Texture2DRD.new()
var async_legacy_running:=false
var async_previous_playing:=false
var async_previous_accepting:=false
var ledger_precision:="exact"
var async_shaders_bound:=false
var async_checkpoint_running:=false
var async_last_migration:={}
var async_shutdown_running:=false
var async_shutdown_error: StringName=&""
var async_capture_owners: Array=[]
var inject_async_capture_registration_failures:=0
var inject_async_candidate_registration_failures:=0
var inject_async_candidate_terminal_unavailable:=false
var inject_async_candidate_build_failure_phase:=""
var async_terminal=AsyncTerminal.new()
var async_fault_probe_running:=false
var inject_async_bootstrap_failure_phase:=""
var inject_async_capture_hold_results:=false
var inject_async_candidate_hold_results:=false
var inject_async_restore_failure_after_publish:=false
var inject_async_shadow_readback_failure_once:=false
var async_shadow_jobs:=[]
var async_last_shadow_drain:={}
var async_ui_pending:={}
var async_gravel_pending_count:=0

func _configure_scene() -> void:
	super._configure_scene()
	if async_pipeline_enabled:
		if async_water_shader==null or async_terrain_shader==null:_fail("GPU clock static shader missing");return
		_bind_clock_shader(water_material,async_water_shader,compiled_constants[0])
		_bind_clock_shader(terrain_material,async_terrain_shader,compiled_constants[1])
		async_shaders_bound=true
		_validate_compiled_inputs()
	var sides := get_node_or_null("WaterSides")
	if sides != null and last_error.is_empty():
		var side_error: String = sides.bind_surface(water_material, terrain_material)
		if not side_error.is_empty(): _fail(side_error)

func _bind_clock_shader(shader_material: ShaderMaterial, shader: Shader, constants: Dictionary) -> void:
	var parameters:={}
	for uniform in shader_material.shader.get_shader_uniform_list():
		var value: Variant=shader_material.get_shader_parameter(uniform.name)
		if value==null:value=RenderingServer.shader_get_parameter_default(shader_material.shader.get_rid(),uniform.name)
		if value!=null:parameters[uniform.name]=value
	for key in constants:parameters[key]=constants[key]
	shader_material.shader=shader
	for key in parameters:shader_material.set_shader_parameter(key,parameters[key])

func _validate_compiled_inputs() -> bool:
	if not async_pipeline_enabled or not async_shaders_bound:return super._validate_compiled_inputs()
	var result:=ClockVariants.validate(self)
	if not result.error.is_empty():_fail(result.error);return false
	if async_backend_ready:
		for shader_material in [water_material,terrain_material]:
			if shader_material.get_shader_parameter("use_async_clock")!=true or shader_material.get_shader_parameter("async_clock")!=async_clock_wrapper:_fail("GPU clock effective binding mismatch");return false
	effective_compilation=result
	return true

func _effective_profile_request() -> Dictionary:
	if not async_pipeline_enabled or not async_shaders_bound:return super._effective_profile_request()
	if not _validate_compiled_inputs():return requested_render_profile
	var value: Dictionary=requested_render_profile.duplicate(true)
	for component in compiled_bundle.components:
		if component.material=="water":
			if value.resources.water_shader!=component.shader:_fail("clock request original water path mismatch");return requested_render_profile
			value.resources.water_shader=async_water_shader.resource_path
		else:
			if value.resources.terrain_fixed_shader!=component.shader or value.resources.terrain_coupled_shader!=component.shader:_fail("clock request original bed path mismatch");return requested_render_profile
			value.resources.terrain_fixed_shader=async_terrain_shader.resource_path
			value.resources.terrain_coupled_shader=async_terrain_shader.resource_path
	return value

func _ready() -> void:
	if async_pipeline_enabled:
		async_controller=AsyncController.new(self)
		async_controller.inject_initialize_failure_phase=inject_async_bootstrap_failure_phase
		collision_proxy.async_failure_callback=_fail
		ledger_precision="approximate"
	super._ready()

func _make_gpu_editor():
	if not async_pipeline_enabled:return super._make_gpu_editor()
	var editor:=AsyncEditor.new()
	editor.brush_water_enabled=enable_brush_water
	return editor

func _create_input_scheduler():
	var previous=super._create_input_scheduler()
	if not async_pipeline_enabled:return previous
	var scheduler:=AsyncScheduler.new(self)
	scheduler.history_limit=DIAGNOSTIC_HISTORY_LIMIT
	return scheduler

func _runtime_configuration_signature() -> Dictionary:
	var value:=super._runtime_configuration_signature()
	_index_sources("res://assets/water_sides", value.sources)
	value.sources["res://assets/water_sides/main_boundary.res"] = FileAccess.get_sha256("res://assets/water_sides/main_boundary.res")
	value.sources["res://assets/water_sides/test1_boundary.res"] = FileAccess.get_sha256("res://assets/water_sides/test1_boundary.res")
	value.async_pipeline_enabled=async_pipeline_enabled
	if async_pipeline_enabled:value.all_tools_pipeline_version=1
	if async_pipeline_enabled:value.pipeline_protocol=1;value.ledger_precision="approximate"
	return value

func _render_setup(target: SandWaterDomain, token: int) -> void:
	super._render_setup(target,token)
	if not async_pipeline_enabled or solver==null or solver.rd==null:return
	if inject_async_bootstrap_failure_phase=="before_controller":
		call_deferred("_fail","GPU pipeline fatal: bootstrap before controller")
		return
	if not async_controller.initialize_render():
		call_deferred("_fail","GPU pipeline initialization: "+async_controller.water.last_error)
		return
	async_clock_wrapper.texture_rd_rid=solver.async_transport.clock_texture
	for material in [terrain_material,water_material]:
		material.set_shader_parameter("async_clock",async_clock_wrapper)
		material.set_shader_parameter("use_async_clock",true)
	_bind_async_textures_render()
	call_deferred("_async_mark_ready",token)

func _mark_ready(token: int) -> void:
	if async_pipeline_enabled and not async_backend_ready:return
	super._mark_ready(token)

func _async_mark_ready(token: int) -> void:
	# Finish bootstrap's original full-collision request before the new owner
	# takes over shape versions; no old callbacks can later overwrite new ones.
	while not closing and last_error.is_empty() and (collision_proxy.staging_texture.is_valid() or not collision_proxy.pending_revisions.is_empty() or collision_proxy.has_prepare_in_flight()):await get_tree().process_frame
	if closing or token!=generation or not last_error.is_empty():return
	async_backend_ready=true
	async_controller.ready=true
	_mark_ready(token)

func _process(delta: float) -> void:
	if async_pipeline_enabled and async_backend_ready:
		async_controller.poll()
		async_controller.pump(delta)
	super._process(delta)

func _physics_process(_delta: float) -> void:
	if async_pipeline_enabled and async_backend_ready:async_controller.physics_consume()

func _start_tick() -> void:
	if not async_pipeline_enabled:super._start_tick();return
	if async_backend_ready and not async_checkpoint_running and not beach_restore_running and not async_controller.transitioning and not shutdown_requested:async_controller.explicit_ticks=mini(async_controller.explicit_ticks+1,64)

func _automatic_tick_enabled() -> bool:
	return not async_pipeline_enabled

func _fail(message: String) -> void:
	if async_pipeline_enabled and not last_error.is_empty():return
	super._fail(message)
	if async_pipeline_enabled:
		collision_proxy.closing=true
		collision_proxy.pending_revisions.clear()
	if async_pipeline_enabled and async_controller!=null and input_scheduler!=null:async_controller._fail_pipeline("owner_failed:"+message,false)
	if async_pipeline_enabled and solver!=null and solver.rd!=null and async_controller!=null:
		async_terminal.required=true
		if not async_fault_probe_running and not async_terminal.pending:
			async_fault_probe_running=true
			call_deferred("_async_fault_terminal_probe")

func _async_fault_terminal_probe() -> void:
	if async_terminal.pending:async_fault_probe_running=false;return
	async_fault_probe_running=true
	async_terminal.begin("probe")
	while async_terminal.pending:await get_tree().process_frame
	async_fault_probe_running=false

func retry_async_terminal_proof() -> bool:
	if async_terminal.pending or async_fault_probe_running:return false
	await _async_fault_terminal_probe()
	return not async_terminal.unconfirmed_ownership

func _settle_gpu_receipt(bytes: PackedByteArray, token: int) -> void:
	if async_pipeline_enabled and not last_error.is_empty():return
	super._settle_gpu_receipt(bytes,token)

func _async_ownership_unconfirmed() -> bool:
	return async_pipeline_enabled and async_controller!=null and (collision_proxy.terminal.unconfirmed_ownership or async_terminal.unconfirmed_ownership or async_controller.unconfirmed_ownership or async_controller.collision.unconfirmed_ownership or async_capture_owners.any(func(job):return job.unconfirmed_ownership) or (beach_restore_candidate!=null and beach_restore_candidate.unconfirmed_ownership))

func _async_has_external_owners() -> bool:
	return not async_shadow_jobs.is_empty() or collision_proxy.failed_readback_owned or collision_proxy.terminal_running or (async_terminal.required and not async_terminal.confirmed) or not async_capture_owners.is_empty() or (beach_restore_candidate!=null and beach_restore_candidate.discard_requested and not beach_restore_candidate.released)

func can_submit_frame_batch() -> bool:
	return false if async_pipeline_enabled else super.can_submit_frame_batch()

func _dispatch_paused_patch() -> void:
	if not async_pipeline_enabled or (async_controller!=null and async_controller.legacy):super._dispatch_paused_patch()

func _after_paused_tool_patch() -> bool:
	if not async_pipeline_enabled or not solver.mold_field_ever_used:return super._after_paused_tool_patch()
	return material_coupler.reconcile_external_sand_patch()

func _request_shadow_sync(reason: String) -> void:
	if async_pipeline_enabled and async_controller!=null and not async_controller.legacy:return
	super._request_shadow_sync(reason)

func _render_shadow_sync(revision: int, token: int, full: bool) -> void:
	if not async_pipeline_enabled:super._render_shadow_sync(revision,token,full);return
	var job=AsyncShadow.new(self,revision,token,full)
	job.inject_failure=inject_async_shadow_readback_failure_once
	inject_async_shadow_readback_failure_once=false
	job.run_render()

func _async_shadow_started(job) -> void:async_shadow_jobs.append(job)

func _async_shadow_field(bytes: PackedByteArray, field: String, revision: int, token: int) -> void:
	if last_error.is_empty():super._shadow_field_ready(bytes,field,revision,token)

func _async_shadow_finished(job) -> void:
	async_shadow_jobs.erase(job)
	async_last_shadow_drain={"registered":job.registered.size(),"received":job.received.size(),"generation":job.generation,"failed":not last_error.is_empty()}
	if not last_error.is_empty() and job.generation==generation:
		shadow_sync_reason="";shadow_sync_full=false;shadow_sync_fields.clear();tick_pending=false

func _drain_input() -> void:
	if not async_pipeline_enabled:
		await super._drain_input()
		return
	input_running=false

func _submit_gpu_input(kind: StringName, start: Vector3, end: Vector3, shape: StringName, amount: float) -> bool:
	var accepted:=super._submit_gpu_input(kind,start,end,shape,amount)
	if async_pipeline_enabled and not accepted:gpu_brush=&"";last_input_hit=end
	return accepted

func _encode_gpu_command(command: Dictionary, ticket: int, revision: int, selection: Dictionary, available: float) -> PackedByteArray:
	if async_pipeline_enabled and async_controller!=null and async_controller.legacy and command.get("schema_version",1)==1:
		command=command.duplicate(true)
		command.sim_tick=completed_ticks
	return super._encode_gpu_command(command,ticket,revision,selection,available)

func _bind_async_textures_render() -> void:
	rock_texture.texture_rd_rid=solver.current_texture("rock")
	sand_texture.texture_rd_rid=solver.published_sand
	water_texture.texture_rd_rid=solver.published_water
	wetness_texture.texture_rd_rid=solver.current_texture("wetness")
	compaction_texture.texture_rd_rid=solver.current_texture("compaction")
	momentum_x_texture.texture_rd_rid=solver.current_texture("momentum_x")
	momentum_z_texture.texture_rd_rid=solver.current_texture("momentum_z")
	sediment_texture.texture_rd_rid=solver.current_texture("sediment")
	obstacle_texture.texture_rd_rid=solver.current_texture("obstacle")
	flux_texture.texture_rd_rid=solver.current_texture("flux")
	if foam_field!=null:foam_texture.texture_rd_rid=foam_field.current_texture()
	if local_front_field!=null:local_front_texture.texture_rd_rid=local_front_field.texture
	if gravel_field!=null:gravel_wrapper.texture_rd_rid=gravel_field.current_texture()

func _publish_textures() -> void:
	if async_pipeline_enabled and async_backend_ready and not async_controller.legacy:
		solver.publish_sand()
		_bind_async_textures_render()
	else:super._publish_textures()

func _format_status_text(text: String) -> String:
	text=super._format_status_text(text)
	if async_pipeline_enabled and async_controller!=null:
		# The old CFL/water-receipt HUD is no longer populated by this backend.
		var previous:="Tick %d  CFL 子步 %d  入水 %.4f m³  出水 %.4f m³"%[completed_ticks,last_substeps,last_source_m3,last_sink_m3]
		text=text.replace(previous,"Tick %d · 模拟 %.2f s"%[completed_ticks,async_controller.actual_time])
		text+="\nGPU编辑 成功%d 跳过%d · 源汇估算"%[async_controller.accepted_commands,async_controller.rejected_commands]
	return text

func request_wave(request: Dictionary) -> Dictionary:
	if async_pipeline_enabled and (async_checkpoint_running or beach_restore_running):return _wave_result(&"transition_busy",int(request.get("request_id",0)),completed_ticks)
	if async_pipeline_enabled and async_controller!=null:
		for index in range(wave_requests.size()-1,-1,-1):
			var item: Dictionary=wave_requests[index]
			if async_controller.wave_start_times.has(item.request_id) and async_controller.actual_time>=async_controller.wave_start_times[item.request_id]+item.duration_s:
				wave_requests.remove_at(index)
				async_controller.wave_start_times.erase(item.request_id)
		if wave_requests.size()>=async_controller.water.MAX_WAVES:return _wave_result(&"wave_capacity",int(request.get("request_id",0)),completed_ticks)
	return super.request_wave(request)

func _update_gravel_aabb() -> void:
	if not async_pipeline_enabled or async_controller==null:super._update_gravel_aabb();return
	if shadow_domain==null or not is_instance_valid(gravel_layer):return
	var source: float=async_controller.nominal_upper_supply+maxf(shadow_domain.sand_source_m3,0.0)
	if source==gravel_last_bound_source and generation==gravel_last_bound_generation:return
	gravel_last_bound_source=source
	gravel_last_bound_generation=generation
	var low: float=Array(shadow_domain.rock).min()-0.1
	var high: float=Array(shadow_domain.rock).max()+(initial_sand_total_m3+source+1.0)/(CELL_SIZE_M*CELL_SIZE_M)+0.2
	gravel_layer.multimesh.custom_aabb=AABB(Vector3(-16.1,low,-16.1),Vector3(32.2,maxf(high-low,1.0),32.2))

func _record_sand_audit(data: PackedByteArray, revision: int, ledger: Dictionary, token: int) -> void:
	if not async_pipeline_enabled:super._record_sand_audit(data,revision,ledger,token);return
	if closing or token!=generation:return
	var result: Dictionary=sand_audit.decode(data)
	if not result.get("valid",false) or result.invalid_cells!=0 or result.negative_cells!=0:_fail("GPU pipeline sand data invalid");return
	audit_sand_m3=result.sand_m3
	audit_sediment_m3=result.sediment_m3
	audit_sand_total_m3=result.sand_m3+result.sediment_m3+ledger.inventory_m3
	audit_sand_closure_m3=absf(audit_sand_total_m3-initial_sand_total_m3-ledger.source_m3+ledger.sink_m3)
	audit_sand_revision=revision

func _async_enter_legacy() -> StringName:
	if async_controller.legacy:return &""
	if async_controller.transitioning:return &"transition_busy"
	async_previous_playing=playing
	async_previous_accepting=input_scheduler.accepting
	async_controller.transitioning=true
	playing=false
	input_scheduler.accepting=false
	while last_error.is_empty() and (not async_controller.idle(true) or (not command_queue.pending.is_empty() and async_controller.ordinary(command_queue.pending[0]))):await get_tree().process_frame
	if not last_error.is_empty():return &"backend_failed"
	async_controller.legacy=true
	for chunk in collision_proxy.applied_revisions:collision_proxy.applied_revisions[chunk]=solver.state_revision
	collision_needed.clear()
	_request_shadow_sync("async_legacy")
	while not shadow_sync_reason.is_empty() and last_error.is_empty():await get_tree().process_frame
	preview_cache_key=""
	return &"" if last_error.is_empty() else &"backend_failed"

func _async_leave_legacy() -> void:
	if not last_error.is_empty():
		collision_proxy.closing=true
		collision_proxy.pending_revisions.clear()
	while collision_proxy.staging_texture.is_valid() or not collision_proxy.pending_revisions.is_empty() or collision_proxy.has_prepare_in_flight():
		if _async_ownership_unconfirmed():break
		await get_tree().process_frame
	if last_error.is_empty():await async_controller.bridge()
	async_controller.legacy=false
	async_controller.transitioning=false
	async_controller.collision.applied_state_seq.clear()
	async_controller.collision.mark_all()
	if last_error.is_empty() and not shutdown_requested and not async_checkpoint_running and not beach_restore_running:
		playing=async_previous_playing
		input_scheduler.accepting=async_previous_accepting
	gpu_prefix.clear()
	command_queue.applied_log.clear()
	command_queue.undo_stack.clear()
	command_queue.redo_stack.clear()

func _async_drain_legacy_front() -> void:
	# Kept for older boundary callers. Every queued tool is now submitted by
	# the same frame pump; this does not switch ownership or pause simulation.
	await get_tree().process_frame

func _async_queue_control(operation: int, values: Dictionary) -> Dictionary:
	if operation not in [async_controller.Tools.Mode.BEGIN,async_controller.Tools.Mode.END,async_controller.Tools.Mode.GRAVEL]:return {"error":&"invalid_command"}
	if not async_backend_ready or not last_error.is_empty():return {"error":&"backend_unavailable"}
	if async_controller.transitioning or async_controller.frozen:return {"error":&"transition_busy"}
	if command_queue.pending.size()>=64:return {"error":&"queue_full"}
	var value:=values.duplicate(true)
	value.async_operation=operation;value.kind=&"async_control"
	value.generation=generation;value.domain_id=domain.domain_id
	value.command_id=command_queue.last_command_id+1
	value.sim_tick=maxi(completed_ticks,int(command_queue.pending[-1].sim_tick) if not command_queue.pending.is_empty() else completed_ticks)
	command_queue.last_command_id=value.command_id
	command_queue.pending.append(value)
	input_scheduler.reservations[value.command_id]=0.0
	input_scheduler.policies[value.command_id]={"policy":0,"speed":0.0}
	return {"error":&"","command":value}

func _async_wait_command(command: Dictionary, allow_shutdown: bool=false) -> Dictionary:
	var scheduler=input_scheduler
	while generation==command.generation and not closing and last_error.is_empty():
		for row in scheduler.terminal:
			if row.command.command_id==command.command_id and row.command.generation==command.generation:return row.result.duplicate(true)
		if shutdown_requested and not allow_shutdown:return {"error":&"closing"}
		await get_tree().process_frame
	return {"error":&"backend_failed" if not last_error.is_empty() else &"closing"}

func begin_shape_stroke(stroke: int) -> StringName:
	if not async_pipeline_enabled:return await super.begin_shape_stroke(stroke)
	var owned_ui: bool=ui_pump_running and stroke==ui_stroke_identity and stroke_controller.generation==generation
	if shutdown_requested and not owned_ui:return &"closing"
	if (async_checkpoint_running or beach_restore_running) and not owned_ui:return &"transition_busy"
	if not input_scheduler.accepting and not owned_ui:return &"backend_unavailable"
	if not shape_backend_ready or shape_stroke_id!=0 or stroke<=0:return &"backend_unavailable"
	_shape_serial+=1;shape_baseline_token=_shape_serial;shape_stroke_id=stroke
	var queued:=_async_queue_control(async_controller.Tools.Mode.BEGIN,{"stroke_id":stroke,"baseline_token":shape_baseline_token})
	if not queued.error.is_empty():shape_stroke_id=0;shape_baseline_token=0;return queued.error
	var result:=await _async_wait_command(queued.command)
	if result.get("status")!=1:shape_stroke_id=0;shape_baseline_token=0;return &"invalid_baseline"
	shape_accepting=true
	return &""

func end_shape_stroke() -> StringName:
	if not async_pipeline_enabled:return await super.end_shape_stroke()
	if shape_stroke_id==0:return &""
	shape_accepting=false
	var queued:=_async_queue_control(async_controller.Tools.Mode.END,{"stroke_id":shape_stroke_id,"baseline_token":shape_baseline_token})
	while queued.error==&"queue_full" and last_error.is_empty():
		await get_tree().process_frame
		queued=_async_queue_control(async_controller.Tools.Mode.END,{"stroke_id":shape_stroke_id,"baseline_token":shape_baseline_token})
	if not queued.error.is_empty():return queued.error
	var result:=await _async_wait_command(queued.command,true)
	shape_stroke_id=0;shape_baseline_token=0
	return &"" if result.get("status")==1 else &"invalid_baseline"

func apply_legacy_command(command: Dictionary) -> Dictionary:
	if not async_pipeline_enabled:return await super.apply_legacy_command(command)
	if shutdown_requested:return {"error":&"closing"}
	if async_checkpoint_running or beach_restore_running:return {"error":&"transition_busy"}
	if command.get("kind") not in [&"smooth",&"compact"]:return {"error":&"invalid_command"}
	var result:=await apply_gpu_command(command)
	if result.has("error"):return result
	return {"gpu_complete":true,"results":[{"command_id":command.command_id,"status":&"applied" if result.get("status")==1 else &"rejected","error":result.get("error_code",0),"edited_cells":result.get("edited_cells",0)}],"receipt":result}

func drop_gravel(point: Vector2, count: int) -> Dictionary:
	if not async_pipeline_enabled:return await super.drop_gravel(point,count)
	if shutdown_requested:return {"error":&"closing"}
	if async_checkpoint_running or beach_restore_running:return {"error":&"transition_busy"}
	if not gravel_enabled or not ready_for_ticks or not input_scheduler.accepting:return {"error":&"backend_unavailable"}
	if not point.is_finite() or count<1 or count>128 or absf(point.x)>15.55 or absf(point.y)>15.55:return {"error":&"out_of_domain"}
	if async_controller.gravel_admitted_count<0:async_controller.gravel_admitted_count=gravel_field.active_count
	if async_controller.gravel_admitted_count+count>1024:return {"error":&"gravel_capacity_full"}
	var queued:=_async_queue_control(async_controller.Tools.Mode.GRAVEL,{"point":point,"count":count})
	if not queued.error.is_empty():return {"error":queued.error}
	async_controller.gravel_admitted_count+=count
	var total: int=async_controller.gravel_admitted_count
	async_gravel_pending_count+=1;gravel_drop_pending=true
	var receipt:=await _async_wait_command(queued.command)
	async_gravel_pending_count-=1;gravel_drop_pending=async_gravel_pending_count>0
	if receipt.get("cancelled",false) and not receipt.get("submitted",false):async_controller.gravel_admitted_count-=count
	var result:={"ok":receipt.get("status")==1,"error":receipt.get("error",&""),"active_count":total,"generation":generation}
	gravel_drop_result=result.duplicate()
	if ui_tool==&"gravel_drop" and result.ok:brush_panel.show_status("已投 %d 颗 · 共 %d / 1024"%[count,total])
	return result

func _async_tool_settled(command: Dictionary, result: Dictionary) -> void:
	if not async_ui_pending.has(command.command_id):return
	async_ui_pending.erase(command.command_id)
	stroke_controller.settle_command(command.command_id,command.generation)
	_record_diagnostic(ui_brush_events,{"command":command,"terminal":{"command":command,"result":result},"buffer_points":stroke_controller.buffer_points(),"at_us":Time.get_ticks_usec()})
	if result.get("status",3)==3 or result.has("error"):
		ui_last_failure=_ui_error_message(result.get("error_code",result.get("error","后端失败")))
		stroke_controller.end_stroke(false)

func _pump_ui_stroke(epoch: int, identity: int) -> void:
	if not async_pipeline_enabled:await super._pump_ui_stroke(epoch,identity);return
	async_ui_pending.clear()
	var error:=await begin_shape_stroke(identity)
	if not error.is_empty():ui_last_failure=_ui_error_message(error);stroke_controller.end_stroke(false);ui_pump_running=false;return
	while epoch==generation and not closing and last_error.is_empty():
		# Cancellation records can arrive without a GPU callback (e.g. shutdown).
		for row in input_scheduler.terminal:
			if async_ui_pending.has(row.command.command_id):_async_tool_settled(row.command,row.result)
		if ui_closing or shutdown_requested:stroke_controller.end_stroke(false)
		stroke_controller.begin_frame(Engine.get_process_frames())
		var segment: Dictionary=stroke_controller.peek_segment()
		if segment.is_empty():
			if stroke_controller.state in [&"draining",&"settled"] and stroke_controller.outstanding==0:break
			await get_tree().process_frame;continue
		var command:=BrushProtocol.make_command(stroke_controller.brush_id,stroke_controller.params,segment.start_xz_m,segment.end_xz_m,domain.domain_id,generation,command_queue.last_command_id+1,identity,segment.sample_index,completed_ticks,shape_baseline_token)
		command.material_profile_id=&"plain_sand_v1" if stroke_controller.brush_id==&"shovel_v1" else &"molded_v1"
		error=input_scheduler.submit(command)
		if error in [&"queue_full",&"backend_unavailable"]:await get_tree().process_frame;continue
		if not error.is_empty():ui_last_failure=_ui_error_message(error);stroke_controller.end_stroke(false);break
		stroke_controller.acknowledge_admission(segment,command.command_id)
		async_ui_pending[command.command_id]=true
	if shape_stroke_id!=0 and epoch==generation and last_error.is_empty():await end_shape_stroke()
	ui_pressed=false;ui_pump_running=false

func apply_gpu_command(command: Dictionary) -> Dictionary:
	if not async_pipeline_enabled:return await super.apply_gpu_command(command)
	var error: StringName=input_scheduler.submit(command)
	if not error.is_empty():return {"error":error}
	var scheduler=input_scheduler
	var epoch:=generation
	var result: Dictionary={}
	while result.is_empty():
		if not last_error.is_empty():return {"error":&"backend_failed"}
		if shutdown_requested or closing:return {"error":&"closing"}
		if generation!=epoch:return {"error":&"generation_changed"}
		for row in scheduler.terminal:
			var submitted: Dictionary=row.get("command",{})
			if submitted.get("command_id")==command.command_id and submitted.get("generation")==epoch:
				result=row.result.duplicate(true);break
		if result.is_empty():await get_tree().process_frame
	# Controlled schema-v1 tools also own a bridge back to the ordinary stream.
	# An open schema-v2 stroke keeps its baseline until its explicit end call.
	if command.get("schema_version",1)==1 and not async_controller.ordinary(command):
		while async_legacy_running or async_controller.transitioning:
			if not last_error.is_empty():return {"error":&"backend_failed"}
			if shutdown_requested or closing:return {"error":&"closing"}
			if generation!=epoch:return {"error":&"generation_changed"}
			await get_tree().process_frame
	if not last_error.is_empty():return {"error":&"backend_failed"}
	if shutdown_requested or closing:return {"error":&"closing"}
	if generation!=epoch:return {"error":&"generation_changed"}
	return result

func _async_snapshot_simulation_configuration() -> Dictionary:
	return {"enable_erosion":enable_erosion,"enable_brush_water":enable_brush_water,"unrestricted_sand_tools":unrestricted_sand_tools,"enable_structures":enable_structures,"local_front_history":prototype_local_front_field,"rise_front_history":prototype_rise_front_field,"contact_history":prototype_contact_history_field,"prescribed_tide_boundary":solver.prescribed_tide_boundary}

func _async_requested_playing() -> bool:
	if async_pipeline_enabled and async_controller!=null and (async_controller.legacy or async_controller.transitioning):return async_previous_playing
	return playing

func _async_requested_accepting() -> bool:
	return async_previous_accepting if (async_controller.legacy or async_controller.transitioning) else input_scheduler.accepting

func _async_boundary_busy() -> bool:
	return async_checkpoint_running or gpu_save_running or beach_restore_running or brush_save_request_pending or async_shutdown_running

func _async_close_interaction() -> void:
	# UI points have not yet entered the command queue. Cancel those points;
	# already admitted segments still settle and close their owned GPU baseline.
	_finish_ui_stroke(false)
	while ui_pump_running and last_error.is_empty():await get_tree().process_frame
	if shape_stroke_id!=0 and last_error.is_empty():await end_shape_stroke()

func capture_async_checkpoint_data() -> Dictionary:
	if not async_pipeline_enabled:return {"error":&"pipeline_disabled"}
	if async_checkpoint_running or gpu_save_running or beach_restore_running:return {"error":&"transition_busy"}
	if shutdown_requested or closing:return {"error":&"closing"}
	if not async_backend_ready or not last_error.is_empty():return {"error":&"backend_failed"}
	if enable_structures or prototype_rise_front_field or prototype_contact_history_field:return {"error":&"unsupported_pipeline_history"}
	var profile_error:=_checkpoint_runtime_profile_error()
	if not profile_error.is_empty():return {"error":profile_error}
	async_checkpoint_running=true
	var was_playing:=_async_requested_playing()
	var was_accepting: bool=_async_requested_accepting()
	var was_preview_suspended:=preview_suspended
	playing=false
	preview_suspended=true
	input_scheduler.accepting=false
	await _async_close_interaction()
	playing=false
	input_scheduler.accepting=false
	while last_error.is_empty() and (async_legacy_running or async_controller.legacy or gravel_drop_pending or not command_queue.pending.is_empty() or not async_controller.idle()):
		if not async_legacy_running and not async_controller.transitioning and not command_queue.pending.is_empty() and not async_controller.ordinary(command_queue.pending[0]):await _async_drain_legacy_front()
		await get_tree().process_frame
	async_controller.transitioning=true
	async_controller.frozen=true
	var result: Dictionary={"error":&"backend_failed"}
	if last_error.is_empty():
		var capture=AsyncCapture.new(self)
		capture.inject_registration_failures=inject_async_capture_registration_failures
		capture.hold_results=inject_async_capture_hold_results
		inject_async_capture_hold_results=false
		inject_async_capture_registration_failures=0
		result=await capture.capture()
	if not last_error.is_empty() and result.error.is_empty():result={"error":&"backend_failed_during_capture"}
	async_controller.frozen=false
	async_controller.transitioning=false
	async_checkpoint_running=false
	preview_suspended=was_preview_suspended
	if not shutdown_requested and not closing and last_error.is_empty():
		playing=was_playing
		input_scheduler.accepting=was_accepting
	return result

func save_gpu_checkpoint(path: String) -> StringName:
	if not async_pipeline_enabled:return await super.save_gpu_checkpoint(path)
	var captured:=await capture_async_checkpoint_data()
	if not captured.error.is_empty():return captured.error
	return AsyncCheckpoint.save(path,captured.checkpoint)

func restore_gpu_checkpoint(path: String) -> StringName:
	if not async_pipeline_enabled:return await super.restore_gpu_checkpoint(path)
	var source:=FileAccess.open(path,FileAccess.READ)
	if source==null:return &"open_failed"
	var magic:=source.get_buffer(8).get_string_from_ascii();source.close()
	if magic==Store.MAGIC:
		var legacy:=Store.load(path)
		if not legacy.error.is_empty():return legacy.error
		if legacy.enable_erosion!=enable_erosion:return &"pipeline_simulation_mismatch"
		return await restore_gpu_checkpoint_data(legacy.checkpoint)
	var loaded:=AsyncCheckpoint.load(path,source_signature)
	if not loaded.error.is_empty():return loaded.error
	return await restore_gpu_checkpoint_data(loaded.checkpoint)

func restore_gpu_checkpoint_data(checkpoint: Dictionary) -> StringName:
	if not async_pipeline_enabled:return await super.restore_gpu_checkpoint_data(checkpoint)
	if async_checkpoint_running or beach_restore_running or gpu_save_running or async_legacy_running:return &"transition_busy"
	if shutdown_requested or closing:return &"closing"
	if not async_backend_ready or not last_error.is_empty():return &"backend_failed"
	if checkpoint.has("gpu_beach_edit"):
		var migration:=AsyncMigration.convert(self,checkpoint)
		if not migration.error.is_empty():return migration.error
		var restored: StringName=await restore_gpu_checkpoint_data(migration.checkpoint)
		if restored.is_empty():
			async_last_migration=migration.provenance
		return restored
	# Validate the private input before changing admission, metadata or live RIDs.
	checkpoint=checkpoint.duplicate(true)
	var error:=AsyncCheckpoint.validate(checkpoint,source_signature)
	if not error.is_empty():return error
	if checkpoint.domain_id!=String(_domain_id()):return &"pipeline_domain_mismatch"
	var requested: Dictionary=checkpoint.simulation.duplicate()
	var actual:=_async_snapshot_simulation_configuration()
	requested.erase("prescribed_tide_boundary");actual.erase("prescribed_tide_boundary")
	if requested!=actual:return &"pipeline_simulation_mismatch"
	var gravel_projection={"visual_extensions":checkpoint.visual_extensions,"shadow":{"domain_id":checkpoint.domain_id,"generation":checkpoint.generation},"tick":checkpoint.sim_tick,"revision":checkpoint.revision}
	error=GravelCodec.validate(gravel_projection,gravel_profile,String(_domain_id()))
	if not error.is_empty():return error
	if checkpoint.visual_extensions.gravel_v1.enabled!=gravel_enabled:return &"gravel_profile_mismatch"
	error=_checkpoint_runtime_profile_error()
	if not error.is_empty():return error
	if maxi(generation,checkpoint.generation)==9223372036854775807:return &"generation_exhausted"
	var was_playing:=_async_requested_playing()
	var was_accepting: bool=_async_requested_accepting()
	var was_preview_suspended:=preview_suspended
	beach_restore_running=true
	beach_restore_phase="draining"
	playing=false;input_scheduler.accepting=false;preview_suspended=true;gpu_brush=&""
	await _async_close_interaction()
	playing=false;input_scheduler.accepting=false
	while last_error.is_empty() and (async_legacy_running or async_controller.legacy or gravel_drop_pending or not command_queue.pending.is_empty() or not async_controller.idle(true)):
		if not async_legacy_running and not async_controller.transitioning and not command_queue.pending.is_empty() and not async_controller.ordinary(command_queue.pending[0]):await _async_drain_legacy_front()
		await get_tree().process_frame
	async_controller.transitioning=true
	async_controller.frozen=true
	ready_for_ticks=false
	while preview_request_in_flight or gravel_drop_pending or collision_proxy.staging_texture.is_valid() or not collision_proxy.pending_revisions.is_empty() or collision_proxy.has_prepare_in_flight():await get_tree().process_frame
	var profiler=get_node_or_null("Interface/PerformancePanel")
	var profiler_processing: bool=profiler!=null and profiler.is_processing()
	if profiler!=null:await profiler.stop_sampling()
	if not last_error.is_empty() or shutdown_requested:
		return _async_restore_finish(&"closed_or_failed_before_build",was_playing,was_accepting,was_preview_suspended,profiler_processing)
	var next_generation: int=maxi(generation,checkpoint.generation)+1
	var candidate_domain=AsyncRestore.domain_from(checkpoint,next_generation)
	beach_restore_candidate=AsyncRestore.new()
	beach_restore_candidate.inject_registration_failures=inject_async_candidate_registration_failures
	beach_restore_candidate.inject_terminal_unavailable=inject_async_candidate_terminal_unavailable
	beach_restore_candidate.inject_build_failure_phase=inject_async_candidate_build_failure_phase
	beach_restore_candidate.hold_results=inject_async_candidate_hold_results
	inject_async_candidate_hold_results=false
	inject_async_candidate_registration_failures=0;inject_async_candidate_terminal_unavailable=false;inject_async_candidate_build_failure_phase=""
	beach_restore_phase="building"
	RenderingServer.call_on_render_thread(_render_async_restore_build.bind(checkpoint,candidate_domain))
	while not beach_restore_candidate.done or beach_restore_candidate.pending>0:await get_tree().process_frame
	error=beach_restore_candidate.error
	beach_restore_verifications.append({"expected":beach_restore_candidate.expected.size(),"observed":beach_restore_candidate.observed.size(),"pending":beach_restore_candidate.pending,"error":String(error)})
	if beach_restore_verifications.size()>128:beach_restore_verifications.pop_front()
	if inject_beach_restore_failure:
		inject_beach_restore_failure=false
		if error.is_empty():error=&"candidate_injected_failure"
	if shutdown_requested:error=&"closed_before_restore_commit"
	if not last_error.is_empty():error=&"backend_failed_during_restore"
	if not error.is_empty():
		if not await _async_discard_candidate():
			return _async_restore_finish(&"candidate_ownership_unconfirmed",was_playing,was_accepting,was_preview_suspended,profiler_processing)
		beach_restore_candidate=null
		return _async_restore_finish(error,was_playing,was_accepting,was_preview_suspended,profiler_processing)
	var controller=beach_restore_candidate.controller
	controller.state_seq=checkpoint.state_seq;controller.actual_time=checkpoint.advanced_time_s
	controller.accepted_commands=checkpoint.native.control.decode_u32(72);controller.rejected_commands=checkpoint.native.control.decode_u32(76)
	controller.nominal_upper_supply=checkpoint.nominal_upper_supply
	controller.wave_start_times=checkpoint.wave_start_times.duplicate(true)
	controller.transitioning=true
	# Admission stays closed through metadata, publication and physics rebuild.
	async_controller.slots.stop_admission()
	async_controller.ready=false
	generation=next_generation;shadow_domain=candidate_domain;completed_ticks=checkpoint.sim_tick
	command_queue=CommandQueue.new(shadow_domain);command_queue.last_command_id=checkpoint.highwater_id
	input_scheduler=_create_input_scheduler();input_scheduler.accepting=false
	input_serial=checkpoint.highwater_id;ticket_id=checkpoint.ticket_id
	water_policy=checkpoint.selection.policy;signed_speed_m_s=checkpoint.selection.speed
	sand_cohesion_yield_height_m=checkpoint.cohesion_yield_height_m
	initial_sand_total_m3=checkpoint.initial_sand_total_m3
	wave_requests.clear()
	for original in checkpoint.wave_requests:
		var wave: Dictionary=original.duplicate(true);wave.generation=generation;wave_requests.append(wave)
	wave_highwater_id=checkpoint.wave_highwater_id
	visual_time_s=checkpoint.advanced_time_s
	gpu_prefix.clear();input_events.clear();input_results.clear();input_rejections.clear();collision_needed.clear()
	shadow_revision=checkpoint.revision;shadow_sand_revision=checkpoint.revision
	preview_cache_key="";preview_cache.clear()
	shape_baseline_token=0;shape_stroke_id=0;shape_accepting=false
	replay_checkpoint.clear();replay_target_tick=-1;replay_ready=false;replay_collision_requested=false
	accumulator=0.0;audit_sand_revision=-1
	beach_restore_phase="metadata_committed";beach_restore_commit_done=false
	RenderingServer.call_on_render_thread(_render_async_restore_commit)
	while not beach_restore_commit_done:await get_tree().process_frame
	if not last_error.is_empty():
		controller._fail_pipeline("owner_failed:"+last_error,false)
		beach_restore_candidate=null
		return _async_restore_finish(&"backend_failed_after_restore_commit",was_playing,was_accepting,was_preview_suspended,profiler_processing)
	controller.ready=true
	controller.collision.mark_all()
	while not controller.idle(true) and last_error.is_empty():await get_tree().process_frame
	beach_restore_candidate=null
	if not last_error.is_empty():return _async_restore_finish(&"backend_failed_during_collision_rebuild",was_playing,was_accepting,was_preview_suspended,profiler_processing)
	beach_restore_phase="complete"
	_apply_brush_selection(checkpoint.selection.brush)
	_update_gravel_aabb()
	if not refresh_effective_render_profile():error=&"restore_profile_failed"
	return _async_restore_finish(error,was_playing,was_accepting,was_preview_suspended,profiler_processing)

func _render_async_restore_build(checkpoint: Dictionary, candidate_domain) -> void:
	if not beach_restore_candidate.build_async(self,checkpoint,candidate_domain) and beach_restore_candidate.error.is_empty():beach_restore_candidate.error=StringName("candidate_build_failed/"+beach_restore_candidate.build_phase)
	beach_restore_candidate.done=true

func _render_async_restore_discard() -> void:
	beach_restore_candidate.release()

func _async_candidate_terminal(bundle, confirmed: bool) -> void:
	if bundle!=beach_restore_candidate or bundle.released:return
	bundle.terminal_pending=false
	bundle.unconfirmed_ownership=not confirmed
	if confirmed:
		bundle.terminal_done=true
		bundle.terminal_proofs+=1
	else:_fail("GPU pipeline fatal: candidate terminal ownership unavailable")

func _async_discard_candidate() -> bool:
	beach_restore_candidate.discard_request_started=false
	RenderingServer.call_on_render_thread(beach_restore_candidate.request_discard.bind(self))
	while not beach_restore_candidate.discard_request_started:await get_tree().process_frame
	while not beach_restore_candidate.released:
		if beach_restore_candidate.unconfirmed_ownership and not beach_restore_candidate.terminal_pending:return false
		if beach_restore_candidate.terminal_done and beach_restore_candidate.pending==0 and not beach_restore_candidate.release_queued:
			beach_restore_candidate.release_queued=true
			RenderingServer.call_on_render_thread(_render_async_restore_discard)
		await get_tree().process_frame
	return true

func retry_async_candidate_cleanup() -> bool:
	if beach_restore_candidate==null:return true
	# Retry proof registration only. No candidate construction or simulation is
	# repeated, and a failed live pipeline never becomes ready through cleanup.
	if not await _async_discard_candidate():return false
	beach_restore_candidate=null
	return true

func _render_async_restore_commit() -> void:
	var old=AsyncRestore.new()
	for key in ["solver","foam_field","local_front_field","sand_audit","sediment_coupler","material_coupler","stable_q","gravel_field","shape_gpu","preview_query"]:old.set(key,get(key))
	old.controller=async_controller
	old.collision={"shader":collision_proxy.shader,"pipeline":collision_proxy.pipeline,"chunk_buffer":collision_proxy.chunk_buffer,"uniform_set":collision_proxy.uniform_set}
	preview_baseline.texture_rd_rid=RID()
	var candidate=beach_restore_candidate
	for key in ["solver","foam_field","local_front_field","sand_audit","sediment_coupler","material_coupler","stable_q","gravel_field","shape_gpu","preview_query"]:set(key,candidate.get(key))
	async_controller=candidate.controller
	collision_proxy.solver=solver;collision_proxy.rd=solver.rd;collision_proxy.generation=generation
	collision_proxy.shader=candidate.collision.shader;collision_proxy.pipeline=candidate.collision.pipeline;collision_proxy.chunk_buffer=candidate.collision.chunk_buffer;collision_proxy.uniform_set=RID()
	collision_proxy.applied_revisions.clear();collision_proxy.applied_usec.clear();collision_proxy.applied_stage_usec.clear()
	async_clock_wrapper.texture_rd_rid=solver.async_transport.clock_texture
	_bind_async_textures_render()
	native_restore_complete=true
	gravel_initialization="restored" if gravel_field!=null else "disabled"
	old.release()
	# Transfer ownership, so discarding the empty holder cannot release live RIDs.
	for key in ["solver","foam_field","local_front_field","sand_audit","sediment_coupler","material_coupler","gravel_field","shape_gpu","preview_query","controller"]:candidate.set(key,null)
	candidate.stable_q={};candidate.collision={}
	call_deferred("_async_restore_published")

func _async_restore_published() -> void:
	beach_restore_commit_done=true
	if inject_async_restore_failure_after_publish:
		inject_async_restore_failure_after_publish=false
		_fail("GPU pipeline fatal: restore publication boundary")

func _async_restore_finish(error: StringName, was_playing: bool, was_accepting: bool, was_preview_suspended: bool, profiler_processing: bool) -> StringName:
	async_controller.frozen=false;async_controller.transitioning=false
	beach_restore_running=false
	ready_for_ticks=not shutdown_requested and not closing and last_error.is_empty()
	input_scheduler.accepting=was_accepting and ready_for_ticks
	playing=was_playing and ready_for_ticks
	preview_suspended=was_preview_suspended
	var profiler=get_node_or_null("Interface/PerformancePanel")
	if profiler!=null:profiler.set_process(profiler_processing and ready_for_ticks)
	beach_restore_events.append({"error":String(error),"phase":beach_restore_phase,"generation":generation,"tick":completed_ticks})
	if beach_restore_events.size()>128:beach_restore_events.pop_front()
	_update_manual_wave_ui()
	return error

func shutdown() -> void:
	if async_pipeline_enabled and async_controller!=null:
		if gpu_release_done:return
		if async_shutdown_running:
			while async_shutdown_running:await get_tree().process_frame
			return
		async_shutdown_running=true
		shutdown_requested=true
		async_shutdown_error=&""
		while async_fault_probe_running or async_terminal.pending:await get_tree().process_frame
		if _async_ownership_unconfirmed():
			async_shutdown_error=&"ownership_unconfirmed";async_shutdown_running=false;return
		# Failed/bootstrap owners cannot admit more packs. Healthy accepted tools
		# still need their publication/collision boundary before normal closure.
		if not async_backend_ready or not last_error.is_empty():
			collision_proxy.closing=true
			collision_proxy.pending_revisions.clear()
		while not async_controller.fault_reason.is_empty() and not async_controller.records.is_empty():
			if _async_ownership_unconfirmed():
				async_shutdown_error=&"ownership_unconfirmed"
				async_shutdown_running=false
				return
			await get_tree().process_frame
		while not async_shadow_jobs.is_empty() or async_checkpoint_running or beach_restore_running or not async_capture_owners.is_empty() or (beach_restore_candidate!=null and beach_restore_candidate.discard_requested and not beach_restore_candidate.released):
			if _async_ownership_unconfirmed():
				async_shutdown_error=&"ownership_unconfirmed";async_shutdown_running=false;return
			await get_tree().process_frame
		var profiler=get_node_or_null("Interface/PerformancePanel")
		if profiler!=null:await profiler.stop_sampling()
		playing=false
		input_scheduler.accepting=false
		input_scheduler.cancel_pending("closed")
		async_controller.explicit_ticks=0
		await _async_close_interaction()
		while async_legacy_running or legacy_command_running or input_running or input_scheduler.pumping or gpu_busy or gravel_drop_pending or ui_pump_running:
			if _async_ownership_unconfirmed():
				async_shutdown_error=&"ownership_unconfirmed";async_shutdown_running=false;return
			input_scheduler.cancel_pending("closed")
			await get_tree().process_frame
		input_scheduler.cancel_pending("closed")
		collision_proxy.closing=true
		collision_proxy.pending_revisions.clear()
		async_controller.transitioning=true
		while not async_controller.idle():
			if _async_ownership_unconfirmed():
				async_shutdown_error=&"ownership_unconfirmed";async_shutdown_running=false;return
			await get_tree().process_frame
		async_controller.slots.stop_admission()
		async_controller.frozen=true
		async_controller.collision.closing=true
		async_controller.collision.pending.clear()
		while async_controller.collision.active_count()>0:await get_tree().process_frame
		while collision_proxy.staging_texture.is_valid() or collision_proxy.failed_readback_owned or collision_proxy.terminal_running:
			if _async_ownership_unconfirmed():
				async_shutdown_error=&"ownership_unconfirmed";async_shutdown_running=false;return
			await get_tree().process_frame
		await collision_proxy.stop_prepare_and_drain()
		# Native receipts can enqueue finalize/rollback after a CPU coroutine has
		# returned its error. Wait those consumers before the final ordered proof.
		while (solver!=null and solver.receipt_pending) or preview_request_in_flight or (shape_gpu!=null and shape_gpu.finalize_pending>0):await get_tree().process_frame
		async_terminal.begin("final")
		while async_terminal.pending:await get_tree().process_frame
		if async_terminal.unconfirmed_ownership:
			if last_error.is_empty():_fail("GPU pipeline fatal: final stream ownership unavailable")
			async_shutdown_error=&"ownership_unconfirmed";async_shutdown_running=false;return
		await get_tree().process_frame
		async_controller.ready=false
	await super.shutdown()
	async_shutdown_running=false

func _render_release() -> void:
	if async_pipeline_enabled and async_controller!=null:
		if _async_has_external_owners():return
		if not async_controller.release_render():call_deferred("_retry_gpu_release");return
		if not async_terminal.release_render():return
		async_backend_ready=false
		async_clock_wrapper.texture_rd_rid=RID()
		for material in [terrain_material,water_material]:material.set_shader_parameter("use_async_clock",false)
	super._render_release()

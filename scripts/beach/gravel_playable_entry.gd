extends "res://scripts/beach/shape_brush_playable_entry.gd"

const GravelField = preload("res://scripts/visual/gpu_gravel_field.gd")
const GravelCodec = preload("res://scripts/visual/gravel_checkpoint_codec.gd")
@export var gravel_enabled := true
@export_range(0,1024) var gravel_count := 512
var gravel_field
var gravel_profile := {}
var gravel_wrapper := Texture2DRD.new()
var gravel_spirv: RDShaderSPIRV
var gravel_initialization := "seeded"
var gravel_capture_ready := false
var gravel_capture_states := {}
var gravel_held_fields := []
var gravel_capture_id := 0
var gravel_capture_callbacks := 0
var gravel_callback_requests := {}
var gravel_last_bound_source := -INF
var gravel_last_bound_generation := -1
var gravel_drop_pending := false
var gravel_drop_result := {}
var gravel_dragging := false
var gravel_drag_point := Vector3.ZERO
@onready var gravel_layer: MultiMeshInstance3D = $GravelLayer

func _runtime_configuration_signature() -> Dictionary:
	var signature := super._runtime_configuration_signature()
	# Presentation profile is validated separately. Authority signature remains
	# identical for paired on/off runs, while the visual asset identity is saved.
	_index_sources("res://assets/gravel",signature.sources)
	signature.sources["res://shaders/visual/gpu_gravel.gdshader"] = FileAccess.get_sha256("res://shaders/visual/gpu_gravel.gdshader")
	return signature

func _prepare_legacy_checkpoint(checkpoint: Dictionary) -> Dictionary:
	var extensions: Variant=checkpoint.get("visual_extensions",{})
	if not extensions is Dictionary or extensions.has("gravel_v1"): return checkpoint
	var edit: Variant=checkpoint.get("gpu_beach_edit")
	if not edit is Dictionary: return checkpoint
	var known: Variant = bytes_to_var(FileAccess.get_file_as_bytes("res://assets/gravel/legacy_configuration_20261015.bin"))
	if edit.get("configuration") != known: return checkpoint
	# Exact, recorded pre-gravel release only. Unrelated signature mismatches
	# retain the existing rejection; no arbitrary old-source substitution.
	var migrated := checkpoint.duplicate(true)
	migrated.gpu_beach_edit.configuration = source_signature.duplicate(true) if not source_signature.is_empty() else _runtime_configuration_signature()
	gravel_initialization = "legacy_seeded"
	return migrated

func _ready() -> void:
	gravel_profile = GravelField.default_profile(scene_key,gravel_count)
	gravel_profile.bed_reconstruction = render_subdivision>1
	if not replay_checkpoint.is_empty():
		replay_checkpoint = _prepare_legacy_checkpoint(replay_checkpoint)
		var error := _validate_gravel(replay_checkpoint)
		if not error.is_empty(): _fail(String(error)); return
	gravel_layer.multimesh = _private_gravel_multimesh(gravel_layer.multimesh)
	gravel_layer.material_override = load("res://assets/gravel/stone_material.tres").duplicate(true)
	gravel_layer.multimesh.visible_instance_count = gravel_count if gravel_enabled else 0
	gravel_layer.visible = gravel_enabled and gravel_count>0
	gravel_layer.layers = 5 if gravel_enabled and gravel_count>0 else 1
	for key in ["seed","radius_min_m","radius_max_m"]:
		gravel_layer.material_override.set_shader_parameter(key,gravel_profile[key])
	gravel_layer.material_override.set_shader_parameter("particle_state",gravel_wrapper)
	super._ready()
	_update_gravel_aabb()

func _private_gravel_multimesh(source: MultiMesh) -> MultiMesh:
	# MultiMesh format flags must be assigned before allocating instances.
	# Generic scene-local duplication may restore instance_count first.
	var result:=MultiMesh.new()
	result.transform_format=source.transform_format
	result.use_colors=source.use_colors
	result.use_custom_data=source.use_custom_data
	result.mesh=source.mesh
	result.instance_count=source.instance_count
	result.buffer=source.buffer
	result.visible_instance_count=source.visible_instance_count
	result.custom_aabb=source.custom_aabb
	return result

func _process(delta: float) -> void:
	super._process(delta)
	_update_gravel_aabb()
	if gravel_field != null:
		gravel_layer.multimesh.visible_instance_count = gravel_field.active_count
		gravel_layer.visible = gravel_enabled and gravel_field.active_count > 0
		gravel_layer.layers = 5 if gravel_layer.visible else 1

func _start_tick() -> void:
	if gravel_drop_pending: return
	super._start_tick()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (not event.pressed or event.button_index == MOUSE_BUTTON_RIGHT): gravel_dragging = false
	if event is InputEventKey and event.pressed and event.keycode in [KEY_ESCAPE, KEY_SPACE]: gravel_dragging = false
	super._input(event)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT: gravel_dragging = false
	super._notification(what)

func _on_ui_tool_changed(tool: StringName) -> void:
	gravel_dragging = false
	super._on_ui_tool_changed(tool)

func _on_ui_parameters_changed() -> void:
	gravel_dragging = false
	super._on_ui_parameters_changed()

func _unhandled_input(event: InputEvent) -> void:
	if ui_tool != &"gravel_drop" or event is InputEventKey:
		super._unhandled_input(event)
		return
	if preview_suspended or ui_closing or closing or shutdown_requested or _scene_switch_busy() or player_camera.look_active: return
	var pressed: bool = event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed
	var dragged: bool = event is InputEventMouseMotion and gravel_dragging
	if not pressed and not dragged: return
	if _over_gui(event.position): gravel_dragging = false; return
	var hit := pick(event.position)
	if hit.is_empty() or not _pick_current(hit): gravel_dragging = false; return
	if pressed or hit.position.distance_to(gravel_drag_point) >= 0.6:
		if gravel_drop_pending and not ("async_pipeline_enabled" in self and get("async_pipeline_enabled")): return
		gravel_dragging = true
		gravel_drag_point = hit.position
		drop_gravel(Vector2(hit.position.x, hit.position.z), int(brush_panel.parameters().count))
	get_viewport().set_input_as_handled()

func drop_gravel(point: Vector2, count: int) -> Dictionary:
	if not gravel_enabled or not ready_for_ticks or gravel_drop_pending or closing or shutdown_requested or _scene_switch_busy() or gpu_save_running or beach_restore_running or checkpoint_capture_pending:
		return {"error": &"backend_unavailable"}
	if not point.is_finite() or count < 1 or count > 128 or absf(point.x) > 15.55 or absf(point.y) > 15.55:
		return {"error": &"out_of_domain"}
	gravel_drop_pending = true
	gravel_drop_result = {}
	var token := generation
	# Stop admitting new ticks, let the previous complete state and edits settle.
	while (busy or input_running or ui_pump_running or not command_queue.pending.is_empty()) and not closing and not shutdown_requested and last_error.is_empty(): await get_tree().process_frame
	if not closing and not shutdown_requested and last_error.is_empty() and generation == token:
		RenderingServer.call_on_render_thread(_render_drop_gravel.bind(point, count, token))
		while gravel_drop_result.is_empty() and not closing and last_error.is_empty(): await get_tree().process_frame
	var result := gravel_drop_result.duplicate()
	gravel_drop_pending = false
	if result.is_empty(): result = {"error": &"backend_unavailable"}
	if ui_tool == &"gravel_drop":
		if result.get("ok", false): brush_panel.show_status("已投 %d 颗 · 共 %d / 1024" % [count, result.active_count])
		else: brush_panel.show_status("容量不足，剩余 %d 颗；请减小数量" % (1024-result.active_count) if result.get("error") == &"gravel_capacity_full" else "暂时无法投放，请稍后重试", &"invalid")
	return result

func _render_drop_gravel(point: Vector2, count: int, token: int) -> void:
	var error: StringName = &"gravel_state_invalid"
	if token == generation and gravel_field != null and not closing:
		error = gravel_field.add_at(solver, point, count, token, completed_ticks, solver.state_revision)
		if error.is_empty(): gravel_wrapper.texture_rd_rid = gravel_field.current_texture()
	call_deferred("_gravel_drop_finished", error, token)

func _gravel_drop_finished(error: StringName, token: int) -> void:
	gravel_drop_result = {"ok": error.is_empty(), "error": error, "active_count": gravel_field.active_count if gravel_field != null else 0, "generation": token}

func _update_gravel_aabb() -> void:
	if shadow_domain==null or not is_instance_valid(gravel_layer): return
	var source: float = shadow_domain.sand_source_m3
	if source==gravel_last_bound_source and generation==gravel_last_bound_generation: return
	gravel_last_bound_source=source
	gravel_last_bound_generation=generation
	var low: float = Array(shadow_domain.rock).min()-0.1
	# Any nonnegative cell's sand is bounded by the whole initial sand and all
	# external additions. Deliberately loose; no per-particle height readback.
	var high: float = Array(shadow_domain.rock).max()+(maxf(initial_sand_total_m3,shadow_domain.total_sand_m3(true))+maxf(source,0.0))/(CELL_SIZE_M*CELL_SIZE_M)+0.2
	gravel_layer.multimesh.custom_aabb = AABB(Vector3(-16.1,low,-16.1),Vector3(32.2,maxf(high-low,1.0),32.2))

func _compile_gravel() -> bool:
	if gravel_spirv!=null: return true
	var source := RDShaderSource.new()
	source.source_compute=FileAccess.get_file_as_string("res://shaders/simulation/visual_gravel_step.glsl").replace("#[compute]","")
	gravel_spirv=RenderingServer.get_rendering_device().shader_compile_spirv_from_source(source)
	return gravel_spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE).is_empty()

func _new_gravel(target_solver, token: int, tick: int, state_revision: int, checkpoint: Dictionary):
	if not gravel_enabled: return null
	if not _compile_gravel(): return null
	var restore: Dictionary = checkpoint.get("visual_extensions",{}).get("gravel_v1",{})
	if not restore.get("enabled",false): restore={}
	var field=GravelField.new()
	if not field.initialize(target_solver,gravel_spirv,gravel_profile,token,tick,state_revision,restore): return null
	return field

func _dispatch_completed_visual_tick(target_tick: int, state_revision: int, token: int, dt: float) -> bool:
	if not super._dispatch_completed_visual_tick(target_tick,state_revision,token,dt): return false
	if not gravel_enabled: return true
	return gravel_field!=null and gravel_field.advance(solver,target_tick,state_revision,token,dt)

func _publish_textures() -> void:
	if replay_checkpoint.has("gpu_beach_native") and not native_restore_complete: return
	if not solver._may_publish(): return
	if gravel_enabled:
		if gravel_field==null:
			gravel_field=_new_gravel(solver,generation,completed_ticks,solver.state_revision,replay_checkpoint)
			if gravel_field==null: call_deferred("_fail","gravel_initialize_failed"); return
			gravel_initialization="restored" if replay_checkpoint.get("visual_extensions",{}).get("gravel_v1",{}).get("enabled",false) else ("legacy_seeded" if not replay_checkpoint.is_empty() else "seeded")
		elif gravel_field.revision!=solver.state_revision:
			if not gravel_field.reproject(solver,completed_ticks,solver.state_revision,generation): call_deferred("_fail","gravel_reproject_failed"); return
		gravel_wrapper.texture_rd_rid=gravel_field.current_texture()
	super._publish_textures()

func _validate_gravel(checkpoint: Dictionary) -> StringName:
	var error := GravelCodec.validate(checkpoint,gravel_profile,String(_domain_id()))
	if not error.is_empty(): return error
	var enabled: bool = checkpoint.get("visual_extensions",{}).get("gravel_v1",{}).get("enabled",gravel_enabled)
	if enabled!=gravel_enabled: return &"gravel_profile_mismatch"
	return &""

func _validate_checkpoint_extensions(checkpoint: Dictionary) -> StringName:
	var error := super._validate_checkpoint_extensions(checkpoint)
	return _validate_gravel(checkpoint) if error.is_empty() else error

func restore_gpu_checkpoint_data(checkpoint: Dictionary) -> StringName:
	while gravel_drop_pending: await get_tree().process_frame
	checkpoint=_prepare_legacy_checkpoint(checkpoint)
	var error := _validate_gravel(checkpoint)
	if not error.is_empty(): return error
	return await super.restore_gpu_checkpoint_data(checkpoint)

func save_gpu_checkpoint(path: String) -> StringName:
	while gravel_drop_pending: await get_tree().process_frame
	return await super.save_gpu_checkpoint(path)

func _start_checkpoint_capture() -> void:
	gravel_capture_ready=false
	gravel_capture_states.clear()
	gravel_held_fields.clear()
	gravel_capture_id+=1
	super._start_checkpoint_capture()

func _render_capture_checkpoint(state_revision: int, token: int) -> void:
	if closing or token!=generation or solver.state_revision!=state_revision: return
	if gravel_enabled:
		gravel_capture_callbacks+=2
		gravel_callback_requests[str(token)+"/"+str(gravel_capture_id)]=2
		gravel_field.capture_async(_on_gravel_capture,gravel_capture_id)
	else:
		call_deferred("_gravel_capture_disabled",token,gravel_capture_id)
	super._render_capture_checkpoint(state_revision,token)

func _on_gravel_capture(bytes: PackedByteArray, key: String, identity: Dictionary) -> void:
	call_deferred("_gravel_capture_received",bytes,key,identity)

func _gravel_capture_disabled(token: int, request_id: int) -> void:
	if token!=generation or request_id!=gravel_capture_id or closing or not checkpoint_capture_pending: return
	checkpoint_capture.visual_extensions={"gravel_v1":{"version":1,"enabled":false}}
	_finish_gravel_capture()

func _gravel_capture_received(bytes: PackedByteArray, key: String, identity: Dictionary) -> void:
	var request := str(identity.generation)+"/"+str(identity.request_id)
	if not gravel_callback_requests.has(request): return
	gravel_capture_callbacks-=1
	gravel_callback_requests[request]-=1
	if gravel_callback_requests[request]==0: gravel_callback_requests.erase(request)
	if identity.generation!=generation or identity.request_id!=gravel_capture_id or closing or not checkpoint_capture_pending: return
	if bytes.size()!=16384 or identity.tick!=checkpoint_capture.tick or identity.revision!=checkpoint_capture.revision:
		last_save_error=&"gravel_capture_failed";pending_save_path="";checkpoint_capture_pending=false;checkpoint_capture.clear();return
	gravel_capture_states[key]=bytes
	if gravel_capture_states.size()==2:
		checkpoint_capture.visual_extensions={"gravel_v1":GravelCodec.extension(gravel_field,String(_domain_id()),gravel_capture_states)}
		_finish_gravel_capture()

func _finish_gravel_capture() -> void:
	gravel_capture_ready=true
	var held := gravel_held_fields
	gravel_held_fields=[]
	for item in held: super._checkpoint_field_ready(item.bytes,item.field,item.revision,item.token)

func _checkpoint_field_ready(bytes: PackedByteArray, field: String, state_revision: int, token: int) -> void:
	if not gravel_capture_ready:
		if token==generation and checkpoint_capture_pending:
			gravel_held_fields.append({"bytes":bytes,"field":field,"revision":state_revision,"token":token})
		return
	super._checkpoint_field_ready(bytes,field,state_revision,token)

func _render_beach_restore_build(checkpoint: Dictionary, candidate_domain) -> void:
	super._render_beach_restore_build(checkpoint,candidate_domain)
	var bundle=beach_restore_candidate
	if not bundle.error.is_empty() or not gravel_enabled: return
	bundle.gravel_field=_new_gravel(bundle.solver,candidate_domain.generation,checkpoint.tick,checkpoint.revision,checkpoint)
	if bundle.gravel_field==null: bundle.error=&"gravel_restore_failed";return
	var ext: Dictionary=checkpoint.get("visual_extensions",{}).get("gravel_v1",{})
	bundle.gravel_initialization="restored" if ext.get("enabled",false) else "legacy_seeded"
	if ext.get("enabled",false):
		for index in 2: bundle._verify(self,bundle.gravel_field.textures[index],"gravel_%d" % index,ext["state_%d" % index])

func _render_beach_restore_commit() -> void:
	var old=gravel_field
	var initialization: String=beach_restore_candidate.gravel_initialization
	gravel_wrapper.texture_rd_rid=RID()
	gravel_field=beach_restore_candidate.gravel_field
	beach_restore_candidate.gravel_field=null
	# Commit has begun; release old dependent uniforms before its solver.
	if old!=null: old.release()
	super._render_beach_restore_commit()
	gravel_initialization=initialization if gravel_field!=null else "disabled"

func shutdown() -> void:
	if gpu_release_done: return
	shutdown_requested=true
	playing=false
	# A restore owns independent candidate resources and deferred callbacks.
	# Let its abort path settle and discard them before the scene can be freed.
	while beach_restore_running or gravel_capture_callbacks>0 or gravel_drop_pending: await get_tree().process_frame
	await super.shutdown()

func _render_release() -> void:
	if gravel_capture_callbacks>0 or (gravel_field!=null and gravel_field.pending>0): call_deferred("_retry_gpu_release");return
	gravel_wrapper.texture_rd_rid=RID()
	if gravel_field!=null: gravel_field.release();gravel_field=null
	super._render_release()

extends "res://scripts/beach/beach_playable_entry.gd"

const BrushQueue = preload("res://scripts/sand/brushes/brush_command_queue.gd")
const BrushScheduler = preload("res://scripts/simulation/brushes/brush_scheduler.gd")
const BrushProtocol = preload("res://scripts/simulation/brushes/brush_protocol.gd")
const Stroke = preload("res://scripts/sand/brushes/stroke_controller.gd")
const ShapeGPU = preload("res://scripts/simulation/brushes/brush_gpu.gd")
var shape_backend_ready := false
var shape_baseline_token := 0
var shape_stroke_id := 0
var shape_accepting := false
var stroke_controller = Stroke.new()
var shape_gpu
var _shape_serial := 0
var _baseline_result: Variant = null
var _baseline_end_result: Variant = null
var _restore_shape_candidate
@export var enable_brush_native_material := false
@export var enable_brush_checkpoint_v4 := false
@export var enable_brush_water := false
var _capture_material_enabled := false
var brush_save_request_pending:=false

func _runtime_configuration_signature() -> Dictionary:
	var signature:=super._runtime_configuration_signature()
	if enable_brush_native_material:
		signature["brush_native_material_enabled"]=true
		for path in ["res://assets/brushes","res://scripts/sand/brushes"]: _index_sources(path,signature.sources)
	if enable_brush_checkpoint_v4:signature["brush_checkpoint_v4_enabled"]=true
	if enable_brush_water:signature["brush_water_enabled"]=true
	return signature

func _supports_edit_version(version:int) -> bool:
	return version==4 if enable_brush_checkpoint_v4 else super._supports_edit_version(version)

func _ready() -> void:
	if enable_brush_checkpoint_v4 and (not enable_brush_native_material or not unrestricted_sand_tools):_fail("brush v4 requires material native and external accounting");return
	super._ready()

func _prepare_prefix_record(record:Dictionary) -> Dictionary:
	if not enable_brush_checkpoint_v4:return super._prepare_prefix_record(record)
	record.backend="brush_v2" if record.command.get("schema_version")==2 else "legacy_v1"
	record.sand_accounting="external_v1";record.receipt_raw=gpu_receipt_raw.duplicate()
	if record.backend=="brush_v2":record.policy=record.command.water_policy;record.speed=record.command.speed_m_s
	return record

func _capture_brush_selection() -> Dictionary:
	return {"tool":String(selected_sand_tool),"parameters":{},"dig_amount_m3":dig_amount_m3,"fill_amount_m3":fill_amount_m3}

func _apply_brush_selection(selection:Dictionary) -> void:
	if selection.tool in [&"remove_sand",&"place_sand"]:selected_sand_tool=StringName(selection.tool)
	dig_amount_m3=selection.dig_amount_m3;fill_amount_m3=selection.fill_amount_m3

func _validate_checkpoint_extensions(candidate:Dictionary) -> StringName:
	var error:=super._validate_checkpoint_extensions(candidate)
	if not error.is_empty():return error
	if enable_brush_checkpoint_v4:return preload("res://scripts/simulation/brushes/brush_checkpoint_codec.gd").validate_edit(candidate,source_signature)
	return &""

func _supports_native_version(version: int) -> bool:
	return version==1 or (version==2 and enable_brush_native_material)

func _restore_native_extensions(target_solver, native: Dictionary) -> bool:
	if native.version==1: return true
	if not enable_brush_native_material or native.version!=2: return false
	return target_solver.restore_native_material(native.material,native.fields.sand,native.spare.sand,native.current_index)

func _start_checkpoint_capture() -> void:
	_capture_material_enabled=enable_brush_native_material
	super._start_checkpoint_capture()
	if enable_brush_checkpoint_v4 and not checkpoint_capture.is_empty():
		var edit:Dictionary=checkpoint_capture.gpu_beach_edit
		edit.version=4;edit.brush_schema=2;edit.selection.brush=_capture_brush_selection()
		for row in edit.prefix:
			if row.get("backend")=="legacy_cpu":row.sand_accounting="external_v1"

func _capture_native_extensions(revision: int, token: int) -> void:
	if not _capture_material_enabled: return
	_native_capture_request(solver.textures.mold_support[solver.current_index],"material_current",revision,token)
	_native_capture_request(solver.textures.mold_support[1-solver.current_index],"material_spare",revision,token)

func _native_capture_raw_count() -> int:
	return 24 if _capture_material_enabled else 22

func _is_native_extension_field(field: String) -> bool:
	return field in ["material_current","material_spare"]

func _assemble_native_record(fields: Dictionary, spare: Dictionary, foam: Dictionary) -> Dictionary:
	var native:=super._assemble_native_record(fields,spare,foam)
	if _capture_material_enabled:
		native.version=2
		native.material=preload("res://scripts/simulation/brushes/brush_material_state_codec.gd").make_record(capture_raw.material_current,capture_raw.material_spare,solver.mold_field_ever_used,material_coupler.profile_sha256)
	return native

func _make_gpu_editor():
	var editor=preload("res://scripts/simulation/edit_validation/frame_pipeline/editor.gd").new() if edit_frame_pipeline_enabled else preload("res://scripts/simulation/brushes/brush_material_solver.gd").new()
	editor.brush_water_enabled=enable_brush_water;return editor

func _create_material_coupler() -> SandcastleGpuMaterialCoupler:
	return preload("res://scripts/simulation/brushes/brush_material_coupler.gd").new()

func _mark_ready(token: int) -> void:
	if not shape_backend_ready or not last_error.is_empty(): return
	super._mark_ready(token)

func _render_setup(target: SandWaterDomain, token: int) -> void:
	super._render_setup(target,token)
	if solver == null or solver.rd == null or closing or token != generation: return
	shape_gpu = ShapeGPU.new()
	if not shape_gpu.initialize(solver): call_deferred("_fail","shape GPU initialize: "+shape_gpu.last_error); return
	call_deferred("_shape_ready",token)

func _shape_ready(token: int) -> void:
	if closing or token != generation: return
	shape_backend_ready = true
	_mark_ready(token)

func begin_shape_stroke(stroke: int) -> StringName:
	if not shape_backend_ready or not ready_for_ticks or busy or shape_stroke_id!=0 or not command_queue.pending.is_empty() or closing or shutdown_requested: return &"backend_unavailable"
	_shape_serial+=1; shape_baseline_token=_shape_serial; shape_stroke_id=stroke
	gpu_busy=true; _baseline_result=null
	RenderingServer.call_on_render_thread(_render_shape_begin.bind(stroke,shape_baseline_token,generation))
	while _baseline_result==null and last_error.is_empty() and not closing: await get_tree().process_frame
	gpu_busy=false
	if _baseline_result!=true: shape_baseline_token=0; shape_stroke_id=0; return &"invalid_baseline"
	shape_accepting=true
	return &""

func _render_shape_begin(stroke: int, baseline: int, epoch: int) -> void:
	if closing or epoch!=generation or shape_gpu==null or not shape_gpu.begin(stroke,baseline,_on_shape_baseline.bind(epoch,baseline)):
		call_deferred("_baseline_done",false,epoch,baseline)

func _on_shape_baseline(ok: bool, epoch: int, baseline: int) -> void:
	call_deferred("_baseline_done",ok,epoch,baseline)

func _baseline_done(ok: bool, epoch: int, baseline: int) -> void:
	if epoch==generation and baseline==shape_baseline_token: _baseline_result=ok

func end_shape_stroke() -> StringName:
	if shape_stroke_id==0: return &""
	shape_accepting=false
	while busy: await get_tree().process_frame
	await input_scheduler.drain_due()
	if not command_queue.pending.is_empty(): return &"backend_unavailable"
	_baseline_end_result=null
	gpu_busy=true
	RenderingServer.call_on_render_thread(_render_shape_end.bind(shape_baseline_token,generation))
	while _baseline_end_result==null and last_error.is_empty() and not closing: await get_tree().process_frame
	gpu_busy=false
	if _baseline_end_result!=true: return &"invalid_baseline"
	shape_stroke_id=0; shape_baseline_token=0
	return &""

func _render_shape_end(baseline: int, epoch: int) -> void:
	var ok: bool = epoch==generation and not closing and shape_gpu!=null and shape_gpu.end(baseline)
	call_deferred("_shape_end_done",ok,epoch,baseline)

func _shape_end_done(ok: bool, epoch: int, baseline: int) -> void:
	if epoch==generation and baseline==shape_baseline_token: _baseline_end_result=ok

func _encode_gpu_command(command: Dictionary, ticket: int, revision: int, selection: Dictionary, available: float) -> PackedByteArray:
	if command.get("schema_version")==2: return BrushProtocol.encode(command,ticket,revision)
	return super._encode_gpu_command(command,ticket,revision,selection,available)

func _render_gpu_command(data: PackedByteArray, token: int) -> void:
	if data.size()!=256: super._render_gpu_command(data,token); return
	if closing or token!=generation: return
	if shape_gpu==null or not shape_gpu.dispatch(data,_on_gpu_receipt.bind(token),completed_ticks): call_deferred("_fail","shape GPU dispatch failed")

func _settle_gpu_receipt(bytes: PackedByteArray, token: int) -> void:
	if pending_gpu_command.get("schema_version")!=2: super._settle_gpu_receipt(bytes,token); return
	if closing or token!=generation or gpu_settled or pending_gpu_command.is_empty(): return
	var receipt := BrushProtocol.decode_receipt(bytes)
	if not BrushProtocol.receipt_matches(receipt,pending_gpu_command,ticket_id,pending_gpu_revision) or receipt.get("applied_tick")!=completed_ticks:
		_fail("shape GPU receipt mismatch"); return
	if receipt.status==1:
		shadow_domain.sand_source_m3+=receipt.external_source_delta_m3
		shadow_domain.sand_sink_m3+=receipt.external_sink_delta_m3
		command_queue.applied_log.append(pending_gpu_command.duplicate(true))
		shadow_sand_revision=-1; shadow_revision=-1
		collision_needed.clear()
		for chunk in _gpu_chunks(receipt): collision_needed[chunk]=receipt.output_revision
	gpu_settled=true; gpu_receipt=receipt;gpu_receipt_raw=bytes.duplicate(); settle_us=Time.get_ticks_usec()
	_record_diagnostic(gpu_events,{"phase":"settled","backend":"brush_v2","at_us":settle_us,"revision":receipt.output_revision})

func request_checkpoint_save(path: String) -> StringName:
	if shape_stroke_id!=0: return &"brush_stroke_active"
	if solver!=null and solver.mold_field_ever_used and not enable_brush_native_material: return &"brush_native_checkpoint_not_implemented"
	if enable_brush_checkpoint_v4:
		if brush_save_request_pending or gpu_save_running or beach_restore_running or shutdown_requested or closing or not ready_for_ticks or FileAccess.file_exists(path):return &"backend_unavailable"
		brush_save_request_pending=true;_save_requested_brush_checkpoint(path);return &""
	return super.request_checkpoint_save(path)

func _save_requested_brush_checkpoint(path:String) -> void:
	last_save_error=&""
	var error:StringName=await save_gpu_checkpoint(path)
	last_save_error=error;brush_save_request_pending=false

func save_gpu_checkpoint(path: String) -> StringName:
	if shape_stroke_id!=0: return &"brush_stroke_active"
	if solver!=null and solver.mold_field_ever_used and not enable_brush_native_material: return &"brush_native_checkpoint_not_implemented"
	for item in gpu_prefix:
		if item.command.get("schema_version")==2 and not enable_brush_checkpoint_v4: return &"brush_checkpoint_not_implemented"
	return await super.save_gpu_checkpoint(path)

func restore_gpu_checkpoint_data(checkpoint: Dictionary) -> StringName:
	if shape_stroke_id!=0: return &"brush_stroke_active"
	checkpoint=checkpoint.duplicate(true)
	var error:StringName=await super.restore_gpu_checkpoint_data(checkpoint)
	if error.is_empty() and checkpoint.gpu_beach_edit.version==4:_apply_brush_selection(checkpoint.gpu_beach_edit.selection.brush)
	return error

func _render_beach_restore_build(checkpoint: Dictionary, candidate_domain) -> void:
	super._render_beach_restore_build(checkpoint,candidate_domain)
	if not beach_restore_candidate.error.is_empty(): return
	_restore_shape_candidate=ShapeGPU.new()
	if not _restore_shape_candidate.initialize(beach_restore_candidate.solver):
		beach_restore_candidate.error=&"brush_candidate_build_failed"

func _render_beach_restore_discard() -> void:
	if _restore_shape_candidate!=null:
		_restore_shape_candidate.release(); _restore_shape_candidate=null
	super._render_beach_restore_discard()

func _render_beach_restore_commit() -> void:
	# Both resource bundles were built before metadata/publication commit.
	shape_gpu.release()
	super._render_beach_restore_commit()
	shape_gpu=_restore_shape_candidate; _restore_shape_candidate=null
	shape_baseline_token=0; shape_stroke_id=0; shape_accepting=false

func _render_release() -> void:
	if shape_gpu!=null and not solver.receipt_pending:
		shape_gpu.release(); shape_gpu=null
	super._render_release()

func _create_input_scheduler():
	# Same queue and highwater owner as legacy tools, including after reattachment.
	var previous = command_queue
	command_queue = BrushQueue.new(shadow_domain)
	command_queue.last_command_id = previous.last_command_id
	command_queue.pending = previous.pending
	command_queue.applied_log = previous.applied_log
	command_queue.undo_stack = previous.undo_stack
	command_queue.redo_stack = previous.redo_stack
	var scheduler = BrushScheduler.new(self)
	scheduler.history_limit = DIAGNOSTIC_HISTORY_LIMIT
	return scheduler

func sand_command_available(command: Dictionary) -> float:
	if command.get("schema_version") == 2: return float(command.add_budget_m3)
	return super.sand_command_available(command)

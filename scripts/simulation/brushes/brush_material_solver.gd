extends "res://scripts/simulation/edit_validation/gpu_water_editor.gd"

# RG32F: tagged molded sand depth (m), reference total sand depth (m).
var mold_field_ever_used := false
var brush_water_enabled:=false
var legacy_material_transaction
var legacy_material_active := false
var legacy_dispatch_indirect := RID()
const MaterialState = preload("res://scripts/simulation/brushes/brush_material_state_codec.gd")

func initialize(p_rd: RenderingDevice, domain: SandWaterDomain,
		edge_spirv: RDShaderSPIRV, drain_spirv: RDShaderSPIRV,
		update_spirv: RDShaderSPIRV, tide_spirv: RDShaderSPIRV,
		cfl_spirv: RDShaderSPIRV, gauge_spirv: RDShaderSPIRV,
		audit_spirv: RDShaderSPIRV, edit_spirv: RDShaderSPIRV,
		initial_momentum_x := PackedFloat32Array(),initial_momentum_z := PackedFloat32Array()) -> bool:
	var bytes:=MaterialState.initial_values(domain.get_meta("brush_initial_mold_depth",PackedFloat32Array()),domain.sand)
	if bytes.is_empty(): return false
	if not super.initialize(p_rd,domain,edge_spirv,drain_spirv,update_spirv,tide_spirv,cfl_spirv,gauge_spirv,audit_spirv,edit_spirv,initial_momentum_x,initial_momentum_z): return false
	var values:=bytes.to_float32_array()
	for i in domain.sand.size(): mold_field_ever_used=mold_field_ever_used or values[i*2]>0.0
	textures["mold_support"]=[_create_texture(RenderingDevice.DATA_FORMAT_R32G32_SFLOAT,bytes),_create_texture(RenderingDevice.DATA_FORMAT_R32G32_SFLOAT,bytes)]
	if not textures.mold_support[0].is_valid() or not textures.mold_support[1].is_valid(): return false
	legacy_material_transaction=preload("res://scripts/simulation/brushes/brush_material_transaction.gd").new()
	return legacy_material_transaction.initialize(self,{"command":command_buffer,"receipt":receipt_buffer,"cells":cells_buffer},true)

func _dispatch_extra_candidate(data: PackedByteArray) -> void:
	super._dispatch_extra_candidate(data)
	legacy_material_active=mold_field_ever_used and not suspended_edit
	if legacy_material_active:
		legacy_material_transaction.dispatch(0,legacy_dispatch_indirect)
		legacy_material_transaction.dispatch(3,legacy_dispatch_indirect)

func restore_native_material(record: Dictionary, current_sand: PackedByteArray, spare_sand: PackedByteArray, index: int) -> bool:
	if rd==null or index!=current_index or not MaterialState.validate(record,current_sand,spare_sand,FileAccess.get_sha256("res://assets/brushes/molded_material_candidate.json")).is_empty(): return false
	for pair in [[record.current_support,textures.mold_support[index]],[record.spare_support,textures.mold_support[1-index]]]:
		var source: RID=_create_texture(RenderingDevice.DATA_FORMAT_R32G32_SFLOAT,pair[0])
		if not source.is_valid(): return false
		var error: Error=rd.texture_copy(source,pair[1],Vector3.ZERO,Vector3.ZERO,Vector3(256,256,1),0,0,0,0)
		rd.free_rid(source)
		if error!=OK: return false
	mold_field_ever_used=record.ever_used
	return true

func publish_sand() -> void:
	if not _may_publish(): return
	super.publish_sand()
	if not mold_field_ever_used: return
	# Publish the completed material output through an explicit texture transfer.
	# The molded path writes both physical sand slots during its final stage.
	if rd.texture_copy(current_texture("sand"),published_sand,Vector3.ZERO,Vector3.ZERO,Vector3(grid_size,grid_size,1),0,0,0,0)!=OK:
		push_error("brush completed sand publication failed")

func _dispatch_extra_commit(mode: int) -> void:
	super._dispatch_extra_commit(mode)
	if legacy_material_active: legacy_material_transaction.dispatch(2 if mode==1 else 1,legacy_dispatch_indirect)

func _receipt_ready(data: PackedByteArray, callback: Callable, ticket: int, command_id: int, revision: int) -> void:
	# New rollback kernels must not run inside device readback callbacks.
	if not legacy_material_active:
		super._receipt_ready(data,callback,ticket,command_id,revision);return
	call_deferred("_schedule_legacy_receipt",data,callback,ticket,command_id,revision)

func _schedule_legacy_receipt(data: PackedByteArray, callback: Callable, ticket: int, command_id: int, revision: int) -> void:
	RenderingServer.call_on_render_thread(_finalize_legacy_receipt.bind(data,callback,ticket,command_id,revision))

func _finalize_legacy_receipt(data: PackedByteArray, callback: Callable, ticket: int, command_id: int, revision: int) -> void:
	if rd==null or not callback.is_valid(): return
	var receipt:=Protocol.decode_receipt(data)
	if ticket!=active_ticket or not receipt_pending: callback.call(data);return
	if Protocol.receipt_matches(receipt,ticket,command_id,owner_generation,revision) and receipt.status==1 and state_revision==revision:
		state_revision=receipt.output_revision;publication_pending=true
	elif not receipt.get("ok",false) or receipt.get("status",0) in [0,1]:
		_rollback_command()
		if rd.texture_get_data_async(textures.mold_support[0],0,_legacy_rollback_ready.bind(data,callback))==OK: return
		push_error("legacy material rollback readback failed");return
	receipt_pending=false;receipt_callback_us=Time.get_ticks_usec();callback.call(data)

func _legacy_rollback_ready(_support: PackedByteArray, data: PackedByteArray, callback: Callable) -> void:
	if rd==null: return
	receipt_pending=false;receipt_callback_us=Time.get_ticks_usec();callback.call(data)

func release() -> void:
	if legacy_material_transaction!=null: legacy_material_transaction.release();legacy_material_transaction=null
	super.release()

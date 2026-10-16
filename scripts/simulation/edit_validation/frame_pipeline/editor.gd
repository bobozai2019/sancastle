extends "res://scripts/simulation/brushes/brush_material_solver.gd"

const BatchLayout=preload("res://scripts/simulation/edit_validation/frame_pipeline/layout.gd")

const MODIFIED_FIELDS=["sand","water","sediment","momentum_x","momentum_z","mold_support","compaction"]
const BatchValidation=preload("res://scripts/simulation/edit_validation/frame_pipeline/validation.gd")
const SNAPSHOT_FIELDS=["rock","sand","water","sediment","momentum_x","momentum_z","wetness","compaction","obstacle","flux"]
var receipt_batch_open:=false
var receipt_batch_plan:={}
var receipt_batch_result:={}
var receipt_batch_serial:=0
var receipt_batch_metrics:={}
var receipt_array_fault:="" # Probe-only, disabled by default.
var batch_snapshots: Array[Dictionary]=[]
var batch_backups: Array[Dictionary]=[]
var helper_shaders: Array[RID]=[]
var helper_pipelines: Array[RID]=[]
var batch_buffers: Array[RID]=[]
var batch_sets: Array[RID]=[]
var batch_indirect:=RID()
var recording_batch:=false
var pre_batch_ticket:=-1
var batch_pass_index:=-1
var rollback_pending:=false
var rollback_callbacks: Array[Callable]=[]
var rollback_remaining:=0
var rollback_errors:=[]
var rollback_hashes:={}
var profile_sequence:=0
var profile_starts:={}

# Opt-in diagnostics. CPU spans measure command recording, GPU spans measure
# the paired device timestamps; neither introduces a synchronous readback.
func _profile_begin(stage: String) -> String:
	if not profile_passes:return ""
	profile_sequence+=1
	var mark:="fp_%d_%d_%s"%[receipt_batch_serial,profile_sequence,stage]
	profile_starts[mark]=Time.get_ticks_usec()
	rd.capture_timestamp(mark+"_start")
	return mark

func _profile_end(mark: String) -> void:
	if mark.is_empty():return
	rd.capture_timestamp(mark+"_end")
	receipt_batch_metrics.cpu_spans.append({"mark":mark,"start_us":profile_starts[mark],"end_us":Time.get_ticks_usec()})
	profile_starts.erase(mark)

func _initialize_helpers() -> String:
	if not helper_pipelines.is_empty():
		return "" if helper_pipelines.size()==2 and helper_pipelines[0].is_valid() and helper_pipelines[1].is_valid() else "helper_initialization_incomplete"
	for name in ["select","capture"]:
		var source:=RDShaderSource.new()
		var path: String="res://scripts/simulation/edit_validation/frame_pipeline/"+str(name)+".glsl"
		source.source_compute=FileAccess.get_file_as_string(path).trim_prefix("#[compute]").strip_edges()
		var spirv:=rd.shader_compile_spirv_from_source(source)
		var error:=spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
		if not error.is_empty():return error
		var shader:=rd.shader_create_from_spirv(spirv);helper_shaders.append(shader)
		if not shader.is_valid():return "helper_shader_create"
		var pipeline:=rd.compute_pipeline_create(shader);helper_pipelines.append(pipeline)
		if not pipeline.is_valid():return "helper_pipeline_create"
	return ""

func _helper_set(index: int, buffers: Array) -> RID:
	var uniforms: Array[RDUniform]=[]
	for binding in buffers.size():
		var uniform:=RDUniform.new()
		uniform.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		uniform.binding=binding;uniform.add_id(buffers[binding]);uniforms.append(uniform)
	var uniform_set:=rd.uniform_set_create(uniforms,helper_shaders[index],0)
	batch_sets.append(uniform_set);return uniform_set

func _helper_dispatch(index: int, push: PackedByteArray) -> void:
	var mark:=_profile_begin("helper_%d"%index)
	var list:=rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list,helper_pipelines[index])
	rd.compute_list_bind_uniform_set(list,batch_sets[index],0)
	if not push.is_empty():rd.compute_list_set_push_constant(list,push,push.size())
	rd.compute_list_dispatch(list,1,1,1);rd.compute_list_end()
	_profile_end(mark)

func _copy_texture(source: RID, target: RID) -> Error:
	return rd.texture_copy(source,target,Vector3.ZERO,Vector3.ZERO,Vector3(grid_size,grid_size,1),0,0,0,0)

func _new_texture_copy(source: RID) -> RID:
	var target:=rd.texture_create(rd.texture_get_format(source),RDTextureView.new())
	if not target.is_valid():return RID()
	if _copy_texture(source,target)!=OK:rd.free_rid(target);return RID()
	return target

func _make_backups() -> bool:
	for field in MODIFIED_FIELDS:
		for slot in 2:
			var source: RID=textures[field][slot]
			var copy:=_new_texture_copy(source)
			if not copy.is_valid():return false
			batch_backups.append({"source":source,"backup":copy,"bytes":grid_size*grid_size*(8 if field=="mold_support" else (2 if field=="compaction" else 4))})
	return true

func _save_snapshot() -> bool:
	var snapshot:={}
	batch_snapshots.append(snapshot)
	for field in SNAPSHOT_FIELDS:
		if textures[field] is Array:
			for spare in 2:
				var key: String=("spare_" if spare==1 else "")+str(field)
				var copy:=_new_texture_copy(textures[field][current_index if spare==0 else 1-current_index])
				if not copy.is_valid():return false
				snapshot[key]=copy
		else:
			var copy:=_new_texture_copy(textures[field])
			if not copy.is_valid():return false
			snapshot[field]=copy
	return true

func _set_batch_window(data: PackedByteArray) -> void:
	edit_window=Rect2i(0,0,grid_size,grid_size)
	if not local_dispatch:return
	var a:=Vector2(data.decode_float(48),data.decode_float(52))
	var b:=a if data.decode_u32(44)==0 else Vector2(data.decode_float(56),data.decode_float(60))
	var radius:=data.decode_float(64);var cell_size:=data.decode_float(76)
	if not a.is_finite() or not b.is_finite() or not is_finite(radius) or radius<=0.0 or not is_finite(cell_size) or cell_size<=0.0:return
	var lo:=(a.min(b)-Vector2.ONE*radius)/cell_size+Vector2.ONE*(grid_size*0.5)
	var hi:=(a.max(b)+Vector2.ONE*radius)/cell_size+Vector2.ONE*(grid_size*0.5)
	var x0:=clampi(int(floor(lo.x))-2,0,grid_size-1);var z0:=clampi(int(floor(lo.y))-2,0,grid_size-1)
	var x1:=clampi(int(ceil(hi.x))+2,0,grid_size-1);var z1:=clampi(int(ceil(hi.y))+2,0,grid_size-1)
	edit_window=Rect2i(x0,z0,x1-x0+1,z1-z0+1)

func dispatch_receipt_batch(envelopes: Array, limit: int, tick: int, external_accounting: bool, callback: Callable, snapshots: bool=false) -> Dictionary:
	if rd==null or receipt_batch_open or receipt_pending or publication_pending:return {"error":"backend_busy"}
	if not external_accounting:return {"error":"serial_accounting_required"}
	if not callback.is_valid():return {"error":"invalid_callback"}
	var plan:=BatchLayout.pack(envelopes,limit,owner_generation,state_revision,tick)
	if not plan.error.is_empty():return plan
	var helper_error:=_initialize_helpers()
	if not helper_error.is_empty():return {"error":helper_error}
	receipt_batch_serial+=1;receipt_batch_open=true;receipt_batch_plan=plan;receipt_batch_result={}
	pre_batch_ticket=active_ticket
	receipt_batch_metrics={"command_upload_calls":1,"command_upload_bytes":plan.data.size(),"control_upload_calls":0,
		"receipt_readback_calls":0,"cpu_ack_inside_batch":0,"scheduled_commands":plan.count,"passes":[],"backup_texture_count":0,"snapshots":snapshots}
	if profile_passes:receipt_batch_metrics.cpu_spans=[]
	var batch_mark:=_profile_begin("batch")
	var backup_mark:=_profile_begin("backup")
	if not _make_backups():_clear_receipt_batch();return {"error":"backup_create"}
	_profile_end(backup_mark)
	receipt_batch_metrics.backup_texture_count=batch_backups.size()
	var setup_mark:=_profile_begin("setup")
	for index in 4:
		var size: int=[plan.data.size(),plan.count*128,48,16][index]
		var data:=PackedByteArray()
		if index==0:data=plan.data
		else:data.resize(size);data.fill(0)
		var usage: int=RenderingDevice.STORAGE_BUFFER_USAGE_DISPATCH_INDIRECT if index==2 else 0
		var buffer:=rd.storage_buffer_create(size,data,usage);batch_buffers.append(buffer)
		if not buffer.is_valid():_clear_receipt_batch();return {"error":"batch_buffer_create"}
	batch_indirect=batch_buffers[2]
	var select_set:=_helper_set(0,[batch_buffers[0],command_buffer,control_buffer,batch_buffers[1],batch_indirect,batch_buffers[3]])
	var capture_set:=_helper_set(1,[command_buffer,receipt_buffer,batch_buffers[1],batch_buffers[3]])
	if not select_set.is_valid() or not capture_set.is_valid():_clear_receipt_batch();return {"error":"batch_uniform_set"}
	_profile_end(setup_mark)
	receipt_pending=true;settlement_authorized=false;recording_batch=true
	# Original per-command sand/water order. Only selection and dispatch sizes
	# move to the GPU. There is no readback/CPU continuation in this loop.
	for index in plan.count:
		var command_mark:=_profile_begin("command_%d"%index)
		var data: PackedByteArray=plan.envelopes[index]
		active_ticket=data.decode_s64(0);batch_pass_index=index;_set_batch_window(data)
		suspended_edit=false;legacy_dispatch_indirect=batch_indirect
		_helper_dispatch(0,PackedInt32Array([index,ceili(float(edit_window.get_area())/64.0),ceili(float(grid_size*grid_size)/64.0),grid_size/16]).to_byte_array())
		_dispatch_edit(0);_dispatch_edit(1,0)
		if data.decode_u32(40)==0:
			for iteration in 4:_dispatch_edit(1,1);_dispatch_edit(2);_dispatch_edit(1,2)
		else:_dispatch_edit(2)
		_dispatch_edit(1,3);_dispatch_extra_candidate(data);_dispatch_edit(3);_dispatch_extra_commit(0)
		_helper_dispatch(1,PackedByteArray())
		_profile_end(command_mark)
		if snapshots and not _save_snapshot():
			recording_batch=false
			var rollback:=abort_receipt_batch()
			return {"error":"snapshot_copy","rollback":rollback}
	recording_batch=false;batch_pass_index=-1;legacy_dispatch_indirect=RID()
	var error: Error=rd.buffer_get_data_async(batch_buffers[1],_batch_receipt_ready.bind(callback,receipt_batch_serial))
	if error!=OK:return {"error":"batch_readback_submit","rollback":abort_receipt_batch()}
	receipt_batch_metrics.receipt_readback_calls=1
	_profile_end(batch_mark)
	return {"error":"","count":plan.count,"serial":receipt_batch_serial}

func _dispatch_edit(index: int, mode: int=0) -> void:
	if not recording_batch:super._dispatch_edit(index,mode);return
	var mark:=_profile_begin("sand_%d_%d"%[index,mode])
	receipt_batch_metrics.passes.append({"command":batch_pass_index,"pass":"sand_%d_%d"%[index,mode]})
	var list:=rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list,edit_pipelines[index])
	rd.compute_list_bind_uniform_set(list,edit_sets[index][current_index if index in [0,4] else 0],0)
	rd.compute_list_set_push_constant(list,PackedInt32Array([mode,edit_window.position.x,edit_window.position.y,edit_window.size.x,edit_window.size.y,0,0,0]).to_byte_array(),32)
	rd.compute_list_dispatch_indirect(list,batch_indirect,0 if index==1 else 12)
	rd.compute_list_end()
	_profile_end(mark)

func _water_dispatch(index: int, mode: int=0) -> void:
	if not recording_batch:super._water_dispatch(index,mode);return
	var mark:=_profile_begin("water_%d_%d"%[index,mode])
	receipt_batch_metrics.passes.append({"command":batch_pass_index,"pass":"water_%d_%d"%[index,mode]})
	var list:=rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list,water_pipelines[index])
	rd.compute_list_bind_uniform_set(list,water_sets[index][current_index if index in [0,4] else 0],0)
	if index in [0,5]:
		rd.compute_list_set_push_constant(list,PackedInt32Array([grid_size,edit_window.position.x,edit_window.position.y,edit_window.size.x,edit_window.size.y,0,0,0]).to_byte_array(),32)
	elif index in [1,7]:
		var push:=PackedByteArray();push.resize(16);push.fill(0)
		push.encode_u32(0,grid_size);push.encode_float(4,cell_size_m);push.encode_u32(8,1 if inject_water_loss_once else 0)
		push.encode_u32(12,1 if active_policy==2 else (2 if fast_full_wet else 0))
		rd.compute_list_set_push_constant(list,push,16)
	elif index==3:rd.compute_list_set_push_constant(list,PackedInt32Array([grid_size,mode,0,0]).to_byte_array(),16)
	rd.compute_list_dispatch_indirect(list,batch_indirect,0 if index in [1,2,6,7] else 24)
	rd.compute_list_end()
	_profile_end(mark)

func _batch_receipt_ready(bytes: PackedByteArray, callback: Callable, serial: int) -> void:
	if rd==null or serial!=receipt_batch_serial or not receipt_batch_open or not receipt_pending:return
	receipt_callback_us=Time.get_ticks_usec()
	var fault:=receipt_array_fault;receipt_array_fault=""
	match fault:
		"truncated":bytes.resize(bytes.size()-1)
		"generation":bytes.encode_s64(16,owner_generation+1)
		"revision":bytes.encode_s64(32,receipt_batch_plan.input_revision+99)
		"nan":bytes.encode_float(56,NAN)
		"duplicate":
			if bytes.size()>=256:
				var first:=bytes.slice(0,128)
				for index in 128:bytes[128+index]=first[index]
		"tail_edited_cells":bytes.encode_u32(bytes.size()-128+96,1)
		"tail_dirty_rect":bytes.encode_u32(bytes.size()-128+64,1)
	var validated:=BatchValidation.validate(bytes,receipt_batch_plan)
	if not validated.error.is_empty():
		# Async callbacks can run while RD is recycling a frame. Schedule new
		# GPU work through main -> render, outside the callback/recycle phase.
		call_deferred("_schedule_invalid_array_abort",callback,validated.error,bytes,receipt_callback_us,receipt_batch_serial)
		return
	state_revision=validated.output_revision
	active_ticket=receipt_batch_plan.envelopes[validated.accepted_count-1].decode_s64(0) if validated.accepted_count>0 else pre_batch_ticket
	receipt_pending=false;publication_pending=validated.accepted_count>0
	receipt_batch_result=validated
	if fault=="drop_callback":return
	callback.call({"error":"","raw":bytes,"validated":validated,"metrics":receipt_batch_metrics.duplicate(true),"callback_us":receipt_callback_us})

func _invalid_array_rolled_back(rollback: Dictionary, callback: Callable, error: String, raw: PackedByteArray, at_us: int) -> void:
	callback.call({"error":error,"raw":raw,"rollback":rollback,"callback_us":at_us})

func _schedule_invalid_array_abort(callback: Callable, error: String, raw: PackedByteArray, at_us: int, serial: int) -> void:
	RenderingServer.call_on_render_thread(_invalid_array_abort_render.bind(callback,error,raw,at_us,serial))

func _invalid_array_abort_render(callback: Callable, error: String, raw: PackedByteArray, at_us: int, serial: int) -> void:
	if rd==null or not receipt_batch_open or serial!=receipt_batch_serial:return
	abort_receipt_batch(_invalid_array_rolled_back.bind(callback,error,raw,at_us))

func abort_receipt_batch(callback: Callable=Callable()) -> Dictionary:
	if not receipt_batch_open:return {"error":"no_batch"}
	if callback.is_valid():rollback_callbacks.append(callback)
	if rollback_pending:return {"error":"rollback_pending"}
	if batch_backups.size()!=14:return {"error":"missing_backup"}
	rollback_pending=true;rollback_remaining=14;rollback_errors=[];rollback_hashes={}
	receipt_batch_serial+=1 # Ignore any late receipt-array delivery.
	for item in batch_backups:
		if _copy_texture(item.backup,item.source)!=OK:rollback_errors.append("rollback_copy")
	# Keep backup RIDs alive until every restored target has completed GPU
	# readback. An enqueue result alone is not restoration completion.
	for index in batch_backups.size():
		var error: Error=rd.texture_get_data_async(batch_backups[index].source,0,_rollback_slot_ready.bind(index,receipt_batch_serial))
		if error!=OK:rollback_errors.append("rollback_readback_submit");rollback_remaining-=1
	if rollback_remaining==0:_rollback_completed()
	return {"error":"rollback_pending"}

func _rollback_slot_ready(bytes: PackedByteArray, index: int, serial: int) -> void:
	if rd==null or not rollback_pending or serial!=receipt_batch_serial:return
	if bytes.size()!=int(batch_backups[index].bytes):rollback_errors.append("rollback_readback_size")
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(bytes)
	rollback_hashes[str(index)]={"bytes":bytes.size(),"sha256":hash.finish().hex_encode()}
	rollback_remaining-=1
	if rollback_remaining==0:call_deferred("_schedule_rollback_completion",serial)

func _schedule_rollback_completion(serial: int) -> void:
	RenderingServer.call_on_render_thread(_rollback_completion_render.bind(serial))

func _rollback_completion_render(serial: int) -> void:
	if rd!=null and rollback_pending and serial==receipt_batch_serial:_rollback_completed()

func _rollback_completed() -> void:
	state_revision=receipt_batch_plan.input_revision;active_ticket=pre_batch_ticket
	receipt_pending=false;publication_pending=false;settlement_authorized=false
	var result:={"error":"" if rollback_errors.is_empty() else "rollback_unconfirmed","restored_textures":rollback_hashes.size(),"revision":state_revision,"hashes":rollback_hashes.duplicate(true),"errors":rollback_errors.duplicate()}
	var callbacks:=rollback_callbacks.duplicate();rollback_callbacks.clear();rollback_pending=false
	if result.error.is_empty():_clear_receipt_batch()
	# An unconfirmed owner stays write-locked and may only be released.
	for callback in callbacks:callback.call(result)

func complete_receipt_batch() -> Dictionary:
	if not receipt_batch_open or receipt_batch_result.is_empty():return {"error":"no_validated_batch"}
	if receipt_pending or publication_pending:return {"error":"backend_busy"}
	var metrics:=receipt_batch_metrics.duplicate(true)
	_clear_receipt_batch();return {"error":"","metrics":metrics}

func _writes_locked() -> bool:return receipt_batch_open or super._writes_locked()

func _may_publish() -> bool:
	if receipt_batch_open:return not receipt_pending and publication_pending and settlement_authorized
	return super._may_publish()

func _clear_receipt_batch() -> void:
	for rid in batch_sets:
		if rid.is_valid():rd.free_rid(rid)
	batch_sets.clear()
	profile_starts.clear()
	for snapshot in batch_snapshots:
		for rid in snapshot.values():rd.free_rid(rid)
	batch_snapshots.clear()
	for item in batch_backups:rd.free_rid(item.backup)
	batch_backups.clear()
	for rid in batch_buffers:
		if rid.is_valid():rd.free_rid(rid)
	batch_buffers.clear();batch_indirect=RID()
	receipt_batch_open=false;receipt_batch_plan={};receipt_batch_result={};recording_batch=false
	rollback_pending=false;rollback_callbacks.clear()

func release() -> void:
	if rd==null:return
	receipt_batch_serial+=1
	if receipt_batch_open:_clear_receipt_batch()
	for rid in helper_pipelines+helper_shaders:
		if rid.is_valid():rd.free_rid(rid)
	helper_pipelines.clear();helper_shaders.clear()
	super.release()

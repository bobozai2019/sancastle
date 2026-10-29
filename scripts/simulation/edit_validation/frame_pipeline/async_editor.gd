extends "res://scripts/simulation/edit_validation/frame_pipeline/editor.gd"

# Candidate backend. Main is switched only after the integration/lifecycle gates.
const AsyncWire = preload("res://scripts/simulation/edit_validation/frame_pipeline/async_protocol.gd")
const Transport = preload("res://scripts/simulation/edit_validation/frame_pipeline/async_transport.gd")
var async_transport := Transport.new()
var async_shaders: Array[RID] = []
var async_pipelines: Array[RID] = []
var async_resources: Array[Dictionary] = []
var async_diagnostics := false
var async_active := false
var async_error := ""

func enable_async(diagnostics: bool = false) -> bool:
	if rd == null or async_active or _writes_locked(): return false
	async_diagnostics = diagnostics
	if not async_transport.initialize(rd,owner_generation): return false
	rd.buffer_update(async_transport.control,40,8,PackedInt64Array([state_revision]).to_byte_array())
	for name in ["async_select","async_capture"]:
		var source := RDShaderSource.new()
		source.source_compute = FileAccess.get_file_as_string("res://scripts/simulation/edit_validation/frame_pipeline/"+name+".glsl").trim_prefix("#[compute]")
		var spirv := rd.shader_compile_spirv_from_source(source)
		async_error = spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
		if not async_error.is_empty(): return false
		var shader := rd.shader_create_from_spirv(spirv)
		async_shaders.append(shader)
		async_pipelines.append(rd.compute_pipeline_create(shader))
	for slot in async_transport.resources:
		var indirect := rd.storage_buffer_create(48,PackedByteArray(),RenderingDevice.STORAGE_BUFFER_USAGE_DISPATCH_INDIRECT)
		var diagnostic := rd.storage_buffer_create(AsyncWire.MAX_COMMANDS*128 if diagnostics else 4)
		var select := _async_set(0,[slot.input,command_buffer,control_buffer,indirect,async_transport.control])
		var capture := _async_set(1,[command_buffer,receipt_buffer,async_transport.control,diagnostic])
		async_resources.append({"indirect":indirect,"diagnostic":diagnostic,"select":select,"capture":capture})
		if not indirect.is_valid() or not diagnostic.is_valid() or not select.is_valid() or not capture.is_valid(): return false
	async_active = true
	return true

func _async_set(index: int, buffers: Array) -> RID:
	var uniforms: Array[RDUniform] = []
	for binding in buffers.size():
		var uniform := RDUniform.new()
		uniform.binding = binding
		uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		uniform.add_id(buffers[binding])
		uniforms.append(uniform)
	return rd.uniform_set_create(uniforms,async_shaders[index],0)

func _async_dispatch(index: int, binding: RID, push: PackedByteArray) -> void:
	var list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list,async_pipelines[index])
	rd.compute_list_bind_uniform_set(list,binding,0)
	rd.compute_list_set_push_constant(list,push,push.size())
	rd.compute_list_dispatch(list,1,1,1)
	rd.compute_list_end()

func dispatch_async_batch(id: Dictionary, envelopes: Array, callback: Callable) -> String:
	if not async_active or not async_error.is_empty(): return "async_unavailable"
	if envelopes.is_empty() or envelopes.size()>AsyncWire.MAX_COMMANDS: return "command_count"
	var bytes := PackedByteArray()
	var previous_id := -1
	for value in envelopes:
		if not value is PackedByteArray or value.size()!=128: return "command_size"
		var data: PackedByteArray = value
		if data.decode_s64(16)!=owner_generation or data.decode_s64(8)<=previous_id or data.decode_u32(112)>1 or (data.decode_u32(112)==1 and data.decode_u32(40)!=1) or data.decode_u32(40)>1 or data.decode_u32(44)>1 or data.decode_u32(80)!=grid_size or data.decode_u32(84)>3: return "command_identity_or_kind"
		for offset in [48,52,56,60,64,68,72,76,88,92,104,108]:
			if not is_finite(data.decode_float(offset)): return "nonfinite_command"
		previous_id = data.decode_s64(8)
		bytes.append_array(data)
	return async_transport.submit(id,bytes,_record_async.bind(envelopes),callback)

func _record_async(input: RID, _control: RID, _count: int, envelopes: Array) -> void:
	var slot_index := -1
	for slot in async_transport.resources:
		slot_index += 1
		if slot.input==input: break
	var resources: Dictionary = async_resources[slot_index]
	# These are only CPU recording variables. No callback mutates them and the
	# RD queue consumes all shared scratch passes before the next work unit.
	recording_batch = true
	receipt_batch_metrics = {"passes":[],"backup_texture_count":0}
	if profile_passes:receipt_batch_metrics.cpu_spans=[]
	batch_indirect = resources.indirect
	legacy_dispatch_indirect = batch_indirect
	for index in envelopes.size():
		var data: PackedByteArray = envelopes[index]
		active_ticket = data.decode_s64(0)
		batch_pass_index = index
		_set_batch_window(data)
		suspended_edit = data.decode_u32(112)==1
		_async_dispatch(0,resources.select,PackedInt32Array([index,ceili(float(edit_window.get_area())/64.0),ceili(float(grid_size*grid_size)/64.0),grid_size/16]).to_byte_array())
		_dispatch_edit(0)
		_dispatch_edit(1,0)
		if data.decode_u32(40)==0:
			for iteration in 4:
				_dispatch_edit(1,1)
				_dispatch_edit(2)
				_dispatch_edit(1,2)
		else: _dispatch_edit(2)
		_dispatch_edit(1,3)
		_dispatch_extra_candidate(data)
		# All validation (including water/material) precedes every authority write.
		_dispatch_edit(3)
		_dispatch_extra_commit(0)
		_async_dispatch(1,resources.capture,PackedInt32Array([index,1 if async_diagnostics else 0,0,0]).to_byte_array())
	recording_batch = false
	batch_indirect = RID()
	legacy_dispatch_indirect = RID()
	batch_pass_index = -1
	# Complete GPU state can publish immediately, without a CPU settlement.
	publish_sand()

func retire_async(id: Dictionary) -> bool:
	return async_transport.retire(id)

func release_async() -> bool:
	for slot in async_transport.resources:
		if not slot.identity.is_empty(): return false
	for slot in async_resources:
		for key in ["select","capture","diagnostic","indirect"]:
			if slot[key].is_valid(): rd.free_rid(slot[key])
	async_resources.clear()
	for rid in async_pipelines+async_shaders:
		if rid.is_valid(): rd.free_rid(rid)
	async_pipelines.clear()
	async_shaders.clear()
	async_active = false
	return async_transport.release()

func release() -> void:
	if rd==null: return
	if not release_async():
		push_error("async editor release attempted before last GPU consumer")
		return
	super.release()

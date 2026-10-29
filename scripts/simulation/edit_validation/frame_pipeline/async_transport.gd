extends RefCounted

# Render-thread-only resource owner. The caller owns the CPU slot state machine.
# It must acknowledge completion before submitting a new lease in the same slot.
const Wire = preload("res://scripts/simulation/edit_validation/frame_pipeline/async_protocol.gd")
var rd: RenderingDevice
var control := RID()
var shader := RID()
var pipeline := RID()
var resources: Array[Dictionary] = []
var generation := 0
var last_error := ""
var clock_texture := RID()
var inject_readback_failure_once:=false
var inject_upload_failure_once:=false
var inject_fence_unavailable:=false
var inject_completion_fault_once:=""
var terminal_fences:=0

func initialize(device: RenderingDevice, epoch: int) -> bool:
	if device == null or epoch < 1 or rd != null: return false
	rd = device
	generation = epoch
	var data := PackedByteArray()
	data.resize(Wire.CONTROL_BYTES)
	data.encode_u32(0, Wire.VERSION)
	data.encode_u64(8, epoch)
	control = rd.storage_buffer_create(data.size(), data)
	var format:=RDTextureFormat.new()
	format.width=1
	format.height=1
	format.format=RenderingDevice.DATA_FORMAT_R32_SFLOAT
	format.usage_bits=RenderingDevice.TEXTURE_USAGE_STORAGE_BIT|RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT|RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT|RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT|RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
	clock_texture=rd.texture_create(format,RDTextureView.new(),[PackedFloat32Array([0.0]).to_byte_array()])
	var source := RDShaderSource.new()
	source.source_compute = FileAccess.get_file_as_string("res://scripts/simulation/edit_validation/frame_pipeline/async_seal.glsl").trim_prefix("#[compute]")
	var spirv := rd.shader_compile_spirv_from_source(source)
	last_error = spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
	if not last_error.is_empty(): return false
	shader = rd.shader_create_from_spirv(spirv)
	pipeline = rd.compute_pipeline_create(shader)
	if not control.is_valid() or not pipeline.is_valid(): return false
	for index in Wire.BATCH_SLOTS:
		var input := rd.storage_buffer_create(Wire.INPUT_BYTES)
		# Tool work appends its GPU receipt to the ordinary completion. The same
		# ordered readback proves ownership of both; normal batches still read 80B.
		var completion := rd.storage_buffer_create(Wire.COMPLETION_BYTES+256)
		var uniforms: Array[RDUniform] = []
		for pair in [[0,input],[1,control],[2,completion]]:
			var uniform := RDUniform.new()
			uniform.binding = pair[0]
			uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
			uniform.add_id(pair[1])
			uniforms.append(uniform)
		var clock_uniform:=RDUniform.new()
		clock_uniform.binding=3
		clock_uniform.uniform_type=RenderingDevice.UNIFORM_TYPE_IMAGE
		clock_uniform.add_id(clock_texture)
		uniforms.append(clock_uniform)
		var binding := rd.uniform_set_create(uniforms, shader, 0)
		resources.append({"input":input,"completion":completion,"binding":binding,"identity":{},"readback_done":false,"terminal_pending":false})
		if not input.is_valid() or not completion.is_valid() or not binding.is_valid(): return false
	return true

func submit(id: Dictionary, commands: PackedByteArray, record: Callable, callback: Callable, receipt_bytes: int=0, command_stride: int=Wire.COMMAND_BYTES) -> String:
	if rd == null or not Wire.identity_valid(id) or id.generation != generation or not callback.is_valid(): return "submit_identity"
	if receipt_bytes not in [0,256]:return "receipt_size"
	if command_stride not in [128,256] or commands.is_empty() or commands.size()%command_stride!=0: return "command_size"
	var header := Wire.pack_header(id, commands.size()/command_stride)
	if header.is_empty(): return "command_count"
	if command_stride==256:
		# Explicit v1 tool-envelope extension; ordinary v1 headers stay identical.
		header.encode_u32(40,1);header.encode_u32(44,256)
	var slot: Dictionary = resources[id.slot_id]
	if not slot.identity.is_empty(): return "slot_in_use"
	header.append_array(commands)
	if inject_upload_failure_once:inject_upload_failure_once=false;return "upload_failed"
	if rd.buffer_update(slot.input, 0, header.size(), header) != OK: return "upload_failed"
	slot.identity = id.duplicate()
	slot.readback_done = false
	slot.terminal_pending=false
	# Work is recorded consecutively on the main RenderingDevice. Each pass
	# ends its compute list; RD inserts storage hazards before following passes.
	# Scratch is shared across work units, never across concurrent recordings.
	if record.is_valid(): record.call(slot.input, control, commands.size()/command_stride)
	var list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list, pipeline)
	rd.compute_list_bind_uniform_set(list, slot.binding, 0)
	rd.compute_list_dispatch(list, 1, 1, 1)
	rd.compute_list_end()
	var error: Error=ERR_UNAVAILABLE
	if inject_readback_failure_once:inject_readback_failure_once=false
	else:error=rd.buffer_get_data_async(slot.completion, _completed.bind(id.duplicate(), callback),0,Wire.COMPLETION_BYTES+receipt_bytes)
	if error != OK:
		# Work may already have executed. Keep the lease and stop; never retry.
		last_error = "readback_submit_failed"
		return last_error
	return ""

func _completed(bytes: PackedByteArray, id: Dictionary, callback: Callable) -> void:
	if rd == null or not Wire.identity_valid(id) or id.slot_id>=resources.size() or not Wire.same_lease(resources[id.slot_id].identity, id): return
	resources[id.slot_id].readback_done = true
	if not inject_completion_fault_once.is_empty():
		var fault:=inject_completion_fault_once;inject_completion_fault_once=""
		bytes=bytes.duplicate()
		if fault=="truncate":bytes=bytes.slice(0,16)
		elif fault=="identity":bytes.encode_u64(16,id.batch_seq+1)
		elif fault=="flags":bytes.encode_u32(4,16)
		elif fault=="protocol":bytes.encode_u32(0,99)
		elif fault=="time":bytes.encode_float(56,NAN)
		elif fault=="counter":bytes.encode_s64(40,-1)
		elif fault=="tool_identity" and bytes.size()==Wire.COMPLETION_BYTES+256:bytes.encode_s64(Wire.COMPLETION_BYTES+24,bytes.decode_s64(Wire.COMPLETION_BYTES+24)+1)
		elif fault=="tool_tick" and bytes.size()==Wire.COMPLETION_BYTES+256:bytes.encode_s64(Wire.COMPLETION_BYTES+64,bytes.decode_s64(Wire.COMPLETION_BYTES+64)+1)
	callback.call(bytes, id)

func has_owned() -> bool:
	for slot in resources:
		if not slot.identity.is_empty():return true
	return false

# A successful ordered readback callback is a lifetime proof only. Its data
# never repairs the failed completion or authorizes authority publication.
func request_fence(callback: Callable) -> Error:
	if rd==null or not control.is_valid() or inject_fence_unavailable:return ERR_UNAVAILABLE
	terminal_fences+=1
	return rd.buffer_get_data_async(control,callback,0,Wire.CONTROL_BYTES)

func request_terminal(id: Dictionary, callback: Callable) -> void:
	if rd==null or not Wire.identity_valid(id) or id.slot_id>=resources.size() or not Wire.same_lease(resources[id.slot_id].identity,id):callback.call(id,false,"terminal_identity_not_owned");return
	var slot: Dictionary=resources[id.slot_id]
	if slot.readback_done:callback.call(id,true,"completed_readback");return
	if slot.terminal_pending:return
	slot.terminal_pending=true
	if request_fence(_terminal_done.bind(id.duplicate(),callback))!=OK:
		slot.terminal_pending=false
		callback.call(id,false,"terminal_readback_unavailable")

func _terminal_done(_bytes: PackedByteArray, id: Dictionary, callback: Callable) -> void:
	if rd==null or not Wire.same_lease(resources[id.slot_id].identity,id):return
	resources[id.slot_id].terminal_pending=false
	resources[id.slot_id].readback_done=true
	callback.call(id,true,"ordered_terminal_fence")

func retire(id: Dictionary) -> bool:
	if rd == null or not Wire.identity_valid(id): return false
	var slot: Dictionary = resources[id.slot_id]
	if not Wire.same_lease(slot.identity, id) or not slot.readback_done: return false
	slot.identity = {}
	return true

func release() -> bool:
	if rd == null: return true
	for slot in resources:
		if not slot.identity.is_empty(): return false
	for slot in resources:
		for key in ["binding","completion","input"]:
			if slot[key].is_valid(): rd.free_rid(slot[key])
	resources.clear()
	for rid in [pipeline,shader,control,clock_texture]:
		if rid.is_valid(): rd.free_rid(rid)
	pipeline = RID()
	shader = RID()
	control = RID()
	clock_texture=RID()
	rd = null
	return true

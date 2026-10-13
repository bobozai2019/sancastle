class_name SandcastleGpuScalarPingPong
extends RefCounted

## T03 render-thread-owned main-RD ping-pong state building block.
## The probe kernel only increments a scalar; it is not a water solver.

var rd: RenderingDevice
var size := 0
var textures: Array[RID] = []
var uniform_sets: Array[RID] = []
var shader_rid := RID()
var pipeline_rid := RID()
var current_index := 0


func initialize(p_rd: RenderingDevice, spirv: RDShaderSPIRV, p_size: int,
		initial_value: float) -> bool:
	if p_rd == null or spirv == null or p_size <= 0 or p_size % 8 != 0:
		return false
	rd = p_rd
	size = p_size
	var format := RDTextureFormat.new()
	format.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	format.width = size
	format.height = size
	format.format = RenderingDevice.DATA_FORMAT_R32_SFLOAT
	format.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	var initial := PackedFloat32Array()
	initial.resize(size * size)
	initial.fill(initial_value)
	textures.append(rd.texture_create(format, RDTextureView.new(), [initial.to_byte_array()]))
	textures.append(rd.texture_create(format, RDTextureView.new()))
	if not textures[0].is_valid() or not textures[1].is_valid():
		release()
		return false
	shader_rid = rd.shader_create_from_spirv(spirv)
	if not shader_rid.is_valid():
		release()
		return false
	pipeline_rid = rd.compute_pipeline_create(shader_rid)
	if not pipeline_rid.is_valid():
		release()
		return false
	for source_index in 2:
		var input_uniform := RDUniform.new()
		input_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		input_uniform.binding = 0
		input_uniform.add_id(textures[source_index])
		var output_uniform := RDUniform.new()
		output_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		output_uniform.binding = 1
		output_uniform.add_id(textures[1 - source_index])
		uniform_sets.append(rd.uniform_set_create([input_uniform, output_uniform], shader_rid, 0))
		if not uniform_sets.back().is_valid():
			release()
			return false
	return true


func dispatch_step() -> bool:
	if rd == null or not pipeline_rid.is_valid() or uniform_sets.size() != 2:
		return false
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline_rid)
	rd.compute_list_bind_uniform_set(compute_list, uniform_sets[current_index], 0)
	rd.compute_list_dispatch(compute_list, size / 8, size / 8, 1)
	rd.compute_list_end()
	current_index = 1 - current_index
	return true


func request_current_data(callback: Callable) -> Error:
	if rd == null or textures.size() != 2:
		return ERR_UNAVAILABLE
	return rd.texture_get_data_async(textures[current_index], 0, callback)


func current_texture() -> RID:
	return textures[current_index] if textures.size() == 2 else RID()


func release() -> void:
	if rd == null:
		return
	for rid in uniform_sets:
		if rid.is_valid():
			rd.free_rid(rid)
	uniform_sets.clear()
	if pipeline_rid.is_valid():
		rd.free_rid(pipeline_rid)
	if shader_rid.is_valid():
		rd.free_rid(shader_rid)
	for rid in textures:
		if rid.is_valid():
			rd.free_rid(rid)
	textures.clear()
	pipeline_rid = RID()
	shader_rid = RID()
	rd = null

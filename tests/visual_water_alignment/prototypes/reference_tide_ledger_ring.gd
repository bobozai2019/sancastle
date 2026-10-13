extends RefCounted

## W07-only batch capture of exactly the same per-cell tide delta values that
## the current solver reads back each tick. It does not replace that ledger yet.

var rd: RenderingDevice
var shader := RID()
var pipeline := RID()
var uniform_set := RID()
var buffer := RID()
var capacity := 0
var grid_size := 0
var captured := 0


func initialize(p_rd: RenderingDevice, spirv: RDShaderSPIRV,
		tide_delta: RID, p_grid_size: int, p_capacity: int) -> bool:
	if p_rd == null or spirv == null or not tide_delta.is_valid() or \
			p_grid_size < 1 or p_grid_size % 64 != 0 or p_capacity < 1:
		return false
	rd = p_rd
	grid_size = p_grid_size
	capacity = p_capacity
	shader = rd.shader_create_from_spirv(spirv)
	if not shader.is_valid():
		release()
		return false
	pipeline = rd.compute_pipeline_create(shader)
	buffer = rd.storage_buffer_create(capacity * grid_size * 4)
	if not pipeline.is_valid() or not buffer.is_valid():
		release()
		return false
	var image_uniform := RDUniform.new()
	image_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	image_uniform.binding = 0
	image_uniform.add_id(tide_delta)
	var buffer_uniform := RDUniform.new()
	buffer_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	buffer_uniform.binding = 1
	buffer_uniform.add_id(buffer)
	uniform_set = rd.uniform_set_create([image_uniform, buffer_uniform], shader, 0)
	if not uniform_set.is_valid():
		release()
		return false
	return true


func dispatch() -> bool:
	if rd == null or not pipeline.is_valid() or captured >= capacity:
		return false
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	var push := PackedInt32Array([captured, grid_size, 0, 0]).to_byte_array()
	rd.compute_list_set_push_constant(compute_list, push, push.size())
	rd.compute_list_dispatch(compute_list, grid_size / 64, 1, 1)
	rd.compute_list_end()
	captured += 1
	return true


func request_data(callback: Callable) -> Error:
	if rd == null or captured != capacity or not callback.is_valid():
		return ERR_UNAVAILABLE
	return rd.buffer_get_data_async(buffer, callback)


func release() -> void:
	if rd == null:
		return
	if uniform_set.is_valid():
		rd.free_rid(uniform_set)
	if pipeline.is_valid():
		rd.free_rid(pipeline)
	if shader.is_valid():
		rd.free_rid(shader)
	if buffer.is_valid():
		rd.free_rid(buffer)
	uniform_set = RID()
	pipeline = RID()
	shader = RID()
	buffer = RID()
	rd = null

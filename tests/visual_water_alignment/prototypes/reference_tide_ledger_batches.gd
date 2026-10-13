extends RefCounted

## W07-only two-slot capture of the original 256 tide deltas per tick.
## A slot cannot be reused until its asynchronous readback callback completes.

var rd: RenderingDevice
var shader := RID()
var pipeline := RID()
var slots: Array[Dictionary] = []
var grid_size := 0
var batch_ticks := 0
var active_slot := 0
var batch_index := 0
var total_captured := 0
var on_batch: Callable


func initialize(p_rd: RenderingDevice, spirv: RDShaderSPIRV,
		tide_delta: RID, p_grid_size: int, p_batch_ticks: int,
		callback: Callable) -> bool:
	if p_rd == null or spirv == null or not tide_delta.is_valid() or \
			p_grid_size < 1 or p_grid_size % 64 != 0 or p_batch_ticks < 1 or \
			not callback.is_valid():
		return false
	rd = p_rd
	grid_size = p_grid_size
	batch_ticks = p_batch_ticks
	on_batch = callback
	shader = rd.shader_create_from_spirv(spirv)
	if not shader.is_valid():
		release()
		return false
	pipeline = rd.compute_pipeline_create(shader)
	if not pipeline.is_valid():
		release()
		return false
	for i in 2:
		var buffer := rd.storage_buffer_create(batch_ticks * grid_size * 4)
		if not buffer.is_valid():
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
		var uniform_set := rd.uniform_set_create(
			[image_uniform, buffer_uniform], shader, 0)
		slots.append({"buffer": buffer, "uniform_set": uniform_set,
			"count": 0, "busy": false})
		if not uniform_set.is_valid():
			release()
			return false
	return true


func dispatch() -> bool:
	if rd == null or slots[active_slot].busy:
		return false
	var slot: Dictionary = slots[active_slot]
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	rd.compute_list_bind_uniform_set(compute_list, slot.uniform_set, 0)
	var push := PackedInt32Array([slot.count, grid_size, 0, 0]).to_byte_array()
	rd.compute_list_set_push_constant(compute_list, push, push.size())
	rd.compute_list_dispatch(compute_list, grid_size / 64, 1, 1)
	rd.compute_list_end()
	slot.count += 1
	total_captured += 1
	if slot.count == batch_ticks:
		return flush()
	return true


func flush() -> bool:
	if rd == null or slots[active_slot].busy:
		return false
	var slot: Dictionary = slots[active_slot]
	if slot.count == 0:
		return true
	var index := batch_index
	var count: int = slot.count
	slot.busy = true
	var error := rd.buffer_get_data_async(slot.buffer,
		_on_readback.bind(active_slot, index, count))
	if error != OK:
		slot.busy = false
		return false
	batch_index += 1
	active_slot = 1 - active_slot
	return true


func _on_readback(data: PackedByteArray, slot_index: int,
		index: int, count: int) -> void:
	var slot: Dictionary = slots[slot_index]
	slot.busy = false
	slot.count = 0
	on_batch.call(index, count, data)


func release() -> void:
	if rd == null:
		return
	for slot in slots:
		if slot.uniform_set.is_valid():
			rd.free_rid(slot.uniform_set)
		if slot.buffer.is_valid():
			rd.free_rid(slot.buffer)
	if pipeline.is_valid():
		rd.free_rid(pipeline)
	if shader.is_valid():
		rd.free_rid(shader)
	slots.clear()
	pipeline = RID()
	shader = RID()
	rd = null

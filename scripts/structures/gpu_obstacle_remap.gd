class_name SandcastleGpuObstacleRemap
extends RefCounted

## T06 obstacle remap dispatcher.
##
## Run after `solver.update_obstacles()` and before the next substep. The remap
## enforces the contract invariant that a blocked cell holds no water, moving
## whatever it held onto its open neighbours rather than deleting it. It is
## idempotent and stateless, so it is safe to dispatch after every structural
## event including ones that only added obstacle cells.
##
## Water, momentum and suspended sand are ping-pong arrays the solver owns, so the
## remap writes the spare slot and `obstacle_commit.glsl` copies it back onto the
## live slot.

var solver: SandcastleGpuShallowSolver
var rd: RenderingDevice
var remap_shader := RID()
var remap_pipeline := RID()
var remap_sets: Array[RID] = []
var commit_shader := RID()
var commit_pipeline := RID()
var commit_sets: Array[RID] = []
var remap_tiles := RID()
var zero_tiles := PackedByteArray()
var tile_readback_pending := false


func initialize(p_solver: SandcastleGpuShallowSolver, remap_spirv: RDShaderSPIRV,
		commit_spirv: RDShaderSPIRV) -> bool:
	if p_solver == null or p_solver.rd == null or remap_spirv == null or \
			commit_spirv == null:
		return false
	solver = p_solver
	rd = solver.rd
	remap_shader = rd.shader_create_from_spirv(remap_spirv)
	commit_shader = rd.shader_create_from_spirv(commit_spirv)
	if not remap_shader.is_valid() or not commit_shader.is_valid():
		release()
		return false
	remap_pipeline = rd.compute_pipeline_create(remap_shader)
	commit_pipeline = rd.compute_pipeline_create(commit_shader)
	if not remap_pipeline.is_valid() or not commit_pipeline.is_valid():
		release()
		return false
	var tile_format := RDTextureFormat.new()
	tile_format.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	tile_format.width = solver.grid_size / 32
	tile_format.height = tile_format.width
	tile_format.format = RenderingDevice.DATA_FORMAT_R32_UINT
	tile_format.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | \
		RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT | \
		RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
	zero_tiles.resize(tile_format.width * tile_format.height * 4)
	zero_tiles.fill(0)
	remap_tiles = rd.texture_create(tile_format, RDTextureView.new(), [zero_tiles])
	if not remap_tiles.is_valid():
		release()
		return false
	for live_index in 2:
		var spare_index := 1 - live_index
		if not _build_remap_set(live_index, spare_index) or \
				not _build_commit_set(live_index, spare_index):
			release()
			return false
	return true


func _build_remap_set(live_index: int, spare_index: int) -> bool:
	var resources: Array[RID] = [
		solver.textures["obstacle"],
		solver.textures["water"][live_index],
		solver.textures["momentum_x"][live_index],
		solver.textures["momentum_z"][live_index],
		solver.textures["sediment"][live_index],
		solver.textures["water"][spare_index],
		solver.textures["momentum_x"][spare_index],
		solver.textures["momentum_z"][spare_index],
		solver.textures["sediment"][spare_index],
		remap_tiles]
	remap_sets.append(_image_set(resources, remap_shader))
	return remap_sets[-1].is_valid()


func _build_commit_set(live_index: int, spare_index: int) -> bool:
	var resources: Array[RID] = [
		solver.textures["water"][spare_index],
		solver.textures["momentum_x"][spare_index],
		solver.textures["momentum_z"][spare_index],
		solver.textures["sediment"][spare_index],
		solver.textures["water"][live_index],
		solver.textures["momentum_x"][live_index],
		solver.textures["momentum_z"][live_index],
		solver.textures["sediment"][live_index]]
	commit_sets.append(_image_set(resources, commit_shader))
	return commit_sets[-1].is_valid()


func _image_set(resources: Array[RID], shader: RID) -> RID:
	var uniforms: Array[RDUniform] = []
	for binding in resources.size():
		var uniform := RDUniform.new()
		uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		uniform.binding = binding
		uniform.add_id(resources[binding])
		uniforms.append(uniform)
	return rd.uniform_set_create(uniforms, shader, 0)


## Call on the render thread. Returns false only on a device-level failure.
func dispatch() -> bool:
	if rd == null or solver == null or tile_readback_pending:
		return false
	var live_index := solver.current_index
	var list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list, remap_pipeline)
	rd.compute_list_bind_uniform_set(list, remap_sets[live_index], 0)
	rd.compute_list_dispatch(list, solver.grid_size / 8, solver.grid_size / 8, 1)
	rd.compute_list_bind_compute_pipeline(list, commit_pipeline)
	rd.compute_list_bind_uniform_set(list, commit_sets[live_index], 0)
	rd.compute_list_dispatch(list, solver.grid_size / 8, solver.grid_size / 8, 1)
	rd.compute_list_end()
	## `update_obstacles` already bumped the revision for this structural event;
	## this pass is part of the same event, so it does not bump again.
	return true


## Must run before `dispatch()` so the tile report covers only this event.
func clear_tiles() -> bool:
	if rd == null or tile_readback_pending:
		return false
	return rd.texture_update(remap_tiles, 0, zero_tiles) == OK


## Reports which 32² tiles still hold water inside blocked cells. A non-zero tile
## means a blocked pocket had no open neighbour, which the caller must surface
## rather than treat as drained.
func request_tiles(callback: Callable) -> Error:
	if rd == null or not callback.is_valid():
		return ERR_UNAVAILABLE
	return rd.texture_get_data_async(remap_tiles, 0, _on_tiles.bind(callback))


func _on_tiles(data: PackedByteArray, callback: Callable) -> void:
	tile_readback_pending = false
	if rd != null:
		callback.call(data)


## Counts 32² tiles whose report value reaches `minimum`: 1 counts every tile the
## remap touched, 2 counts only tiles that still hold water inside a blocked
## pocket and therefore need the caller's attention.
func decode_tiles(data: PackedByteArray, minimum: int = 1) -> int:
	var expected: int = solver.grid_size / 32 * solver.grid_size / 32 * 4
	if data.size() != expected:
		return -1
	var values := data.to_int32_array()
	var count := 0
	for value in values:
		if value >= minimum:
			count += 1
	return count


func release() -> void:
	if rd == null:
		return
	for set_list in [remap_sets, commit_sets]:
		for uniform_set in set_list:
			if uniform_set.is_valid():
				rd.free_rid(uniform_set)
		set_list.clear()
	for rid in [remap_pipeline, remap_shader, commit_pipeline, commit_shader, remap_tiles]:
		if rid.is_valid():
			rd.free_rid(rid)
	remap_pipeline = RID()
	remap_shader = RID()
	commit_pipeline = RID()
	commit_shader = RID()
	remap_tiles = RID()
	tile_readback_pending = false
	rd = null
	solver = null

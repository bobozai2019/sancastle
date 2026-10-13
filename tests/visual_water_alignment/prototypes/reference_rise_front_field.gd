extends RefCounted

## W07 display-only 256x1 front summary, derived from authoritative GPU
## free-surface height (current bed + depth versus preceding completed tick).
var rd: RenderingDevice
var shader := RID()
var pipeline := RID()
var texture := RID()
var anchored_texture := RID()
var anchor_shader := RID()
var anchor_pipeline := RID()
var anchor_uniform_set := RID()
var uniform_sets: Array[Array] = []


func initialize(solver: SandcastleGpuShallowSolver, foam: SandcastleGpuFoamField,
		spirv: RDShaderSPIRV, anchor_spirv: RDShaderSPIRV = null) -> bool:
	if solver == null or foam == null or spirv == null or solver.grid_size != 256:
		return false
	rd = solver.rd
	var format := RDTextureFormat.new()
	format.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	format.width = 256
	format.height = 1
	format.format = RenderingDevice.DATA_FORMAT_R32G32_SFLOAT
	format.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | \
		RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | \
		RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	var initial := PackedFloat32Array()
	initial.resize(256 * 2)
	initial.fill(0.0)
	texture = rd.texture_create(format, RDTextureView.new(), [initial.to_byte_array()])
	shader = rd.shader_create_from_spirv(spirv)
	if not texture.is_valid() or not shader.is_valid():
		release()
		return false
	pipeline = rd.compute_pipeline_create(shader)
	if not pipeline.is_valid():
		release()
		return false
	for solver_index in 2:
		var by_foam: Array[RID] = []
		for previous_index in 2:
			var ids: Array[RID] = [solver.textures["water"][solver_index],
				foam.textures[previous_index], texture,
				solver.textures["rock"], solver.textures["sand"][solver_index],
				foam.bed_textures[previous_index]]
			var uniforms: Array[RDUniform] = []
			for binding in ids.size():
				var uniform := RDUniform.new()
				uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
				uniform.binding = binding
				uniform.add_id(ids[binding])
				uniforms.append(uniform)
			by_foam.append(rd.uniform_set_create(uniforms, shader, 0))
			if not by_foam.back().is_valid():
				release()
				return false
		uniform_sets.append(by_foam)
	if anchor_spirv != null:
		anchored_texture = rd.texture_create(format, RDTextureView.new(),
			[initial.to_byte_array()])
		anchor_shader = rd.shader_create_from_spirv(anchor_spirv)
		if not anchored_texture.is_valid() or not anchor_shader.is_valid():
			release()
			return false
		anchor_pipeline = rd.compute_pipeline_create(anchor_shader)
		if not anchor_pipeline.is_valid():
			release()
			return false
		var anchor_uniforms: Array[RDUniform] = []
		for binding in 2:
			var uniform := RDUniform.new()
			uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
			uniform.binding = binding
			uniform.add_id(texture if binding == 0 else anchored_texture)
			anchor_uniforms.append(uniform)
		anchor_uniform_set = rd.uniform_set_create(anchor_uniforms, anchor_shader, 0)
		if not anchor_uniform_set.is_valid():
			release()
			return false
	return true


func dispatch(solver: SandcastleGpuShallowSolver, foam: SandcastleGpuFoamField) -> bool:
	if rd == null or uniform_sets.size() != 2 or solver == null or foam == null:
		return false
	var previous_index := 1 - foam.current_index
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	rd.compute_list_bind_uniform_set(compute_list,
		uniform_sets[solver.current_index][previous_index], 0)
	rd.compute_list_dispatch(compute_list, 4, 1, 1)
	rd.compute_list_end()
	if anchor_pipeline.is_valid():
		compute_list = rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(compute_list, anchor_pipeline)
		rd.compute_list_bind_uniform_set(compute_list, anchor_uniform_set, 0)
		rd.compute_list_dispatch(compute_list, 4, 1, 1)
		rd.compute_list_end()
	return true


func final_texture() -> RID:
	return anchored_texture if anchored_texture.is_valid() else texture


func request_data(callback: Callable) -> Error:
	if rd == null or not callback.is_valid():
		return ERR_UNAVAILABLE
	return rd.texture_get_data_async(final_texture(), 0, callback)


func release() -> void:
	if rd == null:
		return
	for by_foam in uniform_sets:
		for rid in by_foam:
			if rid.is_valid():
				rd.free_rid(rid)
	uniform_sets.clear()
	if anchor_uniform_set.is_valid():
		rd.free_rid(anchor_uniform_set)
	if anchor_pipeline.is_valid():
		rd.free_rid(anchor_pipeline)
	if anchor_shader.is_valid():
		rd.free_rid(anchor_shader)
	if anchored_texture.is_valid():
		rd.free_rid(anchored_texture)
	if pipeline.is_valid():
		rd.free_rid(pipeline)
	if shader.is_valid():
		rd.free_rid(shader)
	if texture.is_valid():
		rd.free_rid(texture)
	pipeline = RID()
	shader = RID()
	texture = RID()
	anchored_texture = RID()
	anchor_shader = RID()
	anchor_pipeline = RID()
	anchor_uniform_set = RID()
	rd = null

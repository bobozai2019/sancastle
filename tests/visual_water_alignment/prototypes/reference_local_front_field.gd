extends RefCounted

## W07 display-only local X/Z rising-front summary, updated once per GPU tick.
var rd: RenderingDevice
var x_shader := RID()
var z_shader := RID()
var x_pipeline := RID()
var z_pipeline := RID()
var x_texture := RID()
var texture := RID()
var x_uniform_sets: Array[Array] = []
var z_uniform_set := RID()


func initialize(solver: SandcastleGpuShallowSolver,
		foam: SandcastleGpuFoamField, x_spirv: RDShaderSPIRV,
		z_spirv: RDShaderSPIRV,
		initial_front := PackedFloat32Array()) -> bool:
	if solver == null or foam == null or x_spirv == null or z_spirv == null or \
			solver.grid_size != 256:
		return false
	rd = solver.rd
	var x_format := RDTextureFormat.new()
	x_format.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	x_format.width = 256
	x_format.height = 256
	x_format.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	x_format.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | \
		RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
	var out_format := RDTextureFormat.new()
	out_format.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	out_format.width = 256
	out_format.height = 256
	out_format.format = RenderingDevice.DATA_FORMAT_R32G32_SFLOAT
	out_format.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | \
		RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | \
		RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	var x_initial := PackedFloat32Array()
	x_initial.resize(256 * 256 * 4)
	x_initial.fill(0.0)
	var out_initial: PackedFloat32Array = initial_front.duplicate()
	if out_initial.is_empty():
		out_initial.resize(256 * 256 * 2)
		out_initial.fill(0.0)
	elif out_initial.size() != 256 * 256 * 2:
		return false
	x_texture = rd.texture_create(x_format, RDTextureView.new(),
		[x_initial.to_byte_array()])
	texture = rd.texture_create(out_format, RDTextureView.new(),
		[out_initial.to_byte_array()])
	x_shader = rd.shader_create_from_spirv(x_spirv)
	z_shader = rd.shader_create_from_spirv(z_spirv)
	if not x_texture.is_valid() or not texture.is_valid() or \
			not x_shader.is_valid() or not z_shader.is_valid():
		release()
		return false
	x_pipeline = rd.compute_pipeline_create(x_shader)
	z_pipeline = rd.compute_pipeline_create(z_shader)
	if not x_pipeline.is_valid() or not z_pipeline.is_valid():
		release()
		return false
	for solver_index in 2:
		var by_foam: Array[RID] = []
		for previous_index in 2:
			var ids: Array[RID] = [solver.textures["water"][solver_index],
				foam.textures[previous_index], x_texture,
				solver.textures["rock"], solver.textures["sand"][solver_index],
				foam.bed_textures[previous_index]]
			var uniforms: Array[RDUniform] = []
			for binding in ids.size():
				var uniform := RDUniform.new()
				uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
				uniform.binding = binding
				uniform.add_id(ids[binding])
				uniforms.append(uniform)
			by_foam.append(rd.uniform_set_create(uniforms, x_shader, 0))
			if not by_foam.back().is_valid():
				release()
				return false
		x_uniform_sets.append(by_foam)
	var z_uniforms: Array[RDUniform] = []
	for binding in 2:
		var uniform := RDUniform.new()
		uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		uniform.binding = binding
		uniform.add_id(x_texture if binding == 0 else texture)
		z_uniforms.append(uniform)
	z_uniform_set = rd.uniform_set_create(z_uniforms, z_shader, 0)
	if not z_uniform_set.is_valid():
		release()
		return false
	return true


func dispatch(solver: SandcastleGpuShallowSolver,
		foam: SandcastleGpuFoamField, before_foam := false) -> bool:
	if rd == null or x_uniform_sets.size() != 2 or not z_uniform_set.is_valid() \
			or solver == null or foam == null:
		return false
	var previous_index := foam.current_index if before_foam else 1 - foam.current_index
	var x_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(x_list, x_pipeline)
	rd.compute_list_bind_uniform_set(x_list,
		x_uniform_sets[solver.current_index][previous_index], 0)
	rd.compute_list_dispatch(x_list, 32, 32, 1)
	rd.compute_list_end()
	var z_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(z_list, z_pipeline)
	rd.compute_list_bind_uniform_set(z_list, z_uniform_set, 0)
	rd.compute_list_dispatch(z_list, 32, 32, 1)
	rd.compute_list_end()
	return true


func request_data(callback: Callable) -> Error:
	if rd == null or not callback.is_valid():
		return ERR_UNAVAILABLE
	return rd.texture_get_data_async(texture, 0, callback)


func release() -> void:
	if rd == null:
		return
	for by_foam in x_uniform_sets:
		for rid in by_foam:
			if rid.is_valid():
				rd.free_rid(rid)
	x_uniform_sets.clear()
	if z_uniform_set.is_valid():
		rd.free_rid(z_uniform_set)
	for rid in [x_pipeline, z_pipeline, x_shader, z_shader,
			x_texture, texture]:
		if rid.is_valid():
			rd.free_rid(rid)
	x_pipeline = RID()
	z_pipeline = RID()
	x_shader = RID()
	z_shader = RID()
	x_texture = RID()
	texture = RID()
	z_uniform_set = RID()
	rd = null

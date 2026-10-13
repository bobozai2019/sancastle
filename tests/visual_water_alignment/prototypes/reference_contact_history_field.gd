extends RefCounted

## Isolated display-only W13 contact history. R32F; never writes solver or main foam.
var rd: RenderingDevice
var textures: Array[RID] = []
var current_index := 0
var shader_rid := RID()
var pipeline_rid := RID()
var uniform_sets: Array[Array] = []


func initialize(solver: SandcastleGpuShallowSolver,
		foam: SandcastleGpuFoamField, local_front: RefCounted,
		spirv: RDShaderSPIRV) -> bool:
	if solver == null or foam == null or local_front == null or spirv == null or \
			solver.grid_size != 256 or not local_front.texture.is_valid():
		return false
	rd = solver.rd
	var format := RDTextureFormat.new()
	format.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	format.width = 256
	format.height = 256
	format.format = RenderingDevice.DATA_FORMAT_R32_SFLOAT
	format.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | \
		RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | \
		RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	var initial := PackedFloat32Array()
	initial.resize(256 * 256)
	initial.fill(0.0)
	for i in 2:
		textures.append(rd.texture_create(format, RDTextureView.new(),
			[initial.to_byte_array()]))
		if not textures[i].is_valid():
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
	for solver_index in 2:
		var by_foam: Array[Array] = []
		for foam_previous_index in 2:
			var by_history: Array[RID] = []
			for history_index in 2:
				var ids: Array[RID] = [textures[history_index],
					solver.textures["water"][solver_index],
					foam.textures[foam_previous_index], local_front.texture,
					textures[1 - history_index]]
				var uniforms: Array[RDUniform] = []
				for binding in ids.size():
					var uniform := RDUniform.new()
					uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
					uniform.binding = binding
					uniform.add_id(ids[binding])
					uniforms.append(uniform)
				by_history.append(rd.uniform_set_create(uniforms, shader_rid, 0))
				if not by_history.back().is_valid():
					release()
					return false
			by_foam.append(by_history)
		uniform_sets.append(by_foam)
	return true


func dispatch(solver: SandcastleGpuShallowSolver,
		foam: SandcastleGpuFoamField, delta_s: float) -> bool:
	if rd == null or uniform_sets.size() != 2 or solver == null or foam == null or \
			not is_finite(delta_s) or delta_s <= 0.0:
		return false
	var previous_foam_index := 1 - foam.current_index
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline_rid)
	rd.compute_list_bind_uniform_set(compute_list,
		uniform_sets[solver.current_index][previous_foam_index][current_index], 0)
	rd.compute_list_set_push_constant(compute_list,
		PackedFloat32Array([delta_s, 2.0, 0.001, 0.0]).to_byte_array(), 16)
	rd.compute_list_dispatch(compute_list, 32, 32, 1)
	rd.compute_list_end()
	current_index = 1 - current_index
	return true


func current_texture() -> RID:
	return textures[current_index] if textures.size() == 2 else RID()


func request_data(callback: Callable) -> Error:
	if rd == null or not callback.is_valid():
		return ERR_UNAVAILABLE
	return rd.texture_get_data_async(current_texture(), 0, callback)


func release() -> void:
	if rd == null:
		return
	for by_foam in uniform_sets:
		for by_history in by_foam:
			for rid in by_history:
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

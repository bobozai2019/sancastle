class_name SandcastleGpuFoamField
extends RefCounted

## Display-only RG32F history: R is foam coverage, G is previous tick depth.
## A parallel R32F history stores previous bed height for eta-rise sourcing.
## All RenderingDevice calls run on the render thread.

var rd: RenderingDevice
var grid_size := 0
var current_index := 0
var textures: Array[RID] = []
var bed_textures: Array[RID] = []
var shader_rid := RID()
var pipeline_rid := RID()
var uniform_sets: Array[Array] = []


func initialize(solver: SandcastleGpuShallowSolver, spirv: RDShaderSPIRV,
		initial_history := PackedFloat32Array(),
		initial_bed := PackedFloat32Array(), defer_uniforms := false) -> bool:
	if solver == null or solver.rd == null or spirv == null:
		return false
	rd = solver.rd
	grid_size = solver.grid_size
	var initial: PackedFloat32Array = initial_history.duplicate()
	if initial.is_empty():
		initial.resize(grid_size * grid_size * 2)
		initial.fill(0.0)
	elif initial.size() != grid_size * grid_size * 2:
		return false
	if initial_bed.size() != grid_size * grid_size:
		return false
	var format := RDTextureFormat.new()
	format.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	format.width = grid_size
	format.height = grid_size
	format.format = RenderingDevice.DATA_FORMAT_R32G32_SFLOAT
	format.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | \
		RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | \
		RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	for i in 2:
		textures.append(rd.texture_create(format, RDTextureView.new(),
			[_initial_texture_data(initial.to_byte_array(),i,false)]))
		if not textures[i].is_valid():
			release()
			return false
	var bed_format := RDTextureFormat.new()
	bed_format.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	bed_format.width = grid_size
	bed_format.height = grid_size
	bed_format.format = RenderingDevice.DATA_FORMAT_R32_SFLOAT
	bed_format.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | \
		RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | \
		RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	for i in 2:
		bed_textures.append(rd.texture_create(bed_format, RDTextureView.new(),
			[_initial_texture_data(initial_bed.to_byte_array(),i,true)]))
		if not bed_textures[i].is_valid():
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
	if defer_uniforms:
		return true
	return configure_uniforms(solver)

func _initial_texture_data(fallback: PackedByteArray, _index: int, _bed: bool) -> PackedByteArray:
	return fallback


func configure_uniforms(solver: SandcastleGpuShallowSolver,
		front_texture := RID()) -> bool:
	if rd == null or solver == null or not uniform_sets.is_empty():
		return false
	for solver_index in 2:
		var by_foam: Array[RID] = []
		for foam_index in 2:
			var ids: Array[RID] = [textures[foam_index],
				solver.textures["water"][solver_index],
				solver.textures["momentum_x"][solver_index],
				solver.textures["momentum_z"][solver_index],
				solver.textures["rock"], solver.textures["sand"][solver_index],
				textures[1 - foam_index], bed_textures[foam_index],
				bed_textures[1 - foam_index]]
			if front_texture.is_valid():
				ids.append(front_texture)
			var uniforms: Array[RDUniform] = []
			for binding in ids.size():
				var uniform := RDUniform.new()
				uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
				uniform.binding = binding
				uniform.add_id(ids[binding])
				uniforms.append(uniform)
			by_foam.append(rd.uniform_set_create(uniforms, shader_rid, 0))
			if not by_foam.back().is_valid():
				release()
				return false
		uniform_sets.append(by_foam)
	return true


func dispatch(solver: SandcastleGpuShallowSolver, delta_s: float) -> bool:
	if rd == null or uniform_sets.size() != 2 or solver == null or \
			not is_finite(delta_s) or delta_s <= 0.0:
		return false
	if solver.profile_passes: rd.capture_timestamp("sandcastle_foam_start")
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline_rid)
	rd.compute_list_bind_uniform_set(compute_list,
		uniform_sets[solver.current_index][current_index], 0)
	rd.compute_list_set_push_constant(compute_list,
		PackedFloat32Array([delta_s, solver.cell_size_m, 1.8, 25.0]).to_byte_array(), 16)
	rd.compute_list_dispatch(compute_list, grid_size / 8, grid_size / 8, 1)
	rd.compute_list_end()
	if solver.profile_passes: rd.capture_timestamp("sandcastle_foam_end")
	current_index = 1 - current_index
	return true


func current_texture() -> RID:
	return textures[current_index] if textures.size() == 2 else RID()


func request_data(callback: Callable) -> Error:
	if rd == null or not callback.is_valid():
		return ERR_UNAVAILABLE
	return rd.texture_get_data_async(current_texture(), 0, callback)


func release_uniform_sets() -> void:
	if rd == null:
		return
	for by_foam in uniform_sets:
		for rid in by_foam:
			if rid.is_valid():
				rd.free_rid(rid)
	uniform_sets.clear()


func release() -> void:
	if rd == null:
		return
	release_uniform_sets()
	if pipeline_rid.is_valid():
		rd.free_rid(pipeline_rid)
	if shader_rid.is_valid():
		rd.free_rid(shader_rid)
	for rid in textures:
		if rid.is_valid():
			rd.free_rid(rid)
	textures.clear()
	for rid in bed_textures:
		if rid.is_valid():
			rd.free_rid(rid)
	bed_textures.clear()
	rd = null

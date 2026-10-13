extends "res://scripts/simulation/edit_validation/gpu_sand_editor.gd"

var water_spirvs: Array[RDShaderSPIRV] = []
var water_shaders: Array[RID] = []
var water_pipelines: Array[RID] = []
var water_sets: Array = []
var water_input := RID()
var water_candidate := RID()
var water_scratch := RID()
var water_receipt := RID()
var published_water := RID()
var water_active := false
var inject_water_loss_once := false
var active_policy := 0
var fast_full_wet := false
var connected_runs := false

func initialize(p_rd: RenderingDevice, domain: SandWaterDomain,
		edge_spirv: RDShaderSPIRV, drain_spirv: RDShaderSPIRV,
		update_spirv: RDShaderSPIRV, tide_spirv: RDShaderSPIRV,
		cfl_spirv: RDShaderSPIRV, gauge_spirv: RDShaderSPIRV,
		audit_spirv: RDShaderSPIRV, edit_spirv: RDShaderSPIRV,
		initial_momentum_x := PackedFloat32Array(),
		initial_momentum_z := PackedFloat32Array()) -> bool:
	# Setup-only momentum fields accompany a newly created domain, never an edit.
	if domain.has_meta("edit_validation_initial_qx"):
		initial_momentum_x = domain.get_meta("edit_validation_initial_qx")
		initial_momentum_z = domain.get_meta("edit_validation_initial_qz")
	if water_spirvs.size() != 8 or not super.initialize(p_rd, domain, edge_spirv, drain_spirv,
			update_spirv, tide_spirv, cfl_spirv, gauge_spirv, audit_spirv, edit_spirv,
			initial_momentum_x, initial_momentum_z):
		return false
	water_input = rd.storage_buffer_create(grid_size * grid_size * 32)
	water_candidate = rd.storage_buffer_create(grid_size * grid_size * 16)
	water_scratch = rd.storage_buffer_create(grid_size * grid_size * 20)
	water_receipt = rd.storage_buffer_create(128)
	published_water = _create_texture(RenderingDevice.DATA_FORMAT_R32_SFLOAT, domain.water.to_byte_array())
	for spirv in water_spirvs:
		var shader := rd.shader_create_from_spirv(spirv)
		if not shader.is_valid(): return false
		water_shaders.append(shader)
		water_pipelines.append(rd.compute_pipeline_create(shader))
	var prepares := []
	for index in 2:
		prepares.append(_water_set(0, {0: water_input, 1: cells_buffer, 2: receipt_buffer},
			{3: textures.rock, 4: textures.sand[index], 5: textures.water[index],
			6: textures.sediment[index], 7: textures.momentum_x[index],
			8: textures.momentum_z[index], 9: textures.obstacle}))
	water_sets.append(prepares)
	water_sets.append([_water_set(1, {0: water_input, 1: water_candidate, 2: water_scratch, 3: water_receipt}, {})])
	water_sets.append([_water_set(2, {0: command_buffer, 1: water_receipt, 2: receipt_buffer}, {})])
	water_sets.append([_water_set(3, {0: water_input, 1: water_candidate, 2: receipt_buffer},
		{3: textures.water[0], 4: textures.water[1], 5: textures.sediment[0], 6: textures.sediment[1],
		7: textures.momentum_x[0], 8: textures.momentum_x[1], 9: textures.momentum_z[0], 10: textures.momentum_z[1]})])
	water_sets.append([_water_set(4, {}, {0: textures.water[0], 1: published_water}),
		_water_set(4, {}, {0: textures.water[1], 1: published_water})])
	water_sets.append([_water_set(5, {0: command_buffer, 1: cells_buffer, 2: water_candidate, 3: water_scratch, 4: water_receipt}, {})])
	water_sets.append([_water_set(6, {0: command_buffer, 1: water_candidate, 2: water_scratch, 3: water_receipt}, {})])
	water_sets.append([_water_set(7, {0: water_input, 1: water_candidate, 2: water_scratch, 3: water_receipt} if connected_runs else {0: water_input, 1: water_candidate, 3: water_receipt}, {})])
	for sets in water_sets:
		for rid in sets:
			if not rid.is_valid(): return false
	return true

func _water_set(index: int, buffers: Dictionary, images: Dictionary) -> RID:
	var uniforms: Array[RDUniform] = []
	for binding in buffers:
		var uniform := RDUniform.new()
		uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		uniform.binding = binding
		uniform.add_id(buffers[binding])
		uniforms.append(uniform)
	for binding in images:
		var uniform := RDUniform.new()
		uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		uniform.binding = binding
		uniform.add_id(images[binding])
		uniforms.append(uniform)
	return rd.uniform_set_create(uniforms, water_shaders[index], 0)

func _water_dispatch(index: int, mode := 0) -> void:
	var mark := "edit_water_%d_%d_%d" % [active_ticket,index,mode]
	if profile_passes: rd.capture_timestamp(mark + "_start")
	var list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list, water_pipelines[index])
	rd.compute_list_bind_uniform_set(list, water_sets[index][current_index if index in [0, 4] else 0], 0)
	if index in [0, 5]:
		rd.compute_list_set_push_constant(list, PackedInt32Array([grid_size, edit_window.position.x,
			edit_window.position.y, edit_window.size.x, edit_window.size.y, 0, 0, 0]).to_byte_array(), 32)
	elif index in [1,7]:
		var push := PackedByteArray()
		push.resize(16)
		push.fill(0)
		push.encode_u32(0, grid_size)
		push.encode_float(4, cell_size_m)
		push.encode_u32(8, 1 if inject_water_loss_once else 0)
		push.encode_u32(12, 1 if active_policy == 2 else (2 if fast_full_wet else 0))
		rd.compute_list_set_push_constant(list, push, 16)
	elif index == 3:
		rd.compute_list_set_push_constant(list, PackedInt32Array([grid_size, mode, 0, 0]).to_byte_array(), 16)
	if index in [1, 2, 6, 7]: rd.compute_list_dispatch(list, 1, 1, 1)
	elif index == 4: rd.compute_list_dispatch(list, grid_size / 8, grid_size / 8, 1)
	else: rd.compute_list_dispatch(list, ceili(float(grid_size * grid_size) / 64.0), 1, 1)
	rd.compute_list_end()
	if profile_passes: rd.capture_timestamp(mark + "_end")

func _supports_water_policy(policy: int) -> bool:
	return policy in [0, 1, 2, 3]

func _dispatch_extra_candidate(data: PackedByteArray) -> void:
	active_policy = data.decode_u32(84)
	water_active = active_policy > 0
	if water_active:
		_water_dispatch(0)
		if fast_full_wet and active_policy != 2: _water_dispatch(7)
		_water_dispatch(1)
		inject_water_loss_once = false
		_water_dispatch(5)
		_water_dispatch(6)
		_water_dispatch(2)

func _dispatch_extra_commit(mode: int) -> void:
	if water_active: _water_dispatch(3, mode)

func publish_sand() -> void:
	if not _may_publish(): return
	super.publish_sand()
	_water_dispatch(4)

func release() -> void:
	if rd == null: return
	for sets in water_sets:
		for rid in sets:
			if rid.is_valid(): rd.free_rid(rid)
	water_sets.clear()
	for rid in water_pipelines + water_shaders + [water_input, water_candidate, water_scratch, water_receipt, published_water]:
		if rid.is_valid(): rd.free_rid(rid)
	water_pipelines.clear()
	water_shaders.clear()
	super.release()

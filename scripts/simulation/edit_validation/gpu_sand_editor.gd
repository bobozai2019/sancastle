extends "res://scripts/simulation/edit_validation/lab_solver.gd"

const Protocol = preload("res://scripts/simulation/edit_validation/edit_protocol.gd")
var edit_spirvs: Array[RDShaderSPIRV] = []
var edit_shaders: Array[RID] = []
var edit_pipelines: Array[RID] = []
var edit_sets: Array = []
var command_buffer := RID()
var cells_buffer := RID()
var control_buffer := RID()
var receipt_buffer := RID()
var published_sand := RID()
var owner_generation := 0
var receipt_pending := false
var publication_pending := false
var settlement_authorized := false
var receipt_callback_us := -1
var active_ticket := -1
var inject_receipt_failure_once := false
var local_dispatch := false
var edit_window := Rect2i()

func initialize(p_rd: RenderingDevice, domain: SandWaterDomain,
		edge_spirv: RDShaderSPIRV, drain_spirv: RDShaderSPIRV,
		update_spirv: RDShaderSPIRV, tide_spirv: RDShaderSPIRV,
		cfl_spirv: RDShaderSPIRV, gauge_spirv: RDShaderSPIRV,
		audit_spirv: RDShaderSPIRV, edit_spirv: RDShaderSPIRV,
		initial_momentum_x := PackedFloat32Array(),
		initial_momentum_z := PackedFloat32Array()) -> bool:
	if edit_spirvs.size() != 5 or not super.initialize(p_rd, domain, edge_spirv, drain_spirv,
			update_spirv, tide_spirv, cfl_spirv, gauge_spirv, audit_spirv, edit_spirv,
			initial_momentum_x, initial_momentum_z):
		return false
	owner_generation = domain.generation
	command_buffer = rd.storage_buffer_create(128)
	cells_buffer = rd.storage_buffer_create(grid_size * grid_size * 16)
	control_buffer = rd.storage_buffer_create(64)
	receipt_buffer = rd.storage_buffer_create(128)
	published_sand = _create_texture(RenderingDevice.DATA_FORMAT_R32_SFLOAT, domain.sand.to_byte_array())
	for spirv in edit_spirvs:
		var shader := rd.shader_create_from_spirv(spirv)
		if not shader.is_valid():
			return false
		edit_shaders.append(shader)
		edit_pipelines.append(rd.compute_pipeline_create(shader))
	# A set for each physical ping-pong index when reading sand.
	edit_sets.append([_make_edit_set(0, {0: command_buffer, 1: cells_buffer}, {4: textures.sand[0]}),
		_make_edit_set(0, {0: command_buffer, 1: cells_buffer}, {4: textures.sand[1]})])
	edit_sets.append([_make_edit_set(1, {0: command_buffer, 1: cells_buffer, 2: control_buffer, 3: receipt_buffer}, {})])
	edit_sets.append([_make_edit_set(2, {0: command_buffer, 1: cells_buffer, 2: control_buffer, 3: receipt_buffer}, {})])
	edit_sets.append([_make_edit_set(3, {0: command_buffer, 1: cells_buffer, 3: receipt_buffer}, {4: textures.sand[0], 5: textures.sand[1]})])
	edit_sets.append([_make_edit_set(4, {}, {4: textures.sand[0], 6: published_sand}),
		_make_edit_set(4, {}, {4: textures.sand[1], 6: published_sand})])
	for sets in edit_sets:
		for set_rid in sets:
			if not set_rid.is_valid():
				return false
	return true

func _make_edit_set(index: int, buffers: Dictionary, images: Dictionary) -> RID:
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
	return rd.uniform_set_create(uniforms, edit_shaders[index], 0)

func _dispatch_edit(index: int, mode: int = 0) -> void:
	var mark := "edit_sand_%d_%d_%d" % [active_ticket,index,mode]
	if profile_passes: rd.capture_timestamp(mark + "_start")
	var list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list, edit_pipelines[index])
	rd.compute_list_bind_uniform_set(list, edit_sets[index][current_index if index in [0, 4] else 0], 0)
	if index != 4:
		rd.compute_list_set_push_constant(list, PackedInt32Array([mode, edit_window.position.x,
			edit_window.position.y, edit_window.size.x, edit_window.size.y, 0, 0, 0]).to_byte_array(), 32)
	if index == 1:
		rd.compute_list_dispatch(list, 1, 1, 1)
	elif index == 4:
		rd.compute_list_dispatch(list, grid_size / 8, grid_size / 8, 1)
	else:
		rd.compute_list_dispatch(list, ceili(float(edit_window.get_area()) / 64.0), 1, 1)
	rd.compute_list_end()
	if profile_passes: rd.capture_timestamp(mark + "_end")

func dispatch_sand_command(data: PackedByteArray, callback: Callable) -> bool:
	if receipt_pending or publication_pending or data.size() != 128 or data.decode_u32(80) != grid_size or not callback.is_valid():
		return false
	if not _supports_water_policy(data.decode_u32(84)):
		return false
	edit_window = Rect2i(0, 0, grid_size, grid_size)
	if local_dispatch:
		var a := Vector2(data.decode_float(48), data.decode_float(52))
		var b := a if data.decode_u32(44) == 0 else Vector2(data.decode_float(56), data.decode_float(60))
		var radius := data.decode_float(64)
		var cell_size := data.decode_float(76)
		if a.is_finite() and b.is_finite() and is_finite(radius) and radius > 0.0 and is_finite(cell_size) and cell_size > 0.0:
			# Only an enclosing rectangle is calculated on CPU; weights and reductions stay on GPU.
			# Two extra cells enclose float32 boundary rounding and cell-center conversion.
			var lo := (a.min(b) - Vector2.ONE * radius) / cell_size + Vector2.ONE * (grid_size * 0.5)
			var hi := (a.max(b) + Vector2.ONE * radius) / cell_size + Vector2.ONE * (grid_size * 0.5)
			var x0 := clampi(int(floor(lo.x)) - 2, 0, grid_size - 1)
			var z0 := clampi(int(floor(lo.y)) - 2, 0, grid_size - 1)
			var x1 := clampi(int(ceil(hi.x)) + 2, 0, grid_size - 1)
			var z1 := clampi(int(ceil(hi.y)) + 2, 0, grid_size - 1)
			edit_window = Rect2i(x0, z0, x1 - x0 + 1, z1 - z0 + 1)
	var control := PackedByteArray()
	control.resize(64)
	control.fill(0)
	control.encode_s64(32, owner_generation)
	control.encode_s64(40, state_revision)
	if rd.buffer_update(command_buffer, 0, data.size(), data) != OK or rd.buffer_update(control_buffer, 0, 64, control) != OK:
		return false
	receipt_pending = true
	settlement_authorized = false
	active_ticket = data.decode_s64(0)
	_dispatch_edit(0)
	_dispatch_edit(1, 0)
	if data.decode_u32(40) == 0:
		for iteration in 4:
			_dispatch_edit(1, 1)
			_dispatch_edit(2)
			_dispatch_edit(1, 2)
	else:
		_dispatch_edit(2)
	_dispatch_edit(1, 3)
	_dispatch_extra_candidate(data)
	_dispatch_edit(3)
	_dispatch_extra_commit(0)
	if inject_receipt_failure_once:
		inject_receipt_failure_once = false
		_rollback_command()
		receipt_pending = false
		return false
	var error: Error = rd.buffer_get_data_async(receipt_buffer, _receipt_ready.bind(callback,
		active_ticket, data.decode_s64(8), state_revision))
	if error != OK:
		_rollback_command()
		receipt_pending = false
		return false
	return true

func _receipt_ready(data: PackedByteArray, callback: Callable, ticket: int, command_id: int, revision: int) -> void:
	receipt_callback_us=Time.get_ticks_usec()
	if rd == null or not callback.is_valid():
		return
	var receipt := Protocol.decode_receipt(data)
	if ticket != active_ticket:
		callback.call(data)
		return
	if not receipt_pending:
		callback.call(data)
		return
	if Protocol.receipt_matches(receipt, ticket, command_id, owner_generation, revision) and receipt.status == 1 and state_revision == revision:
		state_revision = receipt.output_revision
		publication_pending = true
	elif not receipt.get("ok", false) or receipt.get("status", 0) in [0, 1]:
		_rollback_command()
	receipt_pending = false
	callback.call(data)

func _supports_water_policy(policy: int) -> bool:
	return policy == 0

func _dispatch_extra_candidate(_data: PackedByteArray) -> void:
	pass

func _dispatch_extra_commit(_mode: int) -> void:
	pass

func _rollback_command() -> void:
	_dispatch_edit(3, 1)
	_dispatch_extra_commit(1)

func _writes_locked() -> bool:
	return receipt_pending or publication_pending

func dispatch_tool_patch(data: PackedByteArray, count: int) -> bool:
	return false if _writes_locked() else super.dispatch_tool_patch(data, count)

func update_obstacles(values: PackedFloat32Array) -> bool:
	return false if _writes_locked() else super.update_obstacles(values)

func _dispatch_boundary_source(value_m: float, injection: bool, packet_height_m: float) -> bool:
	return false if _writes_locked() else super._dispatch_boundary_source(value_m, injection, packet_height_m)

func dispatch_substep(delta: float, ocean_boundary_enabled: bool = false) -> bool:
	return false if _writes_locked() else super.dispatch_substep(delta, ocean_boundary_enabled)

func dispatch_tick_with_cfl(delta: float, tile_bytes: PackedByteArray, revision: int, post_water_substep: Callable = Callable()) -> bool:
	return false if _writes_locked() else super.dispatch_tick_with_cfl(delta, tile_bytes, revision, post_water_substep)

func authorize_publication(ticket: int, output_revision: int, token: int) -> bool:
	# Render-thread bridge calls this only after the matching CPU settlement.
	if receipt_pending or not publication_pending or settlement_authorized or ticket != active_ticket or output_revision != state_revision or token != owner_generation:
		return false
	settlement_authorized = true
	return true

func _may_publish() -> bool:
	return not receipt_pending and (not publication_pending or settlement_authorized)

func publish_sand() -> void:
	if not _may_publish(): return
	_dispatch_edit(4)
	publication_pending = false
	settlement_authorized = false

func release() -> void:
	if rd == null:
		return
	for sets in edit_sets:
		for rid in sets:
			if rid.is_valid():
				rd.free_rid(rid)
	edit_sets.clear()
	for rid in edit_pipelines + edit_shaders + [command_buffer, cells_buffer, control_buffer, receipt_buffer, published_sand]:
		if rid.is_valid():
			rd.free_rid(rid)
	edit_pipelines.clear()
	edit_shaders.clear()
	super.release()


class_name SandcastleGpuShallowSolver
extends RefCounted

## Main-RenderingDevice conservative shallow-water core. All methods that
## touch RenderingDevice must be called on the render thread.

const FIELD_ROCK := "rock"
const FIELD_SAND := "sand"
const FIELD_SEDIMENT := "sediment"
const FIELD_WETNESS := "wetness"
const FIELD_COMPACTION := "compaction"
const FIELD_OBSTACLE := "obstacle"
const FIELD_WATER := "water"
const FIELD_MOMENTUM_X := "momentum_x"
const FIELD_MOMENTUM_Z := "momentum_z"
const FIELD_EDGE_X := "edge_x"
const FIELD_EDGE_Z := "edge_z"
const FIELD_DRAIN := "drain"
const FIELD_FLUX := "flux"
const FIELD_TIDE_DELTA := "tide_delta"
const FIELD_CFL_TILES := "cfl_tiles"
const FIELD_GAUGE_DEPTH := "gauge_depth"
const FIELD_AUDIT_TILES := "audit_tiles"
const COURANT := 0.35
const MAX_SUBSTEPS := 64
const PASS_NAMES := ["edge", "drain", "update", "tide", "cfl", "gauge", "audit", "tool"]

var rd: RenderingDevice
var grid_size := 0
var cell_size_m := 0.0
var current_index := 0
var state_revision := 0
var prescribed_tide_boundary := false
var overload_events := 0
var max_substeps_used := 0
var water_source_m3 := 0.0
var water_sink_m3 := 0.0
var nan_events := 0
var profile_passes := false
var tide_ledger_pending := false
var tide_ledger_requested := false
var tide_ledger_revision := -1
var textures := {}
var shaders: Array[RID] = []
var pipelines: Array[RID] = []
var uniform_sets: Array[Array] = []
var edit_buffer_rid := RID()
var edit_uniform_set_rid := RID()


func initialize(p_rd: RenderingDevice, domain: SandWaterDomain,
		edge_spirv: RDShaderSPIRV, drain_spirv: RDShaderSPIRV,
		update_spirv: RDShaderSPIRV, tide_spirv: RDShaderSPIRV,
		cfl_spirv: RDShaderSPIRV, gauge_spirv: RDShaderSPIRV,
		audit_spirv: RDShaderSPIRV, edit_spirv: RDShaderSPIRV,
		initial_momentum_x := PackedFloat32Array(),
		initial_momentum_z := PackedFloat32Array()) -> bool:
	if p_rd == null or domain == null or edge_spirv == null or drain_spirv == null or update_spirv == null or tide_spirv == null or cfl_spirv == null or gauge_spirv == null or audit_spirv == null or edit_spirv == null:
		return false
	if domain.grid_size % 8 != 0 or domain.grid_size < 8:
		return false
	rd = p_rd
	grid_size = domain.grid_size
	cell_size_m = domain.cell_size_m
	prescribed_tide_boundary = false
	state_revision = 0
	overload_events = 0
	max_substeps_used = 0
	water_source_m3 = 0.0
	water_sink_m3 = 0.0
	nan_events = 0
	tide_ledger_pending = false
	tide_ledger_requested = false
	tide_ledger_revision = -1
	var count := grid_size * grid_size
	var zero := PackedFloat32Array()
	zero.resize(count)
	zero.fill(0.0)
	if initial_momentum_x.is_empty():
		initial_momentum_x = zero
	if initial_momentum_z.is_empty():
		initial_momentum_z = zero
	if initial_momentum_x.size() != count or initial_momentum_z.size() != count:
		return false
	var obstacle_bytes := PackedByteArray()
	obstacle_bytes.resize(count)
	for i in count:
		obstacle_bytes[i] = 255 if domain.obstacle[i] >= 0.5 else 0
	textures[FIELD_ROCK] = _create_texture(RenderingDevice.DATA_FORMAT_R32_SFLOAT, domain.rock.to_byte_array())
	textures[FIELD_SAND] = [
		_create_texture(RenderingDevice.DATA_FORMAT_R32_SFLOAT, domain.sand.to_byte_array()),
		_create_texture(RenderingDevice.DATA_FORMAT_R32_SFLOAT, domain.sand.to_byte_array())]
	textures[FIELD_SEDIMENT] = [
		_create_texture(RenderingDevice.DATA_FORMAT_R32_SFLOAT, domain.sediment.to_byte_array()),
		_create_texture(RenderingDevice.DATA_FORMAT_R32_SFLOAT, domain.sediment.to_byte_array())]
	var wetness_data := _float32_to_half_bytes(domain.wetness)
	var compaction_data := _float32_to_half_bytes(domain.compaction)
	textures[FIELD_WETNESS] = [
		_create_texture(RenderingDevice.DATA_FORMAT_R16_SFLOAT, wetness_data),
		_create_texture(RenderingDevice.DATA_FORMAT_R16_SFLOAT, wetness_data)]
	textures[FIELD_COMPACTION] = [
		_create_texture(RenderingDevice.DATA_FORMAT_R16_SFLOAT, compaction_data),
		_create_texture(RenderingDevice.DATA_FORMAT_R16_SFLOAT, compaction_data)]
	textures[FIELD_OBSTACLE] = _create_texture(RenderingDevice.DATA_FORMAT_R8_UNORM,
		obstacle_bytes, 0, 0, true)
	textures[FIELD_WATER] = [
		_create_texture(RenderingDevice.DATA_FORMAT_R32_SFLOAT, domain.water.to_byte_array()),
		_create_texture(RenderingDevice.DATA_FORMAT_R32_SFLOAT, PackedByteArray())]
	textures[FIELD_MOMENTUM_X] = [
		_create_texture(RenderingDevice.DATA_FORMAT_R32_SFLOAT, initial_momentum_x.to_byte_array()),
		_create_texture(RenderingDevice.DATA_FORMAT_R32_SFLOAT, PackedByteArray())]
	textures[FIELD_MOMENTUM_Z] = [
		_create_texture(RenderingDevice.DATA_FORMAT_R32_SFLOAT, initial_momentum_z.to_byte_array()),
		_create_texture(RenderingDevice.DATA_FORMAT_R32_SFLOAT, PackedByteArray())]
	textures[FIELD_EDGE_X] = _create_texture(RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT, PackedByteArray())
	textures[FIELD_EDGE_Z] = _create_texture(RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT, PackedByteArray())
	textures[FIELD_DRAIN] = _create_texture(RenderingDevice.DATA_FORMAT_R32_SFLOAT, PackedByteArray())
	textures[FIELD_FLUX] = [
		_create_texture(RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT, PackedByteArray()),
		_create_texture(RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT, PackedByteArray())]
	textures[FIELD_TIDE_DELTA] = _create_texture(RenderingDevice.DATA_FORMAT_R32_SFLOAT,
		PackedByteArray(), 1, grid_size)
	textures[FIELD_CFL_TILES] = _create_texture(RenderingDevice.DATA_FORMAT_R32_SFLOAT,
		PackedByteArray(), grid_size / 8)
	textures[FIELD_GAUGE_DEPTH] = _create_texture(RenderingDevice.DATA_FORMAT_R32_SFLOAT,
		PackedByteArray(), 1, 1)
	textures[FIELD_AUDIT_TILES] = _create_texture(RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT,
		PackedByteArray(), grid_size / 8)
	for value in textures.values():
		if value is Array:
			for rid in value:
				if not rid.is_valid():
					release()
					return false
		elif not value.is_valid():
			release()
			return false
	for spirv in [edge_spirv, drain_spirv, update_spirv, tide_spirv, cfl_spirv,
			gauge_spirv, audit_spirv, edit_spirv]:
		var shader_rid := rd.shader_create_from_spirv(spirv)
		shaders.append(shader_rid)
		if not shader_rid.is_valid():
			release()
			return false
		var pipeline_rid := rd.compute_pipeline_create(shader_rid)
		pipelines.append(pipeline_rid)
		if not pipeline_rid.is_valid():
			release()
			return false
	edit_buffer_rid = rd.storage_buffer_create(count * 16)
	if not edit_buffer_rid.is_valid():
		release()
		return false
	var edit_buffer_uniform := RDUniform.new()
	edit_buffer_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	edit_buffer_uniform.binding = 0
	edit_buffer_uniform.add_id(edit_buffer_rid)
	var edit_uniforms: Array[RDUniform] = [edit_buffer_uniform]
	for binding in 4:
		var edit_uniform := RDUniform.new()
		edit_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		edit_uniform.binding = binding + 1
		var field := FIELD_SAND if binding < 2 else FIELD_COMPACTION
		edit_uniform.add_id(textures[field][binding % 2])
		edit_uniforms.append(edit_uniform)
	edit_uniform_set_rid = rd.uniform_set_create(edit_uniforms, shaders[7], 0)
	if not edit_uniform_set_rid.is_valid():
		release()
		return false
	for state_index in 2:
		var edge_inputs: Array[RID] = [textures[FIELD_ROCK], textures[FIELD_SAND][state_index],
			textures[FIELD_WATER][state_index], textures[FIELD_MOMENTUM_X][state_index],
			textures[FIELD_MOMENTUM_Z][state_index], textures[FIELD_OBSTACLE],
			textures[FIELD_EDGE_X], textures[FIELD_EDGE_Z]]
		var drain_inputs: Array[RID] = [textures[FIELD_WATER][state_index],
			textures[FIELD_EDGE_X], textures[FIELD_EDGE_Z], textures[FIELD_DRAIN]]
		var update_inputs: Array[RID] = [textures[FIELD_ROCK], textures[FIELD_SAND][state_index],
			textures[FIELD_WATER][state_index], textures[FIELD_MOMENTUM_X][state_index],
			textures[FIELD_MOMENTUM_Z][state_index], textures[FIELD_OBSTACLE],
			textures[FIELD_EDGE_X], textures[FIELD_EDGE_Z], textures[FIELD_DRAIN],
			textures[FIELD_WATER][1 - state_index], textures[FIELD_MOMENTUM_X][1 - state_index],
			textures[FIELD_MOMENTUM_Z][1 - state_index], textures[FIELD_FLUX][1 - state_index]]
		var tide_inputs: Array[RID] = [textures[FIELD_ROCK], textures[FIELD_SAND][state_index],
			textures[FIELD_WATER][state_index], textures[FIELD_MOMENTUM_X][state_index],
			textures[FIELD_MOMENTUM_Z][state_index], textures[FIELD_WATER][1 - state_index],
			textures[FIELD_MOMENTUM_X][1 - state_index], textures[FIELD_MOMENTUM_Z][1 - state_index],
			textures[FIELD_TIDE_DELTA]]
		var cfl_inputs: Array[RID] = [textures[FIELD_WATER][state_index],
			textures[FIELD_MOMENTUM_X][state_index], textures[FIELD_MOMENTUM_Z][state_index],
			textures[FIELD_CFL_TILES]]
		var gauge_inputs: Array[RID] = [textures[FIELD_WATER][state_index],
			textures[FIELD_GAUGE_DEPTH]]
		var audit_inputs: Array[RID] = [textures[FIELD_WATER][state_index],
			textures[FIELD_OBSTACLE], textures[FIELD_AUDIT_TILES]]
		var state_sets: Array[RID] = [
			_make_set(edge_inputs, shaders[0]),
			_make_set(drain_inputs, shaders[1]),
			_make_set(update_inputs, shaders[2]),
			_make_set(tide_inputs, shaders[3]),
			_make_set(cfl_inputs, shaders[4]),
			_make_set(gauge_inputs, shaders[5]),
			_make_set(audit_inputs, shaders[6])]
		uniform_sets.append(state_sets)
		for rid in state_sets:
			if not rid.is_valid():
				release()
				return false
	return true


func dispatch_tool_patch(data: PackedByteArray, count: int) -> bool:
	## Records are (int cell_index, float sand_m, float compaction, float 0),
	## strictly sorted and unique. Called before the tick's tide/CFL passes.
	if rd == null or count < 1 or count > grid_size * grid_size or data.size() != count * 16:
		return false
	var stream := StreamPeerBuffer.new()
	stream.big_endian = false
	stream.data_array = data
	var previous := -1
	for edit_index in count:
		var index := stream.get_32()
		var sand_m := stream.get_float()
		var compaction := stream.get_float()
		stream.get_float()
		if index <= previous or index >= grid_size * grid_size or not is_finite(sand_m) or \
				sand_m < 0.0 or not is_finite(compaction) or compaction < 0.0 or compaction > 1.0:
			return false
		previous = index
	if rd.buffer_update(edit_buffer_rid, 0, data.size(), data) != OK:
		return false
	if profile_passes:
		rd.capture_timestamp("sandcastle_tool_start")
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipelines[7])
	rd.compute_list_bind_uniform_set(compute_list, edit_uniform_set_rid, 0)
	rd.compute_list_set_push_constant(compute_list,
		PackedInt32Array([count, grid_size, 0, 0]).to_byte_array(), 16)
	rd.compute_list_dispatch(compute_list, ceili(float(count) / 64.0), 1, 1)
	rd.compute_list_end()
	if profile_passes:
		rd.capture_timestamp("sandcastle_tool_end")
	state_revision += 1
	return true


func update_obstacles(values: PackedFloat32Array) -> bool:
	## Rare structural event, not a per-frame full-domain readback. Called on
	## the render thread before the next boundary/CFL/substep dispatch.
	if rd == null or values.size() != grid_size * grid_size or tide_ledger_pending:
		return false
	var bytes := PackedByteArray()
	bytes.resize(values.size())
	for i in values.size():
		if not is_finite(values[i]) or values[i] < 0.0 or values[i] > 1.0:
			return false
		bytes[i] = 255 if values[i] >= 0.5 else 0
	if rd.texture_update(textures[FIELD_OBSTACLE], 0, bytes) != OK:
		return false
	state_revision += 1
	return true


func dispatch_tide_boundary(level_m: float) -> bool:
	## Call once at tick start, before conservative substeps. The per-cell signed
	## source/sink volume is available via request_data(FIELD_TIDE_DELTA).
	return _dispatch_boundary_source(level_m, false, 0.0)


func dispatch_wave_boundary(level_m: float, packet_height_m: float) -> bool:
	## Prescribed open-ocean eta plus an incoming normal momentum consistent
	## with the local background depth. The same tide delta ledger books volume.
	if not is_finite(packet_height_m) or packet_height_m < 0.0 or \
			packet_height_m > 0.25:
		return false
	return _dispatch_boundary_source(level_m, false, packet_height_m)


func dispatch_boundary_injection(depth_m: float) -> bool:
	## Add exactly depth_m to each x=0 cell in a closed domain. Unlike a tide
	## boundary this preserves its momentum and does not hold an ocean level.
	return _dispatch_boundary_source(depth_m, true, 0.0)


func _dispatch_boundary_source(value_m: float, injection: bool,
		packet_height_m: float) -> bool:
	if rd == null or uniform_sets.size() != 2 or not is_finite(value_m) or \
			(injection and value_m < 0.0) or tide_ledger_pending:
		return false
	_dispatch_pass(3, PackedFloat32Array([value_m, cell_size_m * cell_size_m,
		1.0 if injection else 0.0, packet_height_m]).to_byte_array())
	current_index = 1 - current_index
	state_revision += 1
	prescribed_tide_boundary = not injection
	tide_ledger_pending = true
	tide_ledger_requested = false
	tide_ledger_revision = state_revision
	return true


func request_tide_ledger(callback: Callable) -> Error:
	## Must consume each boundary update before dispatching the next. A 256-square
	## domain reads back just the x=0 column: 256 R32F values = 1 KiB.
	if rd == null or not tide_ledger_pending or tide_ledger_requested or not callback.is_valid():
		return ERR_UNAVAILABLE
	tide_ledger_requested = true
	var error := request_data(FIELD_TIDE_DELTA,
		_on_tide_ledger.bind(callback, tide_ledger_revision))
	if error != OK:
		tide_ledger_requested = false
	return error


func _on_tide_ledger(data: PackedByteArray, callback: Callable, revision: int) -> void:
	var valid := data.size() == grid_size * 4 and tide_ledger_pending and \
			revision == tide_ledger_revision
	var source_m3 := 0.0
	var sink_m3 := 0.0
	if valid:
		for delta_m3 in data.to_float32_array():
			if not is_finite(delta_m3):
				valid = false
				break
			if delta_m3 >= 0.0:
				source_m3 += delta_m3
			else:
				sink_m3 -= delta_m3
	if valid:
		water_source_m3 += source_m3
		water_sink_m3 += sink_m3
	else:
		nan_events += 1
	tide_ledger_pending = false
	tide_ledger_requested = false
	callback.call(source_m3, sink_m3, revision, valid)


func dispatch_substep(delta: float, ocean_boundary_enabled: bool = false) -> bool:
	if rd == null or delta <= 0.0 or uniform_sets.size() != 2:
		return false
	var ratio := delta / cell_size_m
	_dispatch_pass(0, PackedByteArray())
	_dispatch_pass(1, PackedFloat32Array([ratio, 0.0, 0.0, 0.0]).to_byte_array())
	_dispatch_pass(2, PackedFloat32Array([ratio, cell_size_m,
		1.0 if ocean_boundary_enabled or prescribed_tide_boundary else 0.0, 0.0]).to_byte_array())
	current_index = 1 - current_index
	state_revision += 1
	return true


func request_cfl_tiles(callback: Callable) -> Error:
	## A 256-square domain reads back only 32×32 R32F tile maxima (4 KiB).
	if rd == null or uniform_sets.size() != 2 or not callback.is_valid():
		return ERR_UNAVAILABLE
	_dispatch_pass(4, PackedByteArray())
	return request_data(FIELD_CFL_TILES, _on_cfl_tiles.bind(callback, state_revision))


func _on_cfl_tiles(data: PackedByteArray, callback: Callable, revision: int) -> void:
	callback.call(data, revision)


func request_gauge_depth(x: int, z: int, callback: Callable) -> Error:
	## Diagnostic readback of one R32F pixel from the completed state (4 bytes).
	if rd == null or x < 0 or z < 0 or x >= grid_size or z >= grid_size or \
			not callback.is_valid():
		return ERR_INVALID_PARAMETER
	_dispatch_pass(5, PackedInt32Array([x, z, 0, 0]).to_byte_array())
	return request_data(FIELD_GAUGE_DEPTH, _on_gauge_depth.bind(callback, state_revision))


func _on_gauge_depth(data: PackedByteArray, callback: Callable, revision: int) -> void:
	callback.call(data, revision)


func request_audit_tiles(callback: Callable) -> Error:
	## Per completed tick: min depth, nonfinite count, effective water volume,
	## negative cell count. 256-square output is 32×32 RGBA32F = 16 KiB.
	if rd == null or not callback.is_valid():
		return ERR_INVALID_PARAMETER
	_dispatch_pass(6, PackedFloat32Array([cell_size_m * cell_size_m,
		0.0, 0.0, 0.0]).to_byte_array())
	return request_data(FIELD_AUDIT_TILES, _on_audit_tiles.bind(callback, state_revision))


func _on_audit_tiles(data: PackedByteArray, callback: Callable, revision: int) -> void:
	callback.call(data, revision)


func decode_audit_tiles(data: PackedByteArray) -> Dictionary:
	if data.size() != grid_size * grid_size / 4:
		return {"valid": false}
	var values := data.to_float32_array()
	var minimum_depth := INF
	var invalid_cells := 0
	var negative_cells := 0
	var water_m3 := 0.0
	for tile in grid_size * grid_size / 64:
		var offset: int = tile * 4
		for component in 4:
			if not is_finite(values[offset + component]):
				return {"valid": false}
		minimum_depth = minf(minimum_depth, values[offset])
		invalid_cells += roundi(values[offset + 1])
		water_m3 += values[offset + 2]
		negative_cells += roundi(values[offset + 3])
	return {"valid": true, "minimum_depth_m": minimum_depth,
		"invalid_cells": invalid_cells, "negative_cells": negative_cells,
		"water_m3": water_m3}


func substeps_from_cfl(delta: float, tile_bytes: PackedByteArray) -> int:
	if not is_finite(delta) or delta <= 0.0 or tile_bytes.size() != grid_size * grid_size / 16:
		return -1
	var maximum_speed := 0.01
	for speed in tile_bytes.to_float32_array():
		if not is_finite(speed) or speed < 0.0:
			return -1
		maximum_speed = maxf(maximum_speed, speed)
	return maxi(1, ceili(delta * maximum_speed / (COURANT * cell_size_m)))


func dispatch_tick_with_cfl(delta: float, tile_bytes: PackedByteArray, revision: int,
		post_water_substep: Callable = Callable()) -> bool:
	if revision != state_revision:
		return false
	return dispatch_tick_validated(delta, substeps_from_cfl(delta, tile_bytes),
		revision, post_water_substep)


## Reuse the validated CFL result for this same revision. No tile scan here.
func dispatch_tick_validated(delta: float, substeps: int, revision: int,
		post_water_substep: Callable = Callable()) -> bool:
	if revision != state_revision or not is_finite(delta) or delta <= 0.0 or substeps < 1:
		return false
	if substeps > MAX_SUBSTEPS:
		overload_events += 1
		return false
	max_substeps_used = maxi(max_substeps_used, substeps)
	for step_index in substeps:
		if not dispatch_substep(delta / float(substeps)):
			return false
		if post_water_substep.is_valid() and \
				not post_water_substep.call(delta / float(substeps)):
			return false
	return true


func _dispatch_pass(pass_index: int, push: PackedByteArray) -> void:
	if profile_passes:
		rd.capture_timestamp("sandcastle_%s_start" % PASS_NAMES[pass_index])
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipelines[pass_index])
	rd.compute_list_bind_uniform_set(compute_list, uniform_sets[current_index][pass_index], 0)
	if not push.is_empty():
		rd.compute_list_set_push_constant(compute_list, push, push.size())
	if pass_index == 5:
		rd.compute_list_dispatch(compute_list, 1, 1, 1)
	else:
		rd.compute_list_dispatch(compute_list, grid_size / 8, grid_size / 8, 1)
	rd.compute_list_end()
	if profile_passes:
		rd.capture_timestamp("sandcastle_%s_end" % PASS_NAMES[pass_index])


func current_texture(field: String) -> RID:
	if not textures.has(field):
		return RID()
	var value = textures[field]
	return value[current_index] if value is Array else value


func request_data(field: String, callback: Callable) -> Error:
	var rid := current_texture(field)
	if rd == null or not rid.is_valid():
		return ERR_UNAVAILABLE
	return rd.texture_get_data_async(rid, 0, callback)


func _create_texture(format_id: int, data: PackedByteArray,
		texture_width: int = 0, texture_height: int = 0,
		updatable: bool = false) -> RID:
	var format := RDTextureFormat.new()
	format.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	format.width = grid_size if texture_width == 0 else texture_width
	format.height = format.width if texture_height == 0 else texture_height
	format.format = format_id
	format.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | \
		RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | \
		RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	if updatable:
		format.usage_bits |= RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
	return rd.texture_create(format, RDTextureView.new(), [data]) if not data.is_empty() else rd.texture_create(format, RDTextureView.new())


func _float32_to_half_bytes(values: PackedFloat32Array) -> PackedByteArray:
	var image := Image.create_from_data(grid_size, grid_size, false,
		Image.FORMAT_RF, values.to_byte_array())
	image.convert(Image.FORMAT_RH)
	return image.get_data()


func _make_set(ids: Array[RID], shader_rid: RID) -> RID:
	var uniforms: Array[RDUniform] = []
	for binding in ids.size():
		var uniform := RDUniform.new()
		uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		uniform.binding = binding
		uniform.add_id(ids[binding])
		uniforms.append(uniform)
	return rd.uniform_set_create(uniforms, shader_rid, 0)


func release() -> void:
	if rd == null:
		return
	if edit_uniform_set_rid.is_valid():
		rd.free_rid(edit_uniform_set_rid)
	edit_uniform_set_rid = RID()
	for state_sets in uniform_sets:
		for rid in state_sets:
			if rid.is_valid():
				rd.free_rid(rid)
	uniform_sets.clear()
	for rid in pipelines:
		if rid.is_valid():
			rd.free_rid(rid)
	pipelines.clear()
	for rid in shaders:
		if rid.is_valid():
			rd.free_rid(rid)
	shaders.clear()
	for value in textures.values():
		if value is Array:
			for rid in value:
				if rid.is_valid():
					rd.free_rid(rid)
		elif value.is_valid():
			rd.free_rid(value)
	textures.clear()
	if edit_buffer_rid.is_valid():
		rd.free_rid(edit_buffer_rid)
	edit_buffer_rid = RID()
	prescribed_tide_boundary = false
	tide_ledger_pending = false
	tide_ledger_requested = false
	rd = null

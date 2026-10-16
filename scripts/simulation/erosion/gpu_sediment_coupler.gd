class_name SandcastleGpuSedimentCoupler
extends RefCounted

## Runs after each water substep. The water solver has already flipped its
## ping-pong index: old water/sand/sediment are at 1-current_index and the
## completed water/flux are at current_index.

# test1 E1478 local formula, adapted to meters and the project's water substeps.
# Capacity is equivalent sand thickness / horizontal speed (seconds).
# The captured 0.015/0.005 fractions are anchored to its 0.020716 s update;
# that reference is an adaptation, not a recovered original wall-clock cadence.
const CAPACITY_PER_SPEED_S := 0.003
const EROSION_RATE_PER_S := 0.7295628483661365
const DEPOSITION_RATE_PER_S := 0.2419645313921744
const DRY_DEPTH_M := 0.001
const CAPACITY_SATURATION_DEPTH_M := 1.0 / 30.0

## Mutable copies of the tuned constants so parameter probes can vary one term at
## a time without forking the shader. Production leaves them at the constants.
var capacity_per_speed_s := CAPACITY_PER_SPEED_S
var erosion_rate_per_s := EROSION_RATE_PER_S
var deposition_rate_per_s := DEPOSITION_RATE_PER_S

var solver: SandcastleGpuShallowSolver
var rd: RenderingDevice
var shader := RID()
var pipeline := RID()
var sets: Array[RID] = []
var copy_shader := RID()
var copy_pipeline := RID()
var copy_sets: Array[RID] = []
var dirty_max_texture := RID()
var dirty_zero_bytes := PackedByteArray()
var observe_pushes := false
var bound_pushes := []
var dirty_readback_pending := false


func initialize(p_solver: SandcastleGpuShallowSolver, spirv: RDShaderSPIRV,
		copy_spirv: RDShaderSPIRV) -> bool:
	if p_solver == null or p_solver.rd == null or spirv == null or copy_spirv == null:
		return false
	solver = p_solver
	rd = solver.rd
	shader = rd.shader_create_from_spirv(spirv)
	if not shader.is_valid():
		release()
		return false
	pipeline = rd.compute_pipeline_create(shader)
	copy_shader = rd.shader_create_from_spirv(copy_spirv)
	if not pipeline.is_valid() or not copy_shader.is_valid():
		release()
		return false
	copy_pipeline = rd.compute_pipeline_create(copy_shader)
	if not copy_pipeline.is_valid():
		release()
		return false
	var dirty_format := RDTextureFormat.new()
	dirty_format.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	dirty_format.width = solver.grid_size / 32
	dirty_format.height = dirty_format.width
	dirty_format.format = RenderingDevice.DATA_FORMAT_R32_UINT
	dirty_format.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | \
		RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT | \
		RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
	dirty_zero_bytes.resize(dirty_format.width * dirty_format.height * 4)
	dirty_zero_bytes.fill(0)
	dirty_max_texture = rd.texture_create(dirty_format, RDTextureView.new(),
		[dirty_zero_bytes])
	if not dirty_max_texture.is_valid():
		release()
		return false
	for output_index in 2:
		var input_index := 1 - output_index
		var resources: Array[RID] = [
			solver.textures["sediment"][input_index],
			solver.textures["water"][input_index],
			solver.textures["flux"][output_index],
			solver.textures["obstacle"],
			solver.textures["sand"][input_index],
			solver.textures["momentum_x"][output_index],
			solver.textures["momentum_z"][output_index],
			solver.textures["water"][output_index],
			solver.textures["sand"][output_index],
			solver.textures["sediment"][output_index],
			dirty_max_texture]
		var uniforms: Array[RDUniform] = []
		for binding in resources.size():
			var uniform := RDUniform.new()
			uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
			uniform.binding = binding
			uniform.add_id(resources[binding])
			uniforms.append(uniform)
		sets.append(rd.uniform_set_create(uniforms, shader, 0))
		if not sets[-1].is_valid():
			release()
			return false
		var copy_resources: Array[RID] = [
			solver.textures["sand"][input_index],
			solver.textures["sediment"][input_index],
			solver.textures["sand"][output_index],
			solver.textures["sediment"][output_index]]
		var copy_uniforms: Array[RDUniform] = []
		for binding in copy_resources.size():
			var copy_uniform := RDUniform.new()
			copy_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
			copy_uniform.binding = binding
			copy_uniform.add_id(copy_resources[binding])
			copy_uniforms.append(copy_uniform)
		copy_sets.append(rd.uniform_set_create(copy_uniforms, copy_shader, 0))
		if not copy_sets[-1].is_valid():
			release()
			return false
	return true


func clear_dirty_max() -> bool:
	if rd == null or dirty_readback_pending:
		return false
	return rd.texture_update(dirty_max_texture, 0, dirty_zero_bytes) == OK


func request_dirty_max(callback: Callable) -> Error:
	if rd == null or dirty_readback_pending or not callback.is_valid():
		return ERR_UNAVAILABLE
	dirty_readback_pending = true
	var error := rd.texture_get_data_async(dirty_max_texture, 0,
		_on_dirty_data.bind(callback, solver.state_revision))
	if error != OK:
		dirty_readback_pending = false
	return error


func _on_dirty_data(data: PackedByteArray, callback: Callable, revision: int) -> void:
	dirty_readback_pending = false
	if rd != null:
		callback.call(data, revision)


func decode_dirty_max(data: PackedByteArray) -> Dictionary:
	var count: int = solver.grid_size * solver.grid_size / 1024
	if data.size() != count * 4:
		return {"valid": false}
	var values := data.to_int32_array()
	for value in values:
		if value < 0:
			return {"valid": false}
	return {"valid": true, "max_delta_um": values}


func dispatch_after_boundary() -> bool:
	## Boundary source changes only water/momentum but flips the solver index.
	## Carry the completed sand/sediment state to the new index first.
	if rd == null or solver == null:
		return false
	var list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list, copy_pipeline)
	rd.compute_list_bind_uniform_set(list, copy_sets[solver.current_index], 0)
	rd.compute_list_dispatch(list, solver.grid_size / 8, solver.grid_size / 8, 1)
	rd.compute_list_end()
	return true


func dispatch_after_water_substep(delta_s: float) -> bool:
	if rd == null or solver == null or not is_finite(delta_s) or delta_s <= 0.0:
		return false
	if solver.profile_passes:
		rd.capture_timestamp("sandcastle_sediment_start")
	var list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list, pipeline)
	rd.compute_list_bind_uniform_set(list, sets[solver.current_index], 0)
	var push:=_erosion_push(delta_s)
	rd.compute_list_set_push_constant(list,push,32)
	rd.compute_list_dispatch(list, solver.grid_size / 8, solver.grid_size / 8, 1)
	rd.compute_list_end()
	if solver.profile_passes:
		rd.capture_timestamp("sandcastle_sediment_end")
	return true

func _erosion_push(delta_s: float) -> PackedByteArray:
	var bytes:=PackedFloat32Array([
		delta_s, solver.cell_size_m * solver.cell_size_m,
		capacity_per_speed_s, 1.0 - exp(-erosion_rate_per_s * delta_s),
		1.0 - exp(-deposition_rate_per_s * delta_s), DRY_DEPTH_M,
		CAPACITY_SATURATION_DEPTH_M,
		1.0 if solver.prescribed_tide_boundary else 0.0]).to_byte_array()
	if observe_pushes and bound_pushes.size()<16:
		bound_pushes.append({"revision":solver.state_revision,"index":solver.current_index,"bytes_hex":bytes.hex_encode(),"values":Array(bytes.to_float32_array())})
	return bytes


func release() -> void:
	if rd == null:
		return
	for uniform_set in sets:
		if uniform_set.is_valid():
			rd.free_rid(uniform_set)
	sets.clear()
	for uniform_set in copy_sets:
		if uniform_set.is_valid():
			rd.free_rid(uniform_set)
	copy_sets.clear()
	for rid in [dirty_max_texture, pipeline, shader, copy_pipeline, copy_shader]:
		if rid.is_valid():
			rd.free_rid(rid)
	pipeline = RID()
	shader = RID()
	copy_pipeline = RID()
	copy_shader = RID()
	dirty_max_texture = RID()
	dirty_readback_pending = false
	rd = null
	solver = null

class_name SandcastleGpuSandAudit
extends RefCounted

## Diagnostic-only tile reduction. It never changes the solver's sand state.

var solver: SandcastleGpuShallowSolver
var rd: RenderingDevice
var shader := RID()
var pipeline := RID()
var output := RID()
var sets: Array[RID] = []
var pending := false


func initialize(p_solver: SandcastleGpuShallowSolver, spirv: RDShaderSPIRV) -> bool:
	if p_solver == null or p_solver.rd == null or spirv == null:
		return false
	solver = p_solver
	rd = p_solver.rd
	shader = rd.shader_create_from_spirv(spirv)
	if not shader.is_valid():
		release()
		return false
	pipeline = rd.compute_pipeline_create(shader)
	var format := RDTextureFormat.new()
	format.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	format.width = solver.grid_size / 8
	format.height = format.width
	format.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	format.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | \
		RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	output = rd.texture_create(format, RDTextureView.new())
	if not pipeline.is_valid() or not output.is_valid():
		release()
		return false
	for state_index in 2:
		var resources: Array[RID] = [solver.textures["sand"][state_index],
			solver.textures["sediment"][state_index], output]
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
	return true


func request(callback: Callable) -> Error:
	if rd == null or pending or not callback.is_valid():
		return ERR_UNAVAILABLE
	if solver.profile_passes:
		rd.capture_timestamp("sandcastle_sand_audit_start")
	var list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list, pipeline)
	rd.compute_list_bind_uniform_set(list, sets[solver.current_index], 0)
	rd.compute_list_set_push_constant(list, PackedFloat32Array([
		solver.cell_size_m * solver.cell_size_m, 0.0, 0.0, 0.0]).to_byte_array(), 16)
	rd.compute_list_dispatch(list, solver.grid_size / 8, solver.grid_size / 8, 1)
	rd.compute_list_end()
	if solver.profile_passes:
		rd.capture_timestamp("sandcastle_sand_audit_end")
	pending = true
	var error := rd.texture_get_data_async(output, 0,
		_on_data.bind(callback, solver.state_revision))
	if error != OK:
		pending = false
	return error


func _on_data(data: PackedByteArray, callback: Callable, revision: int) -> void:
	pending = false
	if rd != null:
		callback.call(data, revision)


func decode(data: PackedByteArray) -> Dictionary:
	if solver == null or data.size() != solver.grid_size * solver.grid_size / 4:
		return {"valid": false}
	var values := data.to_float32_array()
	var sand_m3 := 0.0
	var sediment_m3 := 0.0
	var invalid_cells := 0
	var negative_cells := 0
	for tile in solver.grid_size * solver.grid_size / 64:
		var offset: int = tile * 4
		for component in 4:
			if not is_finite(values[offset + component]):
				return {"valid": false}
		sand_m3 += values[offset]
		sediment_m3 += values[offset + 1]
		invalid_cells += roundi(values[offset + 2])
		negative_cells += roundi(values[offset + 3])
	return {"valid": true, "sand_m3": sand_m3,
		"sediment_m3": sediment_m3, "invalid_cells": invalid_cells,
		"negative_cells": negative_cells}


func release() -> void:
	if rd == null:
		return
	for uniform_set in sets:
		if uniform_set.is_valid():
			rd.free_rid(uniform_set)
	sets.clear()
	for rid in [output, pipeline, shader]:
		if rid.is_valid():
			rd.free_rid(rid)
	output = RID()
	pipeline = RID()
	shader = RID()
	pending = false
	rd = null

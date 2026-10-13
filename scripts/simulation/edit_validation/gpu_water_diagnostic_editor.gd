extends "res://scripts/simulation/edit_validation/gpu_water_editor.gd"

var step_loss_buffer := RID()
var diagnostic_rd: RenderingDevice

func initialize(p_rd: RenderingDevice, domain: SandWaterDomain,
		edge_spirv: RDShaderSPIRV, drain_spirv: RDShaderSPIRV,
		update_spirv: RDShaderSPIRV, tide_spirv: RDShaderSPIRV,
		cfl_spirv: RDShaderSPIRV, gauge_spirv: RDShaderSPIRV,
		audit_spirv: RDShaderSPIRV, edit_spirv: RDShaderSPIRV,
		initial_momentum_x := PackedFloat32Array(),
		initial_momentum_z := PackedFloat32Array()) -> bool:
	diagnostic_rd = p_rd
	var zero := PackedByteArray()
	zero.resize(domain.grid_size * domain.grid_size * 32)
	zero.fill(0)
	step_loss_buffer = p_rd.storage_buffer_create(zero.size(), zero)
	return super.initialize(p_rd, domain, edge_spirv, drain_spirv, update_spirv, tide_spirv,
		cfl_spirv, gauge_spirv, audit_spirv, edit_spirv, initial_momentum_x, initial_momentum_z)

func _make_set(ids: Array[RID], shader_rid: RID) -> RID:
	if ids.size() != 13 or shaders.size() < 3 or shader_rid != shaders[2]:
		return super._make_set(ids, shader_rid)
	var uniforms: Array[RDUniform] = []
	for binding in ids.size():
		var uniform := RDUniform.new()
		uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		uniform.binding = binding
		uniform.add_id(ids[binding])
		uniforms.append(uniform)
	var extra := RDUniform.new()
	extra.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	extra.binding = 13
	extra.add_id(step_loss_buffer)
	uniforms.append(extra)
	return rd.uniform_set_create(uniforms, shader_rid, 0)

func release() -> void:
	var device := diagnostic_rd
	# Free parent sets before their diagnostic buffer dependency.
	super.release()
	if device != null and step_loss_buffer.is_valid(): device.free_rid(step_loss_buffer)
	step_loss_buffer = RID()
	diagnostic_rd = null

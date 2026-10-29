extends "res://scripts/simulation/edit_validation/lab_solver.gd"

var brush_spirv: RDShaderSPIRV
var brush_shader := RID()
var brush_pipeline := RID()
var brush_sets: Array[RID] = []
var stable_fields := {}
var diagnostics := false

func setup_brush() -> bool:
	brush_shader = rd.shader_create_from_spirv(brush_spirv)
	if not brush_shader.is_valid(): return false
	brush_pipeline = rd.compute_pipeline_create(brush_shader)
	for index in 2:
		var uniforms: Array[RDUniform] = []
		for binding in 4:
			var field: String = ["sand", "water", "momentum_x", "momentum_z"][binding]
			var uniform := RDUniform.new()
			uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
			uniform.binding = binding
			uniform.add_id(textures[field][index])
			uniforms.append(uniform)
		brush_sets.append(rd.uniform_set_create(uniforms, brush_shader, 0))
	for field in ["sand", "water", "momentum_x", "momentum_z"]:
		stable_fields[field] = _create_texture(RenderingDevice.DATA_FORMAT_R32_SFLOAT, PackedByteArray())
	return brush_pipeline.is_valid() and brush_sets[0].is_valid() and brush_sets[1].is_valid()

func dispatch_brush(command: Dictionary, mode: int) -> bool:
	var a: Vector2 = command.start_xz_m
	var b: Vector2 = command.end_xz_m
	var radius: float = command.radius_m
	var half := grid_size * cell_size_m * 0.5
	var lo := Vector2i((a.min(b) - Vector2.ONE * radius + Vector2.ONE * half) / cell_size_m)
	var hi := Vector2i((a.max(b) + Vector2.ONE * radius + Vector2.ONE * half) / cell_size_m) + Vector2i.ONE
	lo = lo.clamp(Vector2i.ZERO, Vector2i.ONE * (grid_size-1))
	hi = hi.clamp(Vector2i.ONE, Vector2i.ONE * grid_size)
	# Integral of the linear radial capsule: pi*r^2/3 + length*r.
	var integral := PI * radius * radius / 3.0 + a.distance_to(b) * radius
	var height := clampf(command.nominal_amount_m3 / integral, 0.0, 0.10)
	if command.kind == "dig": height = -height
	var push := PackedFloat32Array([a.x,a.y,b.x,b.y,radius,height,cell_size_m,float(mode),float(lo.x),float(lo.y),float(grid_size),0.25]).to_byte_array()
	var mark := "trial_%d_%d" % [command.generation,command.command_id]
	if diagnostics: rd.capture_timestamp(mark+"_start")
	var list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list, brush_pipeline)
	rd.compute_list_bind_uniform_set(list, brush_sets[current_index], 0)
	rd.compute_list_set_push_constant(list, push, push.size())
	rd.compute_list_dispatch(list, ceili(float(hi.x-lo.x)/8.0), ceili(float(hi.y-lo.y)/8.0), 1)
	rd.compute_list_end()
	if diagnostics: rd.capture_timestamp(mark+"_end")
	state_revision += 1
	return true

func publish_trial() -> bool:
	for field in stable_fields:
		if rd.texture_copy(current_texture(field),stable_fields[field],Vector3.ZERO,Vector3.ZERO,Vector3(grid_size,grid_size,1),0,0,0,0) != OK: return false
	return true

func release() -> void:
	for rid in brush_sets:
		if rid.is_valid(): rd.free_rid(rid)
	for rid in stable_fields.values():
		if rid.is_valid(): rd.free_rid(rid)
	for rid in [brush_pipeline,brush_shader]:
		if rid.is_valid(): rd.free_rid(rid)
	super.release()

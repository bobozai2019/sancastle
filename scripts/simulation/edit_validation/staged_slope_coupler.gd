extends "res://scripts/simulation/material/gpu_material_coupler.gd"

var result_buffer := RID()
var consume_shader := RID()
var consume_pipeline := RID()
var consume_sets: Array[RID]=[]
var staged_shader_hashes := []

func initialize(p_solver: SandcastleGpuShallowSolver,dirty: RID,step: RDShaderSPIRV,_slope: RDShaderSPIRV,commit: RDShaderSPIRV) -> bool:
	if p_solver==null or p_solver.rd==null: return false
	var codes: Array[RDShaderSPIRV]=[]
	for name in _staged_names():
		var code: RDShaderSPIRV=_staged_code(name,p_solver.rd)
		if code==null: return false
		var error:=code.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
		if not error.is_empty(): push_error(error);return false
		codes.append(code)
		var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(code.call("get_stage_bytecode",RenderingDevice.SHADER_STAGE_COMPUTE));staged_shader_hashes.append(hash.finish().hex_encode())
	result_buffer=p_solver.rd.storage_buffer_create(p_solver.grid_size*p_solver.grid_size*8)
	if not result_buffer.is_valid(): return false
	if not super.initialize(p_solver,dirty,step,codes[0],commit):
		if result_buffer.is_valid(): p_solver.rd.free_rid(result_buffer);result_buffer=RID()
		return false
	consume_shader=rd.shader_create_from_spirv(codes[1])
	if not consume_shader.is_valid(): release();return false
	consume_pipeline=rd.compute_pipeline_create(consume_shader)
	if not consume_pipeline.is_valid(): release();return false
	for live_index in 2:
		var buffer:=RDUniform.new();buffer.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER;buffer.binding=0;buffer.add_id(result_buffer)
		var texture:=RDUniform.new();texture.uniform_type=RenderingDevice.UNIFORM_TYPE_IMAGE;texture.binding=1;texture.add_id(solver.textures.sand[1-live_index])
		var uniforms: Array[RDUniform]=[buffer,texture]
		consume_sets.append(rd.uniform_set_create(uniforms,consume_shader,0))
		if not consume_sets[-1].is_valid(): release();return false
	return true

func _image_set(resources: Array[RID],shader: RID) -> RID:
	if shader!=slope_shader: return super._image_set(resources,shader)
	var uniforms: Array[RDUniform]=[]
	for binding in resources.size():
		var uniform:=RDUniform.new();uniform.uniform_type=RenderingDevice.UNIFORM_TYPE_IMAGE;uniform.binding=binding;uniform.add_id(resources[binding]);uniforms.append(uniform)
	var buffer:=RDUniform.new();buffer.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER;buffer.binding=7;buffer.add_id(result_buffer);uniforms.append(buffer)
	return rd.uniform_set_create(uniforms,shader,0)

func release() -> void:
	var device:=rd
	if device!=null:
		for rid in consume_sets+[consume_pipeline,consume_shader]:
			if rid.is_valid(): device.free_rid(rid)
	consume_sets.clear();consume_pipeline=RID();consume_shader=RID()
	super.release()
	if device!=null and result_buffer.is_valid(): device.free_rid(result_buffer)
	result_buffer=RID()

func dispatch_after_erosion(delta_s: float) -> bool:
	if rd == null or solver == null or not is_finite(delta_s) or delta_s <= 0.0:
		return false
	var live_index := solver.current_index
	var spare_index := 1 - live_index
	if solver.profile_passes:
		rd.capture_timestamp("sandcastle_material_start")
	# Resource access changes between dependent stages require separate lists.
	# A single list cannot track the same image/buffer as both read and read-write.
	var list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list, step_pipeline)
	rd.compute_list_bind_uniform_set(list, step_sets[live_index], 0)
	rd.compute_list_set_push_constant(list, PackedFloat32Array([
		delta_s, WET_RATE_PER_S, DRY_RATE_PER_S, DIFFUSION_PER_S,
		RESIDUAL_WETNESS, SOAK_DEPTH_M, DRY_DEPTH_M,
		COMPACT_RATE_PER_S]).to_byte_array(), 32)
	rd.compute_list_dispatch(list, solver.grid_size / 8, solver.grid_size / 8, 1)
	rd.compute_list_end()
	list = rd.compute_list_begin()

	rd.compute_list_bind_compute_pipeline(list, slope_pipeline)
	rd.compute_list_bind_uniform_set(list, slope_sets[live_index], 0)
	var slope_push := _slope_push(delta_s)
	rd.compute_list_set_push_constant(list, slope_push, slope_push.size())
	rd.compute_list_dispatch(list, solver.grid_size / 8, solver.grid_size / 8, 1)
	rd.compute_list_end()
	list = rd.compute_list_begin()

	rd.compute_list_bind_compute_pipeline(list, consume_pipeline)
	rd.compute_list_bind_uniform_set(list, consume_sets[live_index], 0)
	rd.compute_list_dispatch(list, solver.grid_size / 8, solver.grid_size / 8, 1)
	rd.compute_list_end()
	list = rd.compute_list_begin()

	rd.compute_list_bind_compute_pipeline(list, commit_pipeline)
	rd.compute_list_bind_uniform_set(list, commit_sets[live_index], 0)
	rd.compute_list_dispatch(list, solver.grid_size / 8, solver.grid_size / 8, 1)
	rd.compute_list_end()
	if solver.profile_passes:
		rd.capture_timestamp("sandcastle_material_end")
	return true

func _slope_push(delta_s: float) -> PackedByteArray:
	return PackedFloat32Array([
		delta_s, solver.cell_size_m, RELAX_RATE_PER_S, DRY_REPOSE_TAN,
		WET_REPOSE_TAN, COMPACTION_REPOSE_GAIN, MIN_DROP_M,
		clampf(cohesion_yield_height_m, 0.0, 2.0)]).to_byte_array()

func _staged_names() -> Array:
	return ["staged_slope","staged_slope_consume"]

func _staged_code(name: String, _device: RenderingDevice) -> RDShaderSPIRV:
	var file: RDShaderFile=load("res://shaders/simulation/edit_validation/"+name+".glsl")
	return file.get_spirv() if file!=null else null



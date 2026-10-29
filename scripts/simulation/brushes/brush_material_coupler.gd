extends "res://scripts/simulation/edit_validation/staged_slope_coupler.gd"

var support_result := RID()
var support_shader := RID()
var support_pipeline := RID()
var support_set := RID()
var profile := {}
var profile_sha256 := ""
var local_pushes := []
var last_push_revision := -1
var support_device: RenderingDevice
var support_flags := RID()
var support_indirect := RID()
var ordinary_shader := RID()
var ordinary_pipeline := RID()
var ordinary_sets: Array[RID]=[]
var ordinary_shader_hash := ""

func _staged_names() -> Array: return ["molded_slope","staged_slope_consume"]

func _compile(path: String, device: RenderingDevice) -> RDShaderSPIRV:
	var source := RDShaderSource.new()
	source.source_compute=FileAccess.get_file_as_string(path).replace("#[compute]","")
	var code:=device.shader_compile_spirv_from_source(source)
	var error:=code.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
	if not error.is_empty(): push_error(path+": "+error)
	return code

func _staged_code(name: String, device: RenderingDevice) -> RDShaderSPIRV:
	if name=="molded_slope": return _compile("res://shaders/simulation/brushes/molded_slope.glsl",device)
	return super._staged_code(name,device)

func initialize(p_solver: SandcastleGpuShallowSolver,dirty: RID,step: RDShaderSPIRV,slope: RDShaderSPIRV,commit: RDShaderSPIRV) -> bool:
	var path := "res://assets/brushes/molded_material_candidate.json"
	var decoded=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not decoded is Dictionary: return false
	profile=decoded; profile_sha256=FileAccess.get_sha256(path)
	if profile.is_empty() or profile.version!=1 or profile.cohesion_yield_height_m!=0.9 or profile.saturation_tagged_depth_m!=0.125: return false
	if not p_solver.textures.has("mold_support"): return false
	support_device=p_solver.rd
	support_result=support_device.storage_buffer_create(p_solver.grid_size*p_solver.grid_size*8)
	if not support_result.is_valid(): return false
	if not super.initialize(p_solver,dirty,step,slope,commit): return false
	var ordinary_code: RDShaderSPIRV=super._staged_code("staged_slope",rd)
	var hash:=HashingContext.new(); hash.start(HashingContext.HASH_SHA256); hash.update(ordinary_code.get_stage_bytecode(RenderingDevice.SHADER_STAGE_COMPUTE)); ordinary_shader_hash=hash.finish().hex_encode()
	ordinary_shader=rd.shader_create_from_spirv(ordinary_code); ordinary_pipeline=rd.compute_pipeline_create(ordinary_shader)
	for live in 2:
		var resources: Array[RID]=[solver.textures.sand[live],solver.textures.rock,solver.textures.wetness[1-live],solver.textures.compaction[1-live],solver.textures.obstacle,solver.textures.sand[1-live],dirty]
		var ordinary_uniforms: Array[RDUniform]=[]
		for binding in resources.size():
			var u:=RDUniform.new(); u.binding=binding; u.uniform_type=RenderingDevice.UNIFORM_TYPE_IMAGE; u.add_id(resources[binding]); ordinary_uniforms.append(u)
		var output:=RDUniform.new(); output.binding=7; output.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER; output.add_id(result_buffer); ordinary_uniforms.append(output)
		ordinary_sets.append(rd.uniform_set_create(ordinary_uniforms,ordinary_shader,0))
		if not ordinary_sets[-1].is_valid(): return false
	support_flags=rd.storage_buffer_create(4)
	support_indirect=rd.storage_buffer_create(24,PackedByteArray(),RenderingDevice.STORAGE_BUFFER_USAGE_DISPATCH_INDIRECT)
	var code := _compile("res://shaders/simulation/brushes/mold_support_step.glsl",rd)
	if not code.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE).is_empty(): return false
	support_shader=rd.shader_create_from_spirv(code); support_pipeline=rd.compute_pipeline_create(support_shader)
	var uniforms: Array[RDUniform]=[]
	for pair in [[0,solver.textures.mold_support[0]],[1,solver.textures.mold_support[1]],[2,solver.textures.sand[0]],[3,solver.textures.sand[1]]]:
		var u := RDUniform.new(); u.binding=pair[0]; u.uniform_type=RenderingDevice.UNIFORM_TYPE_IMAGE; u.add_id(pair[1]); uniforms.append(u)
	var buffer := RDUniform.new(); buffer.binding=4; buffer.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER; buffer.add_id(support_result); uniforms.append(buffer)
	for pair in [[5,support_flags],[6,support_indirect]]:
		var u:=RDUniform.new(); u.binding=pair[0]; u.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER; u.add_id(pair[1]); uniforms.append(u)
	support_set=rd.uniform_set_create(uniforms,support_shader,0)
	return support_shader.is_valid() and support_pipeline.is_valid() and support_set.is_valid()

func _image_set(resources: Array[RID],shader: RID) -> RID:
	if shader!=slope_shader: return super._image_set(resources,shader)
	var uniforms: Array[RDUniform]=[]
	for binding in resources.size():
		var u := RDUniform.new(); u.binding=binding; u.uniform_type=RenderingDevice.UNIFORM_TYPE_IMAGE; u.add_id(resources[binding]); uniforms.append(u)
	var staged := RDUniform.new(); staged.binding=7; staged.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER; staged.add_id(result_buffer); uniforms.append(staged)
	var live: int=0 if resources[0]==solver.textures.sand[0] else 1
	var tagged := RDUniform.new(); tagged.binding=8; tagged.uniform_type=RenderingDevice.UNIFORM_TYPE_IMAGE; tagged.add_id(solver.textures.mold_support[1-live]); uniforms.append(tagged)
	var output := RDUniform.new(); output.binding=9; output.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER; output.add_id(support_result); uniforms.append(output)
	return rd.uniform_set_create(uniforms,shader,0)

func _slope_push(delta_s: float) -> PackedByteArray:
	var values := super._slope_push(delta_s).to_float32_array()
	values.append_array(PackedFloat32Array([profile.cohesion_yield_height_m,profile.saturation_tagged_depth_m,0,0]))
	var bytes := values.to_byte_array()
	if solver.state_revision!=last_push_revision and local_pushes.size()<16:
		local_pushes.append({"revision":solver.state_revision,"bytes_hex":bytes.hex_encode(),"values":Array(values)})
		last_push_revision=solver.state_revision
	return bytes

func _support_dispatch(phase: int) -> void:
	var list := rd.compute_list_begin(); rd.compute_list_bind_compute_pipeline(list,support_pipeline)
	rd.compute_list_bind_uniform_set(list,support_set,0)
	rd.compute_list_set_push_constant(list,PackedInt32Array([solver.grid_size,solver.current_index,phase,0]).to_byte_array(),16)
	if phase in [2,3]: rd.compute_list_dispatch(list,1,1,1)
	else: rd.compute_list_dispatch(list,solver.grid_size/8,solver.grid_size/8,1)
	rd.compute_list_end()

func reconcile_external_sand_patch() -> bool:
	if rd==null or solver==null or not support_set.is_valid():return false
	# Same upper-tag loss/reference rule used before every material step.
	# A paused CPU patch already changed sand, so reconcile before publication
	# without advancing moisture, slope, sand, the clock, or any source ledger.
	_support_dispatch(2)
	_support_dispatch(0)
	_support_dispatch(3)
	var live: int=solver.current_index
	return rd.texture_copy(solver.textures.mold_support[1-live],solver.textures.mold_support[live],Vector3.ZERO,Vector3.ZERO,Vector3(solver.grid_size,solver.grid_size,1),0,0,0,0)==OK

func dispatch_after_erosion(delta_s: float) -> bool:
	if rd==null or solver._writes_locked(): return false
	if solver.profile_passes: rd.capture_timestamp("sandcastle_material_start")
	var result: bool=_dispatch_material(delta_s)
	if solver.profile_passes: rd.capture_timestamp("sandcastle_material_end")
	return result

func _dispatch_material(delta_s: float) -> bool:
	# A never-molded domain uses the original complete material choreography.
	# No extra sand reads or indirect passes enter that legacy execution graph.
	if not solver.mold_field_ever_used:
		return _ordinary_dispatch(delta_s)
	_support_dispatch(2); _support_dispatch(0); _support_dispatch(3)
	# Keep step/slope/consume/commit resource usages in separate graph nodes.
	var live: int=solver.current_index
	var list:=rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list,step_pipeline); rd.compute_list_bind_uniform_set(list,step_sets[live],0)
	rd.compute_list_set_push_constant(list,PackedFloat32Array([delta_s,WET_RATE_PER_S,DRY_RATE_PER_S,DIFFUSION_PER_S,RESIDUAL_WETNESS,SOAK_DEPTH_M,DRY_DEPTH_M,COMPACT_RATE_PER_S]).to_byte_array(),32)
	rd.compute_list_dispatch(list,solver.grid_size/8,solver.grid_size/8,1)
	rd.compute_list_end()
	list=rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list,ordinary_pipeline); rd.compute_list_bind_uniform_set(list,ordinary_sets[live],0)
	rd.compute_list_set_push_constant(list,super._slope_push(delta_s),32)
	rd.compute_list_dispatch_indirect(list,support_indirect,0)
	rd.compute_list_end()
	list=rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list,slope_pipeline); rd.compute_list_bind_uniform_set(list,slope_sets[live],0)
	var push:=_slope_push(delta_s); rd.compute_list_set_push_constant(list,push,push.size())
	rd.compute_list_dispatch_indirect(list,support_indirect,12)
	rd.compute_list_end()
	list=rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list,consume_pipeline); rd.compute_list_bind_uniform_set(list,consume_sets[live],0)
	rd.compute_list_dispatch(list,solver.grid_size/8,solver.grid_size/8,1)
	rd.compute_list_end()
	list=rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list,commit_pipeline); rd.compute_list_bind_uniform_set(list,commit_sets[live],0)
	rd.compute_list_dispatch(list,solver.grid_size/8,solver.grid_size/8,1); rd.compute_list_end()
	_support_dispatch(1)
	return true

func _ordinary_dispatch(delta_s: float) -> bool:
	# Keep step/slope/consume/commit resource usages in separate graph nodes.
	var live: int=solver.current_index
	var list:=rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list,step_pipeline); rd.compute_list_bind_uniform_set(list,step_sets[live],0)
	rd.compute_list_set_push_constant(list,PackedFloat32Array([delta_s,WET_RATE_PER_S,DRY_RATE_PER_S,DIFFUSION_PER_S,RESIDUAL_WETNESS,SOAK_DEPTH_M,DRY_DEPTH_M,COMPACT_RATE_PER_S]).to_byte_array(),32)
	rd.compute_list_dispatch(list,solver.grid_size/8,solver.grid_size/8,1)
	rd.compute_list_end()
	list=rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list,ordinary_pipeline); rd.compute_list_bind_uniform_set(list,ordinary_sets[live],0)
	var push:=super._slope_push(delta_s); rd.compute_list_set_push_constant(list,push,32)
	if local_pushes.size()<16: local_pushes.append({"revision":solver.state_revision,"bytes_hex":push.hex_encode(),"values":Array(push.to_float32_array()),"branch":"ordinary_direct"})
	rd.compute_list_dispatch(list,solver.grid_size/8,solver.grid_size/8,1)
	rd.compute_list_end()
	list=rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list,consume_pipeline); rd.compute_list_bind_uniform_set(list,consume_sets[live],0)
	rd.compute_list_dispatch(list,solver.grid_size/8,solver.grid_size/8,1)
	rd.compute_list_end()
	list=rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list,commit_pipeline); rd.compute_list_bind_uniform_set(list,commit_sets[live],0)
	rd.compute_list_dispatch(list,solver.grid_size/8,solver.grid_size/8,1); rd.compute_list_end()
	return true

func release() -> void:
	var device := rd if rd!=null else support_device
	if device!=null:
		for rid in ordinary_sets+[ordinary_pipeline,ordinary_shader,support_set,support_pipeline,support_shader]:
			if rid.is_valid(): device.free_rid(rid)
	support_set=RID(); support_pipeline=RID(); support_shader=RID()
	ordinary_sets.clear(); ordinary_pipeline=RID(); ordinary_shader=RID()
	super.release()
	if device!=null:
		for rid in [support_result,support_flags,support_indirect]:
			if rid.is_valid(): device.free_rid(rid)
	support_result=RID(); support_flags=RID(); support_indirect=RID()
	support_device=null

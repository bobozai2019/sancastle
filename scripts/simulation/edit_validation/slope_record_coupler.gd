extends "res://scripts/simulation/material/gpu_material_coupler.gd"

var record_buffer := RID()
var record_metadata := []
var record_spirv_sha256 := ""

func initialize(p_solver: SandcastleGpuShallowSolver,dirty: RID,step: RDShaderSPIRV,_slope: RDShaderSPIRV,commit: RDShaderSPIRV) -> bool:
	if p_solver==null or p_solver.rd==null or p_solver.grid_size!=256: return false
	var file: RDShaderFile=load("res://shaders/simulation/edit_validation/slope_output_record.glsl" if "--beach-slope-output" in OS.get_cmdline_user_args() else "res://shaders/simulation/edit_validation/slope_counter.glsl" if "--beach-slope-counter" in OS.get_cmdline_user_args() else "res://shaders/simulation/edit_validation/slope_record.glsl")
	if file==null: return false
	var code:=file.get_spirv()
	var compile_error:=code.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
	if not compile_error.is_empty(): push_error(compile_error);return false
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(code.call("get_stage_bytecode",RenderingDevice.SHADER_STAGE_COMPUTE));record_spirv_sha256=hash.finish().hex_encode()
	var bytes:=PackedByteArray();bytes.resize(16+4*128*32*4);bytes.fill(0)
	record_buffer=p_solver.rd.storage_buffer_create(bytes.size(),bytes)
	return record_buffer.is_valid() and super.initialize(p_solver,dirty,step,code,commit)

func _image_set(resources: Array[RID],shader: RID) -> RID:
	if shader!=slope_shader: return super._image_set(resources,shader)
	var uniforms: Array[RDUniform]=[]
	for binding in resources.size():
		var uniform:=RDUniform.new();uniform.uniform_type=RenderingDevice.UNIFORM_TYPE_IMAGE;uniform.binding=binding;uniform.add_id(resources[binding]);uniforms.append(uniform)
	var record:=RDUniform.new();record.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER;record.binding=7;record.add_id(record_buffer);uniforms.append(record)
	return rd.uniform_set_create(uniforms,shader,0)

func dispatch_after_erosion(delta_s: float) -> bool:
	record_metadata.append({"revision":solver.state_revision,"index":solver.current_index,"delta_s":delta_s})
	return super.dispatch_after_erosion(delta_s)

func release() -> void:
	var device:=rd
	super.release()
	if device!=null and record_buffer.is_valid(): device.free_rid(record_buffer)
	record_buffer=RID()

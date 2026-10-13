extends "res://scripts/simulation/material/gpu_material_coupler.gd"

# Default-off float contraction experiment; the formula and dispatch are intact.
func initialize(p_solver: SandcastleGpuShallowSolver, dirty_max_texture: RID, step_spirv: RDShaderSPIRV, _slope_spirv: RDShaderSPIRV, commit_spirv: RDShaderSPIRV) -> bool:
	var file: RDShaderFile=load("res://shaders/simulation/edit_validation/precise_slope_relax.glsl")
	if file==null: return false
	var code:=file.get_spirv()
	if not code.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE).is_empty(): return false
	return super.initialize(p_solver,dirty_max_texture,step_spirv,code,commit_spirv)

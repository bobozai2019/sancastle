extends RefCounted

# Isolated original display classes borrow verified physical inputs only.
const Foam=preload("res://scripts/simulation/edit_validation/checkpoint_foam_field.gd")
const Front=preload("res://tests/visual_water_alignment/prototypes/reference_local_front_field.gd")
const Gravel=preload("res://scripts/visual/gpu_gravel_field.gd")
const SOURCES=["res://tests/integration/unified_edit_legacy_visual_reference.gd","res://scripts/simulation/edit_validation/checkpoint_foam_field.gd","res://scripts/visual/gpu_foam_field.gd","res://tests/visual_water_alignment/prototypes/reference_local_front_field.gd"]
var solver: SandcastleGpuShallowSolver
var foam
var front
var gravel
var rd: RenderingDevice
var error:=""

func code(path: String) -> RDShaderSPIRV:
	var source:=RDShaderSource.new();source.source_compute=FileAccess.get_file_as_string(path).trim_prefix("#[compute]")
	var spirv:=rd.shader_compile_spirv_from_source(source);error=spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE);return spirv

func initialize(subject, domain, configuration: Dictionary) -> bool:
	rd=subject.state.rd;solver=SandcastleGpuShallowSolver.new();solver.rd=rd;solver.grid_size=256;solver.cell_size_m=0.125;solver.textures=subject.state.textures
	if subject.visuals.foam_enabled:
		foam=Foam.new();var bed: PackedFloat32Array=domain.rock.duplicate()
		for index in 65536:bed[index]+=domain.sand[index]
		if not foam.initialize(solver,code("res://shaders/simulation/visual_foam_step.glsl"),PackedFloat32Array(),bed):return false
	if subject.visuals.front_enabled:
		front=Front.new();var directory:="res://tests/visual_water_alignment/prototypes/"
		if not front.initialize(solver,foam,code(directory+("reference_local_front_x_wide.glsl" if configuration.environment.get("local_front_wide_field",false) else "reference_local_front_x.glsl")),code(directory+"reference_local_front_z.glsl")):return false
	if subject.visuals.gravel_enabled:
		gravel=Gravel.new()
		if not gravel.initialize(solver,code("res://shaders/simulation/visual_gravel_step.glsl"),subject.visuals.profile,domain.generation,0,0):return false
	return error.is_empty()

func step(dt: float) -> bool:
	if front!=null and not front.dispatch(solver,foam,true):return false
	if foam!=null and not foam.dispatch(solver,dt):return false
	if gravel!=null and not gravel.advance(solver,1,0,solver_generation(),dt):return false
	return true

func solver_generation() -> int:return gravel.generation

func reproject(tick: int, revision: int) -> bool:return gravel==null or gravel.reproject(solver,tick,revision,gravel.generation)

func output_images() -> Dictionary:
	var result: Dictionary={}
	if foam!=null:result.foam=foam.current_texture();result.bed=foam.bed_textures[foam.current_index]
	if front!=null:result.local_front=front.texture
	if gravel!=null:result.gravel=gravel.current_texture()
	return result

func release() -> void:
	if front!=null:front.release()
	if foam!=null:foam.release()
	if gravel!=null:gravel.release()
	if solver!=null:solver.textures={};solver.rd=null
	solver=null;foam=null;front=null;gravel=null;rd=null

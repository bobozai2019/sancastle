extends RefCounted

# Probe-only comparison. Legacy couplers build their original bindings against
# an isolated state copy; no old editor, queue, writer or lifecycle is started.
const SOURCES=["res://tests/integration/unified_edit_legacy_coupled_reference.gd","res://scripts/simulation/gpu_shallow_solver.gd","res://scripts/simulation/erosion/gpu_sediment_coupler.gd","res://scripts/simulation/material/gpu_material_coupler.gd","res://scripts/simulation/edit_validation/staged_slope_coupler.gd","res://scripts/simulation/brushes/brush_material_coupler.gd","res://scripts/simulation/edit_validation/frame_pipeline/async_coupled.gd","res://shaders/simulation/erosion/copy_after_boundary.glsl"]
var state
var channel
var water
var solver: SandcastleGpuShallowSolver
var sediment
var material
var coupled
var last_error:=""
var rd: RenderingDevice
var final_index:=0

func _code(path: String) -> RDShaderSPIRV:
	var source:=RDShaderSource.new();source.source_compute=FileAccess.get_file_as_string(path).trim_prefix("#[compute]")
	var code:=rd.shader_compile_spirv_from_source(source)
	last_error=code.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
	return code

func initialize(device: RenderingDevice, domain, decision: PackedByteArray) -> bool:
	rd=device;state=preload("res://scripts/simulation/unified_edit/state.gd").new();channel=preload("res://scripts/simulation/unified_edit/transport.gd").new()
	if not channel.initialize(rd,"main_beach",9007199254740993):last_error="reference_channel";return false
	if not state.initialize(rd,domain,channel):last_error="reference_state";return false
	water=preload("res://scripts/simulation/unified_edit/water.gd").new()
	if not water.initialize(state):last_error=water.last_error;return false
	# Borrow only typed resource fields; do not call this solver's initialize,
	# dispatch or release methods. State owns every borrowed physical image.
	solver=SandcastleGpuShallowSolver.new();solver.rd=rd;solver.grid_size=256;solver.cell_size_m=0.125;solver.textures=state.textures
	sediment=preload("res://scripts/simulation/erosion/gpu_sediment_coupler.gd").new()
	if not sediment.initialize(solver,_code("res://shaders/simulation/erosion/sediment_step.glsl"),_code("res://shaders/simulation/erosion/copy_after_boundary.glsl")):last_error="reference_sediment";return false
	material=preload("res://scripts/simulation/brushes/brush_material_coupler.gd").new()
	if not material.initialize(solver,sediment.dirty_max_texture,_code("res://shaders/simulation/material/material_step.glsl"),_code("res://shaders/simulation/edit_validation/staged_slope.glsl"),_code("res://shaders/simulation/material/material_commit.glsl")):last_error="reference_material";return false
	coupled=preload("res://scripts/simulation/edit_validation/frame_pipeline/async_coupled.gd").new()
	if not coupled.initialize(water,sediment,material):last_error=water.last_error;return false
	if rd.buffer_update(water.decision,0,64,decision)!=OK:last_error="reference_decision";return false
	var dispatches:=PackedByteArray();dispatches.resize(64*12)
	var steps:=decision.decode_u32(4)
	for step in 64:
		dispatches.encode_u32(step*12,32 if step<steps else 0);dispatches.encode_u32(step*12+4,32);dispatches.encode_u32(step*12+8,1)
	if rd.buffer_update(water.indirect,0,dispatches.size(),dispatches)!=OK:last_error="reference_dispatches";return false
	return true

func record(decision: PackedByteArray) -> void:
	var steps:=decision.decode_u32(4);var dt:=decision.decode_float(8)
	for step in steps:
		var index:=step%2
		state.dispatch("edge_flux",state.uniform_sets[index][0],Vector3i(32,32,1))
		state.dispatch("drain_scale",state.uniform_sets[index][1],Vector3i(32,32,1),PackedFloat32Array([dt/0.125,0,0,0]).to_byte_array())
		state.dispatch("update_state",state.uniform_sets[index][2],Vector3i(32,32,1),PackedFloat32Array([dt/0.125,0.125,0,0]).to_byte_array())
		coupled.record(water.decision,water.indirect,step,1-index)
	final_index=steps%2

func output_images() -> Dictionary:
	var output:={}
	for pair in [["sand","sand"],["water","water"],["sediment","sediment"],["qx","momentum_x"],["qz","momentum_z"],["wetness","wetness"],["compact","compaction"],["support","mold_support"],["flux","flux"]]:output[pair[0]]=state.textures[pair[1]][final_index]
	return output

func release() -> void:
	if coupled!=null:coupled.detach()
	if water!=null:water.release()
	if material!=null:material.release()
	if sediment!=null:sediment.release()
	if solver!=null:solver.textures={};solver.rd=null
	if state!=null:state.release()
	if channel!=null:channel.try_release()
	state=null;channel=null;water=null;solver=null;sediment=null;material=null;coupled=null;rd=null

class_name SandcastleGpuMaterialCoupler
extends RefCounted

## T05 wetness, compaction and conservative slope relaxation.
##
## Runs after the erosion pass of the same substep. All three fields live in the
## solver's ping-pong arrays, but only the water solver advances that index, so
## every pass here writes the spare slot and `material_commit.glsl` copies the
## spare slot back onto the live one.
##
## Sand mass is never created or destroyed: the slope pass only moves sand along
## shared edges that both cells evaluate identically.

## Wetness moves at a constant rate: a fully wet cell saturates in about a
## second, while an exposed one takes roughly ten to drain back to the residual.
const WET_RATE_PER_S := 1.5
const DRY_RATE_PER_S := 0.07
const RESIDUAL_WETNESS := 0.05
const SOAK_DEPTH_M := 0.06
const DIFFUSION_PER_S := 4.0
## Wet sand packs under its own weight; the rate is an approach, not a linear ramp.
const COMPACT_RATE_PER_S := 0.05
## Dry sand rests near 34 degrees, saturated sand near 45 degrees, and compaction
## adds a few more degrees before the slope lets go.
const DRY_REPOSE_TAN := 0.674
const WET_REPOSE_TAN := 1.0
const COMPACTION_REPOSE_GAIN := 0.3
## A slope relaxes towards the angle of repose by removing curvature, so a long
## flank flattens as a front travelling down it. The rate has to be brisk enough
## that a 30-cell pile settles in a few seconds rather than a minute.
const RELAX_RATE_PER_S := 15.0
const MIN_DROP_M := 0.0005
## Same wet/dry boundary as the erosion pass; material strength affects slope
## relaxation, while sediment exchange uses the competitor capacity rule.
const DRY_DEPTH_M := 0.001

var solver: SandcastleGpuShallowSolver
var rd: RenderingDevice
## S01 prototype switch. Zero retains the T05 repose-only path exactly.
var cohesion_yield_height_m := 0.0
var _dirty_max_texture := RID()
var step_shader := RID()
var step_pipeline := RID()
var step_sets: Array[RID] = []
var slope_shader := RID()
var slope_pipeline := RID()
var slope_sets: Array[RID] = []
var commit_shader := RID()
var commit_pipeline := RID()
var commit_sets: Array[RID] = []


func initialize(p_solver: SandcastleGpuShallowSolver, dirty_max_texture: RID,
		step_spirv: RDShaderSPIRV, slope_spirv: RDShaderSPIRV,
		commit_spirv: RDShaderSPIRV) -> bool:
	if p_solver == null or p_solver.rd == null or not dirty_max_texture.is_valid() or \
			step_spirv == null or slope_spirv == null or commit_spirv == null:
		return false
	solver = p_solver
	rd = solver.rd
	_dirty_max_texture = dirty_max_texture
	step_shader = rd.shader_create_from_spirv(step_spirv)
	slope_shader = rd.shader_create_from_spirv(slope_spirv)
	commit_shader = rd.shader_create_from_spirv(commit_spirv)
	if not step_shader.is_valid() or not slope_shader.is_valid() or \
			not commit_shader.is_valid():
		release()
		return false
	step_pipeline = rd.compute_pipeline_create(step_shader)
	slope_pipeline = rd.compute_pipeline_create(slope_shader)
	commit_pipeline = rd.compute_pipeline_create(commit_shader)
	if not step_pipeline.is_valid() or not slope_pipeline.is_valid() or \
			not commit_pipeline.is_valid():
		release()
		return false
	for live_index in 2:
		var spare_index := 1 - live_index
		if not _build_step_set(live_index, spare_index) or \
				not _build_slope_set(live_index, spare_index) or \
				not _build_commit_set(live_index, spare_index):
			release()
			return false
	return true


func _build_step_set(live_index: int, spare_index: int) -> bool:
	var resources: Array[RID] = [
		solver.textures["wetness"][live_index],
		solver.textures["compaction"][live_index],
		solver.textures["water"][live_index],
		solver.textures["sand"][live_index],
		solver.textures["obstacle"],
		solver.textures["wetness"][spare_index],
		solver.textures["compaction"][spare_index]]
	step_sets.append(_image_set(resources, step_shader))
	return step_sets[-1].is_valid()


func _build_slope_set(live_index: int, spare_index: int) -> bool:
	## The wetness/compaction read here is the slot material_step just wrote, so
	## the slump sees the same substep's moisture rather than the previous one.
	var resources: Array[RID] = [
		solver.textures["sand"][live_index],
		solver.textures["rock"],
		solver.textures["wetness"][spare_index],
		solver.textures["compaction"][spare_index],
		solver.textures["obstacle"],
		solver.textures["sand"][spare_index],
		_dirty_max_texture]
	slope_sets.append(_image_set(resources, slope_shader))
	return slope_sets[-1].is_valid()


func _build_commit_set(live_index: int, spare_index: int) -> bool:
	var resources: Array[RID] = [
		solver.textures["wetness"][spare_index],
		solver.textures["compaction"][spare_index],
		solver.textures["sand"][spare_index],
		solver.textures["wetness"][live_index],
		solver.textures["compaction"][live_index],
		solver.textures["sand"][live_index]]
	commit_sets.append(_image_set(resources, commit_shader))
	return commit_sets[-1].is_valid()


func _image_set(resources: Array[RID], shader: RID) -> RID:
	var uniforms: Array[RDUniform] = []
	for binding in resources.size():
		var uniform := RDUniform.new()
		uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		uniform.binding = binding
		uniform.add_id(resources[binding])
		uniforms.append(uniform)
	return rd.uniform_set_create(uniforms, shader, 0)


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
	rd.compute_list_set_push_constant(list, PackedFloat32Array([
		delta_s, solver.cell_size_m, RELAX_RATE_PER_S, DRY_REPOSE_TAN,
		WET_REPOSE_TAN, COMPACTION_REPOSE_GAIN, MIN_DROP_M,
		clampf(cohesion_yield_height_m, 0.0, 2.0)]).to_byte_array(), 32)
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


func release() -> void:
	if rd == null:
		return
	for set_list in [step_sets, slope_sets, commit_sets]:
		for uniform_set in set_list:
			if uniform_set.is_valid():
				rd.free_rid(uniform_set)
		set_list.clear()
	for rid in [step_pipeline, step_shader, slope_pipeline, slope_shader,
			commit_pipeline, commit_shader]:
		if rid.is_valid():
			rd.free_rid(rid)
	step_pipeline = RID()
	step_shader = RID()
	slope_pipeline = RID()
	slope_shader = RID()
	commit_pipeline = RID()
	commit_shader = RID()
	_dirty_max_texture = RID()
	rd = null
	solver = null

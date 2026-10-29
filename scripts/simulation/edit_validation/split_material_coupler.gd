extends "res://scripts/simulation/material/gpu_material_coupler.gd"

# Default-off list submission experiment, not a different numerical formula.
func dispatch_after_erosion(delta_s: float) -> bool:
	if rd==null or solver==null or not is_finite(delta_s) or delta_s<=0.0: return false
	var live_index:=solver.current_index
	_observe_stage("before",live_index)
	if solver.profile_passes: rd.capture_timestamp("sandcastle_material_start")
	var list:=rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list,step_pipeline)
	rd.compute_list_bind_uniform_set(list,step_sets[live_index],0)
	rd.compute_list_set_push_constant(list,PackedFloat32Array([delta_s,WET_RATE_PER_S,DRY_RATE_PER_S,DIFFUSION_PER_S,RESIDUAL_WETNESS,SOAK_DEPTH_M,DRY_DEPTH_M,COMPACT_RATE_PER_S]).to_byte_array(),32)
	rd.compute_list_dispatch(list,solver.grid_size/8,solver.grid_size/8,1)
	rd.compute_list_end()
	_observe_stage("step",live_index)
	list=rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list,slope_pipeline)
	rd.compute_list_bind_uniform_set(list,slope_sets[live_index],0)
	rd.compute_list_set_push_constant(list,PackedFloat32Array([delta_s,solver.cell_size_m,RELAX_RATE_PER_S,DRY_REPOSE_TAN,WET_REPOSE_TAN,COMPACTION_REPOSE_GAIN,MIN_DROP_M,clampf(cohesion_yield_height_m,0.0,2.0)]).to_byte_array(),32)
	rd.compute_list_dispatch(list,solver.grid_size/8,solver.grid_size/8,1)
	rd.compute_list_end()
	_observe_stage("slope",live_index)
	list=rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list,commit_pipeline)
	rd.compute_list_bind_uniform_set(list,commit_sets[live_index],0)
	rd.compute_list_dispatch(list,solver.grid_size/8,solver.grid_size/8,1)
	rd.compute_list_end()
	_observe_stage("commit",live_index)
	if solver.profile_passes: rd.capture_timestamp("sandcastle_material_end")
	return true

func _observe_stage(_stage: String, _live_index: int) -> void:
	pass

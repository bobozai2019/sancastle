extends "res://tests/shape_brushes/retention_trace_coupler.gd"

var barrier_calls := 0

func dispatch_after_erosion(delta_s: float) -> bool:
	if rd == null or solver == null or not is_finite(delta_s) or delta_s <= 0.0:
		return false
	var live_index := solver.current_index
	var spare_index := 1 - live_index
	if solver.profile_passes:
		rd.capture_timestamp("sandcastle_material_start")
	var list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list, step_pipeline)
	rd.compute_list_bind_uniform_set(list, step_sets[live_index], 0)
	rd.compute_list_set_push_constant(list, PackedFloat32Array([
		delta_s, WET_RATE_PER_S, DRY_RATE_PER_S, DIFFUSION_PER_S,
		RESIDUAL_WETNESS, SOAK_DEPTH_M, DRY_DEPTH_M,
		COMPACT_RATE_PER_S]).to_byte_array(), 32)
	rd.compute_list_dispatch(list, solver.grid_size / 8, solver.grid_size / 8, 1)
	rd.compute_list_add_barrier(list)

	rd.compute_list_bind_compute_pipeline(list, slope_pipeline)
	rd.compute_list_bind_uniform_set(list, slope_sets[live_index], 0)
	var slope_push := _slope_push(delta_s)
	rd.compute_list_set_push_constant(list, slope_push, slope_push.size())
	rd.compute_list_dispatch(list, solver.grid_size / 8, solver.grid_size / 8, 1)
	rd.compute_list_add_barrier(list)

	rd.compute_list_bind_compute_pipeline(list, consume_pipeline)
	rd.compute_list_bind_uniform_set(list, consume_sets[live_index], 0)
	rd.compute_list_dispatch(list, solver.grid_size / 8, solver.grid_size / 8, 1)
	rd.compute_list_set_push_constant(list,PackedByteArray(),0)
	rd.compute_list_add_barrier(list)

	rd.compute_list_bind_compute_pipeline(list, commit_pipeline)
	rd.compute_list_bind_uniform_set(list, commit_sets[live_index], 0)
	rd.compute_list_dispatch(list, solver.grid_size / 8, solver.grid_size / 8, 1)
	rd.compute_list_end()
	if solver.profile_passes:
		rd.capture_timestamp("sandcastle_material_end")
	barrier_calls+=3
	return true


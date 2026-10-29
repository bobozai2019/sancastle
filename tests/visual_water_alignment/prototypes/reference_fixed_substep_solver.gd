extends "res://tests/visual_water_alignment/prototypes/reference_batched_ledger_solver.gd"

## W07-only fixed substep experiment. The physical passes and coupling order
## remain the same, but this bypasses the CPU CFL decision for each tick.
func dispatch_tick_fixed(delta: float, substeps: int, revision: int,
		post_water_substep: Callable = Callable()) -> bool:
	if revision != state_revision or substeps < 1 or substeps > MAX_SUBSTEPS:
		return false
	max_substeps_used = maxi(max_substeps_used, substeps)
	for step_index in substeps:
		if not dispatch_substep(delta / float(substeps)):
			return false
		if post_water_substep.is_valid() and \
				not post_water_substep.call(delta / float(substeps)):
			return false
	return true

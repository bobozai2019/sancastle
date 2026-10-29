extends "res://assets/water_material_natural_candidate/compiled_worker_entry.gd"

func _create_solver() -> SandcastleGpuShallowSolver:
	return preload("res://scripts/simulation/edit_validation/lab_solver.gd").new()

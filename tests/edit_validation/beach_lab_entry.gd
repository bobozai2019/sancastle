extends "res://scripts/visual/test1_beach_edit_worker_entry.gd"

func _create_solver() -> SandcastleGpuShallowSolver:
	return preload("res://scripts/simulation/edit_validation/lab_solver.gd").new()

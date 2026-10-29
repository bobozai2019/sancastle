extends "res://tests/shape_brushes/snapshot_retention_probe.gd"

func _retention_scene_path() -> String:
	return "res://tests/shape_brushes/ordered_snapshot_retention_lab.tscn"

func _retention_resources_released() -> bool:
	_check("combined_actual_barrier_calls",preview.material_coupler.barrier_calls>=target_ticks*3,preview.material_coupler.barrier_calls)
	return super._retention_resources_released()

extends "res://tests/shape_brushes/retention_probe.gd"

func _retention_scene_path() -> String:
	return "res://tests/shape_brushes/original_retention_lab.tscn"

func _retention_resources_released() -> bool:
	return preview.gpu_release_done

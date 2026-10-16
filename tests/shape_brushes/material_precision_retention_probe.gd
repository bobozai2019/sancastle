extends "res://tests/shape_brushes/precise_retention_probe.gd"

func _retention_scene_path() -> String:
	return "res://tests/shape_brushes/material_precision_retention_lab.tscn"

func _retention_resources_released() -> bool:
	var file:=FileAccess.open(output.path_join("precision_identity.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(preview.precision_identity,"\t"));file.close()
	_check("material_precision_actual_identity",not preview.precision_identity.is_empty() and preview.precision_identity.actual_solver_script=="res://scripts/simulation/edit_validation/gpu_water_editor.gd")
	return preview.gpu_release_done

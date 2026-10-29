extends "res://tests/shape_brushes/original_retention_probe.gd"

func _retention_scene_path() -> String:
	return "res://tests/shape_brushes/precise_retention_lab.tscn"

func _retention_resources_released() -> bool:
	var file:=FileAccess.open(output.path_join("precision_identity.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(preview.precision_identity,"\t"));file.close()
	_check("precision_diagnostic_shader_identity",not preview.precision_identity.is_empty() and preview.precision_identity.original_source_sha256!=preview.precision_identity.diagnostic_source_sha256)
	return preview.gpu_release_done

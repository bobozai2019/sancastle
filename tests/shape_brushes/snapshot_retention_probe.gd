extends "res://tests/shape_brushes/original_retention_probe.gd"

func _retention_scene_path() -> String:
	return "res://tests/shape_brushes/snapshot_retention_lab.tscn"

func _retention_resources_released() -> bool:
	var file:=FileAccess.open(output.path_join("snapshot_identity.json"),FileAccess.WRITE)
	var identity: Dictionary=preview.snapshot_identity.duplicate(true)
	identity["copy_count"]=preview.snapshot_copy_count
	file.store_string(JSON.stringify(identity,"\t"));file.close()
	_check("snapshot_diagnostic_pool_released",preview.snapshot_inputs.is_empty() and preview.snapshot_device==null)
	return preview.gpu_release_done

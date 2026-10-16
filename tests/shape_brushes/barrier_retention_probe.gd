extends "res://tests/shape_brushes/original_retention_probe.gd"

func _retention_scene_path() -> String:
	return "res://tests/shape_brushes/barrier_retention_lab.tscn"

func _retention_resources_released() -> bool:
	_check("barrier_actual_calls",preview.material_coupler.barrier_calls>=target_ticks*3,preview.material_coupler.barrier_calls)
	var file:=FileAccess.open(output.path_join("barrier_identity.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"barrier_calls":preview.material_coupler.barrier_calls,"source_sha256":FileAccess.get_sha256("res://tests/shape_brushes/barrier_material_coupler.gd"),"shader_hashes":preview.material_coupler.staged_shader_hashes,"actual_solver_script":preview.solver.get_script().resource_path,"scope":"Only three in-list barriers added to original material choreography; no diagnostic copies/logger or production change."},"\t"));file.close()
	return preview.gpu_release_done

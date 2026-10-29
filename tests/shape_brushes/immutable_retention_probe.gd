extends "res://tests/shape_brushes/original_retention_probe.gd"

func _retention_scene_path() -> String:
	return "res://tests/shape_brushes/immutable_retention_lab.tscn"

func _retention_resources_released() -> bool:
	_check("immutable_material_pool_released",preview.material_coupler.immutable_inputs.is_empty())
	_check("immutable_material_copy_and_barriers_count",preview.material_coupler.input_copy_count>=target_ticks and preview.material_coupler.barrier_calls==preview.material_coupler.input_copy_count*3)
	var file:=FileAccess.open(output.path_join("immutable_identity.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"copy_count":preview.material_coupler.input_copy_count,"barrier_calls":preview.material_coupler.barrier_calls,"source_sha256":FileAccess.get_sha256("res://tests/shape_brushes/immutable_material_coupler.gd"),"shader_hashes":preview.material_coupler.staged_shader_hashes,"actual_solver_script":preview.solver.get_script().resource_path,"scope":"Two immutable material_step inputs plus in-list barriers, no sediment input copies, original shaders unchanged."},"\t"));file.close()
	return preview.gpu_release_done

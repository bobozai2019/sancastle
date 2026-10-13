extends SceneTree

func _initialize() -> void:
	var output := "res://test_output/water_material_natural/t01_profile_rejections"
	DirAccess.make_dir_recursive_absolute(output)
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/water_material_natural_candidate/texture_layers.json"))
	var rows := []
	for id in ["version", "hash", "mode", "direction", "gain", "layer_count", "extra_field", "wrong_type", "missing_field"]:
		var p := source.duplicate(true)
		match id:
			"version": p.candidate_schema_version = 99
			"hash": p.base_profile_sha256 = "bad"
			"mode": p.normal_detail.mode = "placeholder"
			"direction": p.normal_detail.layers[0].direction_xz = [0,0]
			"gain": p.normal_detail.layers[0].gain = -1
			"layer_count": p.normal_detail.layers.append(p.normal_detail.layers[0].duplicate())
			"extra_field": p["unconsumed"] = true
			"wrong_type": p.normal_detail.layers[0].gain = "invalid"
			"missing_field": p.normal_detail.erase("texture")
		var path: String = output + "/" + String(id) + ".json"
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string(JSON.stringify(p));file.close()
		var node: Node3D = load("res://scenes/water_material_natural_candidate/texture_layers.tscn").instantiate()
		node.candidate_profile_path = path
		node._ready()
		var rejected: bool = not node.candidate_error.is_empty() and not node.ready_for_ticks
		rows.append({"case": id, "rejected": rejected, "code": node.candidate_error})
		node.free()
		if not rejected:
			push_error("invalid candidate reached initialization")
			quit(1)
			return
	var file := FileAccess.open(output + "/report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass": true, "cases": rows, "scope": "runtime pre-initialization rejection"},"\t"));file.close()
	print("PASS: nine malformed candidates refused before simulation initialization")
	quit(0)

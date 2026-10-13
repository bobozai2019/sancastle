extends SceneTree

func _initialize() -> void:
	var output := "res://test_output/water_material_natural/t03_profile_rejections_v2"
	DirAccess.make_dir_recursive_absolute(output)
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/water_material_natural_candidate/optics_selected.json"))
	var rows := []
	for id in ["version","hash","mode","deep_range","gain_range","refraction_range","extra_field","wrong_type","missing_field","unset_extinction","schema1_new_mode"]:
		var p := source.duplicate(true)
		match id:
			"version": p.optics_schema_version = 99
			"hash": p.lighting_profile_sha256 = "bad"
			"mode": p.path_mode = "placeholder"
			"deep_range": p.extinction_deep_m = 0.0
			"gain_range": p.scatter_gain = -1
			"refraction_range": p.refraction_scale = 0.04
			"extra_field": p["unconsumed"] = true
			"wrong_type": p.shallow_preserve = 1
			"missing_field": p.erase("path_mode")
			"unset_extinction": p.extinction_deep_m = null
			"schema1_new_mode": p.optics_schema_version = 1
		var path: String = output + "/" + String(id) + ".json"
		var file := FileAccess.open(path,FileAccess.WRITE)
		file.store_string(JSON.stringify(p));file.close()
		var node: Node3D = load("res://scenes/water_material_natural_candidate/optics_reconstructed.tscn").instantiate()
		node.optics_profile_path = path
		node._ready()
		var rejected: bool = not node.candidate_error.is_empty() and not node.ready_for_ticks
		rows.append({"case":id,"rejected":rejected,"code":node.candidate_error})
		node.free()
		if not rejected:
			push_error("invalid optics reached initialization");quit(1);return
	var file := FileAccess.open(output+"/report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass":true,"cases":rows,"scope":"runtime pre-initialization rejection; no simulation"},"\t"));file.close()
	print("PASS: eleven malformed optics profiles rejected")
	quit(0)

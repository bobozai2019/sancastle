extends SceneTree

func _initialize() -> void:
	var output := "res://test_output/water_material_natural/t02_lighting_rejections"
	DirAccess.make_dir_recursive_absolute(output)
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/water_material_natural_candidate/lighting_engine.json"))
	var rows := []
	for id in ["version", "normal_hash", "gain", "gain_type", "shadow_type", "missing_foam", "extra_field", "missing_field", "schema1_engine"]:
		var p := source.duplicate(true)
		match id:
			"version": p.lighting_schema_version = 99
			"normal_hash": p.normal_profile_sha256 = "bad"
			"gain": p.sun_glint_gain = -1
			"gain_type": p.sun_glint_gain = "invalid"
			"shadow_type": p.shadow_enabled = 1
			"missing_foam": p.foam_shader = "res://assets/water_material_natural_candidate/missing.gdshader"
			"extra_field": p["unconsumed"] = true
			"missing_field": p.erase("water_shader")
			"schema1_engine":
				p.lighting_schema_version = 1
				p.erase("foam_shader")
		var path: String = output + "/" + String(id) + ".json"
		var file := FileAccess.open(path,FileAccess.WRITE)
		file.store_string(JSON.stringify(p));file.close()
		var node: Node3D = load("res://scenes/water_material_natural_candidate/lighting_engine.tscn").instantiate()
		node.lighting_profile_path = path
		node._ready()
		var rejected: bool = not node.candidate_error.is_empty() and not node.ready_for_ticks
		rows.append({"case":id,"rejected":rejected,"code":node.candidate_error})
		node.free()
		if not rejected:
			push_error("invalid lighting candidate reached simulation initialization")
			quit(1)
			return
	var file := FileAccess.open(output+"/report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass":true,"cases":rows,"scope":"pre-simulation runtime lighting profile rejection"},"\t"));file.close()
	print("PASS: nine invalid lighting profiles rejected before simulation")
	quit(0)

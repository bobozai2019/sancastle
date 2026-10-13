extends SceneTree

func _initialize() -> void:
	var output := "res://test_output/water_material_natural/t05_height_profile_rejections"
	DirAccess.make_dir_recursive_absolute(output)
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/water_material_natural_candidate/style_height.json"))
	var rows := []
	for id in ["missing_mode","unknown_mode","mode_type","missing_interface"]:
		var p := source.duplicate(true)
		match id:
			"missing_mode": p.erase("macro_normal_mode")
			"unknown_mode": p.macro_normal_mode = "placeholder"
			"mode_type": p.macro_normal_mode = true
			"missing_interface":
				p.reflection_profile = "res://assets/water_material_natural_candidate/reflection_oriented.json"
				p.reflection_profile_sha256 = FileAccess.get_sha256(p.reflection_profile)
		var path: String = output + "/" + id + ".json"
		var file := FileAccess.open(path,FileAccess.WRITE)
		file.store_string(JSON.stringify(p));file.close()
		var node: Node3D = load("res://scenes/water_material_natural_candidate/style_height.tscn").instantiate()
		node.style_profile_path = path;node._ready()
		var rejected: bool = not node.candidate_error.is_empty() and not node.ready_for_ticks
		rows.append({"case":id,"rejected":rejected,"code":node.candidate_error});node.free()
		if not rejected:push_error("invalid height profile reached initialization");quit(1);return
	var file := FileAccess.open(output + "/report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass":true,"cases":rows,
		"scope":"Pre-initialization schema2 rejection only. Expected reject errors; no GPU simulation."},"\t"));file.close()
	print("PASS: four malformed height profiles rejected");quit(0)

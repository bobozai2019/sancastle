extends SceneTree

func _initialize() -> void:
	var output := "res://test_output/water_material_natural/t05_style_profile_rejections"
	DirAccess.make_dir_recursive_absolute(output)
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/water_material_natural_candidate/style_combination.json"))
	var rows := []
	for id in ["version", "fractional_version", "extra", "reflection_hash", "bed_hash", "source_hash", "missing_base",
			"enabled_type", "strength", "softness", "scale", "gain", "exponent", "detail", "nonvisual_base"]:
		var p := source.duplicate(true)
		match id:
			"version": p.style_schema_version = 99
			"fractional_version": p.style_schema_version = 1.5
			"extra": p.unknown_field = true
			"reflection_hash": p.reflection_profile_sha256 = "bad"
			"bed_hash": p.bed_shader_sha256 = "bad"
			"source_hash": p.source_bed_shader_sha256 = "bad"
			"missing_base": p.base_profile = "res://missing_style_base.json"
			"enabled_type": p.caustics.enabled = 1
			"strength": p.caustics.strength = -1.
			"softness": p.caustics.softness = 1.1
			"scale": p.caustics.uv_scale = 0.
			"gain": p.glint.gain = 2.1
			"exponent": p.glint.exponent = 3.
			"detail": p.detail_gain_multiplier = 8.1
			"nonvisual_base":
				var base: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(p.base_profile))
				base.reference_bed = "flat"
				var base_path: String = output + "/nonvisual_base.json"
				var base_file := FileAccess.open(base_path, FileAccess.WRITE)
				base_file.store_string(JSON.stringify(base)); base_file.close()
				p.base_profile = base_path
		var path: String = output + "/" + id + ".json"
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string(JSON.stringify(p)); file.close()
		var node: Node3D = load("res://scenes/water_material_natural_candidate/style_combination.tscn").instantiate()
		node.style_profile_path = path; node._ready()
		var rejected: bool = not node.candidate_error.is_empty() and not node.ready_for_ticks
		rows.append({"case": id, "rejected": rejected, "code": node.candidate_error}); node.free()
		if not rejected: push_error("invalid style reached initialization"); quit(1); return
	var file := FileAccess.open(output + "/report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass": true, "cases": rows,
		"scope": "Pre-initialization rejection; expected reject errors, no simulation."}, "\t")); file.close()
	print("PASS: fifteen malformed style profiles rejected"); quit(0)

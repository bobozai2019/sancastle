extends SceneTree

const Fixtures = preload("res://tests/shape_brushes/fixtures.gd")
var output := ""

func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	if output.is_empty(): quit(1); return
	DirAccess.make_dir_recursive_absolute(output)
	var index := []
	for id in Fixtures.CASES:
		var fixture := Fixtures.build(id)
		var fields := {}
		for key in fixture.fields:
			var values: PackedFloat32Array = fixture.fields[key]
			if values.size() != 65536: quit(1); return
			for value in values:
				if not is_finite(value) or (key != "rock" and value < 0.0): quit(1); return
			var path := output.path_join(id + "_" + key + ".bin")
			var file := FileAccess.open(path, FileAccess.WRITE)
			file.store_buffer(values.to_byte_array()); file.close()
			fields[key] = {"path": path, "sha256": FileAccess.get_sha256(path), "bytes": 262144}
		fixture.fields = fields
		index.append(fixture)
	var file := FileAccess.open(output.path_join("fixture_index.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"fixtures": index, "generator_sha256": FileAccess.get_sha256("res://tests/shape_brushes/fixtures.gd"), "scope": "CPU initial data only; GPU upload validated at G2"}, "\t")); file.close()
	print("FIXTURES_PASS ", index.size())
	quit(0)

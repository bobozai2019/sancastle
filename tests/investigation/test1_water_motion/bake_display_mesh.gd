extends SceneTree

## Keep main's vertices/UV/diagonal; draw only test1's available capture rectangle.
func _initialize() -> void:
	var source: ArrayMesh = load("res://assets/test1_water_motion/main_grid.res")
	var arrays := source.surface_get_arrays(0)
	var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var cropped := PackedInt32Array()
	for i in range(0, indices.size(), 3):
		var inside := true
		for j in 3:
			var p := positions[indices[i + j]]
			inside = inside and absf(p.x) < 15.0 and absf(p.z) < 7.5
		if inside:
			cropped.append_array(indices.slice(i, i + 3))
	arrays[Mesh.ARRAY_INDEX] = cropped
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var error := ResourceSaver.save(mesh, "res://assets/test1_water_motion/main_capture_grid.res")
	print("main capture rectangle mesh: ", error, " triangles ", cropped.size() / 3)
	quit(error)

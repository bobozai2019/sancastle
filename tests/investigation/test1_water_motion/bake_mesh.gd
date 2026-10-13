extends SceneTree

func _initialize() -> void:
	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for z in 256:
		for x in 512:
			var uv := Vector2((float(x) + 0.5) / 512.0, (float(z) + 0.5) / 256.0)
			positions.append(Vector3((uv.x - 0.5) * 30.0, 0.0, -(uv.y - 0.5) * 15.0))
			normals.append(Vector3.UP)
			uvs.append(uv)
	for z in 255:
		for x in 511:
			var a := z * 512 + x
			indices.append_array(PackedInt32Array([a, a + 512, a + 1, a + 1, a + 512, a + 513]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var error := ResourceSaver.save(mesh, "res://assets/test1_water_motion/grid.res")
	print("test1 water mesh bake: ", error)
	quit(error)

extends SceneTree

func _initialize() -> void:
	var main_vertices := PackedVector3Array()
	var main_uvs := PackedVector2Array()
	for z in 512:
		for x in 512:
			main_vertices.append(Vector3((float(x) + 0.5) * 0.0625 - 16.0, 0, (float(z) + 0.5) * 0.0625 - 16.0))
			main_uvs.append(Vector2((float(x) + 0.5) / 512.0, (float(z) + 0.5) / 512.0))
	_bake("main_boundary", main_vertices, main_uvs, 512, 512)
	var geometry: ArrayMesh = load("res://assets/test1_geometry/visible_grid.res")
	var data := geometry.surface_get_arrays(0)
	_bake("test1_boundary", data[Mesh.ARRAY_VERTEX], data[Mesh.ARRAY_TEX_UV], 481, 241)
	print("WATER_SIDES_MESHES_SAVED")
	quit()

func _bake(name: String, top_vertices: PackedVector3Array, top_uvs: PackedVector2Array, width: int, height: int) -> void:
	# Copy the actual top grid vertices. Independent lerp introduces roundoff.
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var outward := [Vector3.FORWARD, Vector3.RIGHT, Vector3.BACK, Vector3.LEFT]
	var starts := [0, width-1, width*height-1, (height-1)*width]
	var strides := [1, width, -1, -width]
	var counts := [width, height, width, height]
	for face in 4:
		var base := vertices.size()
		for i in counts[face]:
			var index: int = starts[face] + i * strides[face]
			for upper in 2:
				vertices.append(top_vertices[index])
				uvs.append(top_uvs[index])
				normals.append(outward[face])
				colors.append(Color(float(upper), 0, 0, 1))
		for i in counts[face] - 1:
			var j: int = base + 2 * i
			# Godot's outward front faces are clockwise (opposite cross normal).
			indices.append_array(PackedInt32Array([j, j + 3, j + 1, j, j + 2, j + 3]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.custom_aabb = AABB(Vector3(-16, -32, -16), Vector3(32, 96, 32))
	assert(ResourceSaver.save(mesh, "res://assets/water_sides/" + name + ".res", ResourceSaver.FLAG_COMPRESS) == OK)

extends SceneTree

const OUT := "res://assets/test1_geometry/"

func save_mesh(name: String, vertices: PackedVector3Array, uvs: PackedVector2Array, indices: PackedInt32Array, normals: PackedVector3Array, colors: PackedColorArray = PackedColorArray()) -> void:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	arrays[Mesh.ARRAY_NORMAL] = normals
	if not colors.is_empty(): arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.custom_aabb = AABB(Vector3(-15, -0.15, -7.5), Vector3(30, 10.15, 15))
	var error := ResourceSaver.save(mesh, OUT + name + ".res", ResourceSaver.FLAG_COMPRESS)
	assert(error == OK)

func _initialize() -> void:
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var normals := PackedVector3Array()
	for z in 241:
		for x in 481:
			var p := Vector3(-15.0 + x * 0.0625, 0, -7.5 + z * 0.0625)
			vertices.append(p)
			uvs.append(Vector2((p.x + 16.0) / 32.0, (p.z + 16.0) / 32.0))
			normals.append(Vector3.UP)
	for z in 240:
		for x in 480:
			var i := z * 481 + x
			indices.append_array(PackedInt32Array([i, i + 482, i + 1, i, i + 481, i + 482]))
	save_mesh("visible_grid", vertices, uvs, indices, normals)
	vertices.clear(); uvs.clear(); indices.clear(); normals.clear()
	var colors := PackedColorArray()
	var corners := [Vector3(-15, 0, -7.5), Vector3(15, 0, -7.5), Vector3(15, 0, 7.5), Vector3(-15, 0, 7.5)]
	var face_normals := [Vector3.FORWARD, Vector3.RIGHT, Vector3.BACK, Vector3.LEFT]
	for side in 4:
		var a: Vector3 = corners[side]
		var b: Vector3 = corners[(side + 1) % 4]
		var steps := roundi(a.distance_to(b) / 0.0625)
		var base := vertices.size()
		for j in steps + 1:
			var p := a.lerp(b, float(j) / steps)
			for top in 2:
				vertices.append(p)
				uvs.append(Vector2((p.x + 16) / 32, (p.z + 16) / 32))
				normals.append(face_normals[side])
				colors.append(Color(float(top), 0, 0, 1))
		for j in steps:
			var i := base + j * 2
			indices.append_array(PackedInt32Array([i, i + 1, i + 3, i, i + 3, i + 2]))
	save_mesh("sand_sides", vertices, uvs, indices, normals, colors)
	print("TEST1_GEOMETRY_MESHES_SAVED")
	quit()

extends SceneTree

# Run only when the fixed prototype topology changes. Runtime scene setup loads
# these saved meshes; field-driven positions still come from the vertex shader.
const GRID_SIZE := 256
const CELL_SIZE_M := 0.125
const LAYERS := 9


func _initialize() -> void:
	var row := _make_mesh(false)
	var branches := _make_mesh(true)
	var base := "res://tests/visual_water_alignment/prototypes/"
	var row_error := ResourceSaver.save(row, base + "reference_front_lip_row_mesh.tres")
	var branch_error := ResourceSaver.save(branches,
		base + "reference_front_lip_branch_mesh.tres")
	if row_error != OK or branch_error != OK:
		push_error("front lip mesh resource save failed: %s/%s" % [row_error, branch_error])
		quit(1)
		return
	quit(0)


func _make_mesh(branches: bool) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var candidate_uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var candidates := range(80, 249, 4) if branches else [0]
	for candidate in candidates:
		var base := vertices.size()
		var candidate_uv := (float(candidate) + 0.5) / float(GRID_SIZE)
		for z in GRID_SIZE:
			var world_z := (float(z) + 0.5) * CELL_SIZE_M - 16.0
			var row_uv := (float(z) + 0.5) / float(GRID_SIZE)
			for layer in LAYERS:
				vertices.append(Vector3(0.0, 0.0, world_z))
				uvs.append(Vector2(float(layer) / float(LAYERS - 1), row_uv))
				if branches:
					candidate_uvs.append(Vector2(candidate_uv, row_uv))
		for z in GRID_SIZE - 1:
			for layer in LAYERS - 1:
				var i := base + z * LAYERS + layer
				indices.append_array(PackedInt32Array([
					i, i + LAYERS, i + 1,
					i + 1, i + LAYERS, i + LAYERS + 1]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	if branches:
		arrays[Mesh.ARRAY_TEX_UV2] = candidate_uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return result

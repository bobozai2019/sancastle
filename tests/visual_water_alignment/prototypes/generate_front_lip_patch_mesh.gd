extends SceneTree

# Offline-only mesh builder. Each Z cell owns its face, so disconnected front
# branches cannot form triangles across inactive rows at runtime.
const GRID_SIZE := 256
const CELL_SIZE_M := 0.125
const LAYERS := 9
const OUTPUT := "res://tests/visual_water_alignment/prototypes/reference_front_lip_patch_mesh.tres"


func _initialize() -> void:
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var candidate_uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for candidate in range(80, 249, 4):
		var candidate_uv := (float(candidate) + 0.5) / float(GRID_SIZE)
		for z in GRID_SIZE:
			var row_uv := (float(z) + 0.5) / float(GRID_SIZE)
			var base := vertices.size()
			for edge in 2:
				var world_z := float(z + edge) * CELL_SIZE_M - 16.0
				for layer in LAYERS:
					vertices.append(Vector3(0.0, 0.0, world_z))
					uvs.append(Vector2(float(layer) / float(LAYERS - 1), row_uv))
					candidate_uvs.append(Vector2(candidate_uv, row_uv))
			for layer in LAYERS - 1:
				var a := base + layer
				var b := base + LAYERS + layer
				indices.append_array(PackedInt32Array([
					a, b, a + 1, a + 1, b, b + 1]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = candidate_uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var err := ResourceSaver.save(mesh, OUTPUT)
	if err != OK:
		push_error("front lip patch mesh save failed: " + str(err))
		quit(1)
		return
	print("PASS: saved front lip patch mesh vertices=" + str(vertices.size()) +
		" indices=" + str(indices.size()))
	quit(0)

extends SceneTree

# Editor/offline resource generation. The local front and wetness remain GPU
# data-driven; the fixed quad topology is saved for scene instancing.
const ROWS := 256
const SLOTS := 128


func _initialize() -> void:
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var corners := PackedVector2Array()
	var indices := PackedInt32Array()
	for z in ROWS:
		var row_uv := (float(z) + 0.5) / float(ROWS)
		var world_z := row_uv * 32.0 - 16.0
		for slot in SLOTS:
			var base := vertices.size()
			var slot_uv := (float(slot) + 0.5) / float(SLOTS)
			for corner in [Vector2(0.0, 0.0), Vector2(1.0, 0.0),
					Vector2(0.0, 1.0), Vector2(1.0, 1.0)]:
				vertices.append(Vector3(0.0, 0.0, world_z))
				uvs.append(Vector2(slot_uv, row_uv))
				corners.append(corner)
			indices.append_array(PackedInt32Array([
				base, base + 2, base + 1,
				base + 1, base + 2, base + 3]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = corners
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var path := "res://tests/visual_water_alignment/prototypes/reference_front_foam_dense_mesh.tres"
	var result := ResourceSaver.save(mesh, path)
	if result != OK:
		push_error("front foam mesh save failed: %d" % result)
		quit(1)
		return
	quit(0)

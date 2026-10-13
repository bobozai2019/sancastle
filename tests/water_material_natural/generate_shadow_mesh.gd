extends SceneTree

func _initialize() -> void:
	var selected := PackedInt32Array()
	for i in range(0,512,2): selected.append(i)
	selected.append(511)
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for z in selected:
		for x in selected:
			var uv := Vector2((float(x)+0.5)/512.0,(float(z)+0.5)/512.0)
			uvs.append(uv)
			vertices.append(Vector3(uv.x*32.0-16.0,0.0,uv.y*32.0-16.0))
	var width := selected.size()
	for z in range(width-1):
		for x in range(width-1):
			var i := z*width+x
			indices.append_array(PackedInt32Array([i,i+width+1,i+1,i,i+width,i+width+1]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices
	arrays[Mesh.ARRAY_TEX_UV]=uvs
	arrays[Mesh.ARRAY_INDEX]=indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	mesh.set_meta("source_grid_width",512)
	mesh.set_meta("selected_source_indices",selected)
	var path := "res://assets/water_material_natural_candidate/shadow_grid257.res"
	if ResourceSaver.save(mesh,path,ResourceSaver.FLAG_COMPRESS)!=OK:
		quit(1)
		return
	print("PASS: static shadow mesh 257x257, exact source UV subset, visible mesh unchanged")
	quit(0)

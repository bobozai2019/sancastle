extends SceneTree

func _initialize() -> void:
	var entry = load("res://tests/visual_water_alignment/prototypes/reference_preview.gd").new()
	var mesh: ArrayMesh = entry._make_grid_mesh(2)
	var error := ResourceSaver.save(mesh,"res://assets/approx_gpu_edit/grid_mesh.res")
	entry.free()
	print("grid bake: ",error)
	quit(error)

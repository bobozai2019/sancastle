extends SceneTree

func _initialize() -> void:
	var results:={}
	for key in ["main","test1_geometry"]:
		var scene: Node3D=load("res://scenes/main.tscn" if key=="main" else "res://scenes/playable/test1_geometry.tscn").instantiate()
		var node: MeshInstance3D=scene.get_node("GpuWaterSurface")
		var transform:=node.transform
		var parent:=node.get_parent()
		while parent!=null:
			if parent is Node3D:transform=parent.transform*transform
			parent=parent.get_parent()
		var arrays:=node.mesh.surface_get_arrays(0)
		var uv: PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV]
		var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var error:=0.0
		var minimum:=Vector2(INF,INF);var maximum:=Vector2(-INF,-INF)
		for i in vertices.size():
			minimum=minimum.min(uv[i]);maximum=maximum.max(uv[i])
			var world:=transform*vertices[i]
			error=max(error,(Vector2(world.x,world.z)-(uv[i]*32.0-Vector2(16,16))).length())
		results[key]={"vertices":vertices.size(),"transform":var_to_str(transform),"mesh":node.mesh.resource_path,"uv_min":var_to_str(minimum),"uv_max":var_to_str(maximum),"uv32_minus16_world_xz_error_m":error,"note":"Authored formal-entry transforms; scene not added to tree and simulation not booted"}
		scene.free()
	FileAccess.open("res://task/water_foam_visual/验收/G0/geometry_coordinates.json",FileAccess.WRITE).store_string(JSON.stringify(results,"\t"))
	print(JSON.stringify(results))
	quit()

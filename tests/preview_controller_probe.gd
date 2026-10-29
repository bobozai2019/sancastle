extends SceneTree

const PREVIEW := preload("res://scenes/editor_scene_preview.tscn")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var edited := PREVIEW.instantiate()
	var untouched := PREVIEW.instantiate()
	root.add_child(edited)
	root.add_child(untouched)
	edited.preview_size_m = 12.0
	edited.water_coverage = 0.5
	edited.water_level_m = 0.42
	edited.water_color = Color(0.12, 0.34, 0.76, 0.55)
	edited.wave_height_m = 0.21
	edited.dune_height_m = 2.0
	edited.trigger_origin_m = Vector2(-2.0, 1.0)
	edited.trigger_water_wave()
	await process_frame
	await process_frame
	var terrain_mesh := edited.get_node("TerrainPreview").mesh as PlaneMesh
	var water_node := edited.get_node("WaterPreview") as MeshInstance3D
	var water_mesh := water_node.mesh as PlaneMesh
	var water_material := water_mesh.material as ShaderMaterial
	var untouched_terrain := untouched.get_node("TerrainPreview").mesh as PlaneMesh
	var untouched_water := untouched.get_node("WaterPreview") as MeshInstance3D
	var untouched_water_material := (untouched_water.mesh as PlaneMesh).material as ShaderMaterial
	if terrain_mesh.size != Vector2(12.0, 12.0) or \
			water_mesh.size.x != 6.0 or not is_equal_approx(water_node.position.y, 0.42) or \
			not is_equal_approx(float(water_material.get_shader_parameter("wave_height_m")), 0.21) or \
			float(water_material.get_shader_parameter("trigger_age_s")) <= 0.0 or \
			untouched_water_material.get_shader_parameter("water_color") != \
				Color(0.04, 0.72, 0.69, 0.68) or \
			untouched_terrain.size != Vector2(32.0, 32.0):
		printerr("FAIL: editor preview controller did not update isolated resources")
		quit(1)
		return
	print("PASS: split terrain/water preview scenes and wave trigger controller")
	quit(0)

extends SceneTree

const SCENE := preload("res://scenes/sand_visual_fixture.tscn")

var preview: Node3D


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	preview = SCENE.instantiate()
	root.add_child(preview)
	var material := preview.water_material as ShaderMaterial
	var editor_water := preview.get_node(
		"VisualEditorPreview/WaterPreview") as MeshInstance3D
	var editor_material := (editor_water.mesh as PlaneMesh).material as ShaderMaterial
	if material.get_shader_parameter("phase2_optics") != true or \
			material.get_shader_parameter("phase2_foam") != false or \
			material.get_shader_parameter("phase2_shallow_tint") != \
				Vector3(0.04, 0.72, 0.69) or \
			editor_material.get_shader_parameter("water_color") != \
				Color(0.26, 0.66, 0.49, 0.68) or \
			editor_material.get_shader_parameter("output_color_bias") != \
				Vector3(0.0425, 0.075, 0.1245):
		printerr("FAIL: sand_v1 editor/runtime water profiles disagree")
		preview.queue_free()
		quit(1)
		return
	var frames := 0
	while not preview.ready_for_ticks and preview.last_error.is_empty() and frames < 600:
		await process_frame
		frames += 1
	if not preview.last_error.is_empty() or not preview.ready_for_ticks:
		printerr("FAIL: sand_v1 GPU setup failed: " + preview.last_error)
		preview.queue_free()
		quit(1)
		return
	print("PASS: sand_v1 editor and triggered runtime water use phase-2 teal profile")
	preview.queue_free()
	for _frame in 8:
		await process_frame
	quit(0)

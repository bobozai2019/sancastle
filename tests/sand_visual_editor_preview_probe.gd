@tool
extends SceneTree

const SCENE := preload("res://scenes/sand_visual_fixture.tscn")
const EDITOR_STILL := "res://logs/sand_visual_actual_editor_still.png"
const EDITOR_WAVE := "res://logs/sand_visual_actual_editor_wave.png"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if not Engine.is_editor_hint():
		printerr("FAIL: run this probe with --editor")
		quit(1)
		return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var scene := SCENE.instantiate()
	viewport.add_child(scene)
	await process_frame
	var controller := scene.get_node_or_null("VisualEditorPreview") as Node3D
	var terrain := scene.get_node_or_null(
		"VisualEditorPreview/TerrainPreview") as MeshInstance3D
	var water := scene.get_node_or_null(
		"VisualEditorPreview/WaterPreview") as MeshInstance3D
	if controller == null or terrain == null or water == null or \
			not controller.is_visible_in_tree() or \
			not terrain.is_visible_in_tree() or not water.is_visible_in_tree() or \
			terrain.mesh == null or water.mesh == null or \
			(water.mesh as PlaneMesh).size.x < 2.0 or \
			water.custom_aabb.size.y < 4.0:
		printerr("FAIL: visual editor terrain/water preview is missing or hidden")
		quit(1)
		return
	var button: Callable = controller.get("trigger_water_wave_action")
	if not button.is_valid():
		printerr("FAIL: visual editor wave button is missing")
		quit(1)
		return
	for _frame in 40:
		await process_frame
	await RenderingServer.frame_post_draw
	if viewport.get_texture().get_image().save_png(EDITOR_STILL) != OK:
		printerr("FAIL: could not save editor still frame")
		quit(1)
		return
	button.call()
	for _frame in 25:
		await process_frame
	await RenderingServer.frame_post_draw
	if viewport.get_texture().get_image().save_png(EDITOR_WAVE) != OK:
		printerr("FAIL: could not save editor wave frame")
		quit(1)
		return
	var material := (water.mesh as PlaneMesh).material as ShaderMaterial
	if float(material.get_shader_parameter("trigger_age_s")) <= 0.0:
		printerr("FAIL: visual editor wave button did not advance the shader")
		quit(1)
		return
	print("PASS: sand visual editor meshes are visible and wave button advances")
	quit(0)

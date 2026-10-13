extends SceneTree

const SCENE := preload("res://scenes/sand_coupled_fixture.tscn")
const EDITOR_FRAME := "res://logs/sand_coupled_editor_water.png"
const EDITOR_DRY_FRAME := "res://logs/sand_coupled_editor_dry.png"
const RUNTIME_FRAME := "res://logs/sand_coupled_runtime_water.png"
const RUNTIME_DRY_FRAME := "res://logs/sand_coupled_runtime_dry.png"

var preview: Node3D


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	preview = SCENE.instantiate()
	root.add_child(preview)
	var frames := 0
	while not preview.ready_for_ticks and preview.last_error.is_empty() and frames < 1200:
		await process_frame
		frames += 1
	if not preview.last_error.is_empty() or not preview.ready_for_ticks:
		_fail("fixture did not initialize: " + preview.last_error)
		return
	preview.playing = false
	while preview.tick_pending:
		await process_frame
	var controller: Node3D = preview.get_node("EditorPreviewController")
	controller.visible = true
	preview.get_node("GpuSandTerrain").visible = false
	preview.get_node("GpuWaterSurface").visible = false
	controller.get_node("WaterPreview").visible = false
	for _frame in 3:
		await process_frame
	if root.get_texture().get_image().save_png(EDITOR_DRY_FRAME) != OK:
		_fail("editor dry frame save failed")
		return
	controller.get_node("WaterPreview").visible = true
	for _frame in 3:
		await process_frame
	if root.get_texture().get_image().save_png(EDITOR_FRAME) != OK:
		_fail("editor preview frame save failed")
		return
	controller.visible = false
	preview.get_node("GpuSandTerrain").visible = true
	preview.get_node("GpuWaterSurface").visible = true
	for _frame in 4:
		await process_frame
	if root.get_texture().get_image().save_png(RUNTIME_FRAME) != OK:
		_fail("runtime frame save failed")
		return
	preview.get_node("GpuWaterSurface").visible = false
	for _frame in 2:
		await process_frame
	if root.get_texture().get_image().save_png(RUNTIME_DRY_FRAME) != OK:
		_fail("runtime dry frame save failed")
		return
	print("PASS: sand coupled editor/runtime comparison frames saved")
	preview.queue_free()
	quit(0)


func _fail(message: String) -> void:
	printerr("FAIL: " + message)
	if preview != null:
		preview.queue_free()
	quit(1)

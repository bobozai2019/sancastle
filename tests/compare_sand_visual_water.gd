extends SceneTree

const SCENE := preload("res://scenes/sand_visual_fixture.tscn")
const EDITOR_FRAME := "res://logs/sand_visual_editor_water.png"
const EDITOR_DRY_FRAME := "res://logs/sand_visual_editor_dry.png"
const RUNTIME_FRAME := "res://logs/sand_visual_runtime_water.png"
const RUNTIME_DRY_FRAME := "res://logs/sand_visual_runtime_dry.png"

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
	var controller: Node3D = preview.get_node("VisualEditorPreview")
	controller.visible = true
	preview.get_node("GpuSandTerrain").visible = false
	preview.get_node("GpuWaterSurface").visible = false
	controller.get_node("WaterPreview").visible = false
	for _frame in 2:
		await process_frame
	if root.get_texture().get_image().save_png(EDITOR_DRY_FRAME) != OK:
		_fail("editor dry frame save failed")
		return
	controller.trigger_water_wave()
	for _frame in 30:
		await process_frame
	if root.get_texture().get_image().save_png(EDITOR_FRAME) != OK:
		_fail("editor preview frame save failed")
		return
	controller.visible = false
	preview.get_node("GpuSandTerrain").visible = true
	preview.get_node("GpuWaterSurface").visible = true
	var start_tick: int = preview.completed_ticks + 2
	var admitted: Dictionary = preview.request_wave({
		"domain_id": preview.shadow_domain.domain_id,
		"generation": preview.generation,
		"request_id": 1,
		"start_tick": start_tick,
		"profile_id": &"test_packet",
		"amplitude_m": 0.20,
		"duration_s": 3.0,
		"seed": 19,
	})
	if not admitted.ok:
		_fail("runtime wave rejected: " + String(admitted.code))
		return
	preview.playing = true
	while preview.completed_ticks < start_tick + 45 and preview.last_error.is_empty() and frames < 6000:
		await process_frame
		frames += 1
	preview.playing = false
	while preview.tick_pending:
		await process_frame
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
	print("PASS: sand visual editor/runtime comparison frames saved")
	preview.queue_free()
	quit(0)


func _fail(message: String) -> void:
	printerr("FAIL: " + message)
	if preview != null:
		preview.queue_free()
	quit(1)

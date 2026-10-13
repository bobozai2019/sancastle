extends SceneTree

const SCENE := preload("res://scenes/sand_visual_fixture.tscn")
const BEFORE := "res://logs/sand_visual_wave_before.png"
const AFTER := "res://logs/sand_visual_wave_after.png"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := SCENE.instantiate()
	root.add_child(scene)
	var frames := 0
	while not scene.ready_for_ticks and scene.last_error.is_empty() and frames < 1200:
		await process_frame
		frames += 1
	if not scene.ready_for_ticks:
		printerr("FAIL: fixture setup: ", scene.last_error)
		quit(1)
		return
	scene.playing = false
	scene.get_node("GpuSandTerrain").visible = false
	scene.get_node("GpuWaterSurface").visible = false
	var controller := scene.get_node("VisualEditorPreview") as Node3D
	controller.visible = true
	controller.wave_height_m = 0.0
	for _frame in 4:
		await process_frame
	root.get_texture().get_image().save_png(BEFORE)
	var button: Callable = controller.get("trigger_water_wave_action")
	if not button.is_valid():
		printerr("FAIL: Inspector wave button is not callable")
		quit(1)
		return
	button.call()
	for _frame in 20:
		await process_frame
	root.get_texture().get_image().save_png(AFTER)
	var material := (controller.get_node("WaterPreview").mesh as PlaneMesh).material as ShaderMaterial
	var age := float(material.get_shader_parameter("trigger_age_s"))
	if age <= 0.0 or age >= controller.trigger_duration_s:
		printerr("FAIL: wave button did not advance animation; age=", age)
		quit(1)
		return
	print("PASS: visual wave button advances animation; age=", age)
	quit(0)

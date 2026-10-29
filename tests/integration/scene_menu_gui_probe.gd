extends SceneTree

var scene
var output := "D:/godot/project/sandcastle/test_output/scene_switch_gui_20261013"
var checks := []

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	call_deferred("_run")

func check(name: String, value: bool) -> void:
	checks.append({"name": name, "pass": value})
	print("SCENE_GUI_CHECK ", name, " ", value)

func _run() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	scene.playing = false
	root.add_child(scene)
	current_scene = scene
	while not scene.ready_for_ticks and scene.last_error.is_empty():
		await process_frame
	var service = root.get_node("BeachScenes")
	var panel: Node = scene.get_node("Interface/EditPanel/Margin/Controls/SceneSwitcher")
	panel.targets.select(1)
	await process_frame
	var click := InputEventMouseButton.new()
	click.position = panel.switch_button.get_global_rect().get_center()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	Input.parse_input_event(click.duplicate())
	await process_frame
	click.pressed = false
	Input.parse_input_event(click.duplicate())
	await process_frame
	check("real_gui_switch_started", service.busy)
	var deadline := Time.get_ticks_msec() + 120000
	while service.busy and Time.get_ticks_msec() < deadline:
		await process_frame
	scene = service.active_scene
	check("real_gui_switch_completed", not service.busy and service.last_error.is_empty() and scene.scene_key == "test1_capture")
	var record: Dictionary = preload("res://scripts/simulation/checkpoint_store.gd").load(service.saved.main.path)
	check("gui_click_created_no_sand_command", record.error.is_empty() and record.checkpoint.gpu_beach_edit.prefix.is_empty() and record.checkpoint.shadow.tool_inventory_m3 == 0.0)
	await scene.shutdown()
	var passed := true
	for row in checks:
		passed = passed and row.pass
	var file := FileAccess.open(output.path_join("result.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass": passed, "checks": checks}, "\t"))
	quit(0 if passed else 1)

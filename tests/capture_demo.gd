extends SceneTree


func _init() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var scene: PackedScene = load("res://scenes/cpu_reference.tscn")
	if scene == null:
		printerr("FAIL: main scene missing")
		quit(1)
		return
	var demo: Node3D = scene.instantiate()
	root.add_child(demo)
	for _frame in 15:
		await process_frame
	var image := root.get_texture().get_image()
	var path := "res://test_output/sandcastle_water_sand_coupling/验收/CPU_demo_20260928.png"
	var err := image.save_png(path)
	if err != OK:
		printerr("FAIL: demo screenshot: %d" % err)
		quit(1)
		return
	print("PASS: saved CPU demo screenshot " + path)
	quit(0)

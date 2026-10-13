extends SceneTree


func _init() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var scene: PackedScene = load("res://scenes/cpu_reference.tscn")
	if scene == null:
		printerr("FAIL: standard scene missing")
		quit(1)
		return
	var demo: Node3D = scene.instantiate()
	root.add_child(demo)
	demo.playing = false
	for preset in 3:
		demo._reset_domain(preset)
		demo._update_visuals()
		for _frame in 3:
			await process_frame
		var image := root.get_texture().get_image()
		if image == null or image.is_empty():
			printerr("FAIL: standard scene viewport image missing")
			quit(1)
			return
		var path := "res://test_output/sandcastle_water_sand_coupling/验收/T00_scenario_0%d_20260928.png" % (preset + 1)
		if image.save_png(path) != OK:
			printerr("FAIL: standard scene screenshot failed")
			quit(1)
			return
	print("PASS: captured three fixed-camera fixed-seed standard scenes")
	quit(0)

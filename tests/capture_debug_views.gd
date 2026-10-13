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
	demo.playing = false
	demo._reset_domain(2)
	var names := ["normal", "height", "slope", "sand", "compaction"]
	for view in names.size():
		demo.debug_view = view
		demo._update_visuals()
		for _frame in 3:
			await process_frame
		var image := root.get_texture().get_image()
		if image == null or image.is_empty():
			printerr("FAIL: debug screenshot unavailable")
			quit(1)
			return
		var path := "res://test_output/sandcastle_water_sand_coupling/验收/T01_debug_%s_20260928.png" % names[view]
		var error := image.save_png(path)
		if error != OK:
			printerr("FAIL: debug screenshot save error %d" % error)
			quit(1)
			return
	print("PASS: captured five terrain views including four pseudocolor diagnostics")
	quit(0)

extends SceneTree


func _init() -> void:
	call_deferred("_record")


func _record() -> void:
	var scene: PackedScene = load("res://scenes/cpu_reference.tscn")
	if scene == null:
		printerr("FAIL: main scene missing")
		quit(1)
		return
	var demo: Node3D = scene.instantiate()
	root.add_child(demo)
	demo._reset_domain(1)
	demo.playing = false
	demo._update_visuals()
	for frame in 120:
		if frame == 15:
			demo.playing = true
			demo.show_flow_arrows = true
		if frame == 50:
			demo.speed_multiplier = 10
		if frame == 65:
			demo.playing = false
			demo.speed_multiplier = 1
		if frame == 72 or frame == 78 or frame == 84:
			demo._step_simulation()
		if frame == 90:
			demo.debug_view = 2
		if frame == 105:
			demo.debug_view = 0
		demo._update_visuals()
		if frame == 48:
			var image := root.get_texture().get_image()
			var path := "res://test_output/sandcastle_water_sand_coupling/验收/T02_flow_arrows_20260928.png"
			if image == null or image.is_empty() or image.save_png(path) != OK:
				printerr("FAIL: flow-arrow screenshot failed")
				quit(1)
				return
		await process_frame
	print("PASS: recorded 120 scripted debug frames; final tick=%d" % demo.domain.sim_tick)
	quit(0)

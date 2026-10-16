extends "res://tests/water_material_natural/rdc_main_smoke.gd"

func _finish() -> void:
	var passed := true
	for row in checks: passed = passed and row.pass
	var file := FileAccess.open(output.path_join("entry_checks.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass": passed, "checks": checks}, "\t"))
	file.close()
	print("ENTRY_SMOKE_COMPLETE ", passed)

func _run() -> void:
	root.size = Vector2i(1280, 720)
	for key in ["test1_capture", "test1_backwash"]:
		preview = load("res://scenes/playable/" + key + ".tscn").instantiate()
		preview.playing = false
		root.add_child(preview)
		var deadline := Time.get_ticks_msec() + 90000
		while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_msec() < deadline: await process_frame
		_check(key + "_ready", preview.ready_for_ticks and preview.last_error.is_empty(), preview.last_error)
		if preview.ready_for_ticks:
			_check(key + "_external_v1", preview.unrestricted_sand_tools and preview.shadow_domain.tool_inventory_m3 == 0.0)
			_check(key + "_configuration", preview._validate_compiled_inputs() and not preview.source_signature.is_empty())
			await _ticks(1)
			_check(key + "_tick", preview.completed_ticks == 1 and preview.last_error.is_empty())
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output.path_join(key + ".png"))
		var service := root.get_node("BeachScenes")
		_check(key + "_disposed", await service._dispose_scene(preview))
	_finish()
	var passed := true
	for row in checks: passed = passed and row.pass
	quit(0 if passed else 1)

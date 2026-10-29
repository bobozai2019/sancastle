extends "res://tests/shape_brushes/ui_probe.gd"

func _run() -> void:
	root.size=Vector2i(1280,720)
	preview=load("res://scenes/main.tscn").instantiate();preview.playing=false;root.add_child(preview)
	var deadline:=Time.get_ticks_msec()+90000
	while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	_check("formal_layout_ready",preview.ready_for_ticks,preview.last_error)
	if not preview.ready_for_ticks:_finish();quit(1);return
	preview.get_node("Interface/PerformancePanel/Margin/Rows/Header/Sampling").button_pressed=false
	for size in [Vector2i(1280,720),Vector2i(1024,768)]:
		root.size=size
		for i in 3:await process_frame
		for tool in ["Dig","Fill","Castle","Shovel","Wall"]:
			await select_tool(tool)
			await RenderingServer.frame_post_draw
			var bounds:Rect2=root.get_visible_rect()
			var brush:Rect2=preview.brush_panel.get_global_rect()
			var edit:Rect2=preview.get_node("Interface/EditPanel").get_global_rect()
			var profiler:Rect2=preview.get_node("Interface/PerformancePanel").get_global_rect()
			_check(str(size)+tool+"_three_panels_fit",bounds.encloses(brush) and bounds.encloses(edit) and bounds.encloses(profiler),{"bounds":bounds,"brush":brush,"edit":edit,"profiler":profiler})
			_check(str(size)+tool+"_panels_disjoint",not brush.intersects(edit) and not brush.intersects(profiler) and not edit.intersects(profiler))
		root.get_texture().get_image().save_png(output.path_join("formal_"+str(size.x)+"x"+str(size.y)+".png"))
	await preview.shutdown();preview.queue_free();await process_frame
	_finish();var passed:=true
	for row in checks:passed=passed and row.pass
	quit(0 if passed else 1)

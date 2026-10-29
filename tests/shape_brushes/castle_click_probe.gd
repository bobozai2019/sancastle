extends "res://tests/shape_brushes/ui_probe.gd"

func _run() -> void:
	root.size=Vector2i(1280,720);pair_fields=27
	preview=load("res://tests/shape_brushes/ui_lab.tscn").instantiate();preview.playing=false;root.add_child(preview)
	var deadline:=Time.get_ticks_msec()+90000
	while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	_check("click_lab_ready",preview.ready_for_ticks,preview.last_error)
	if not preview.ready_for_ticks:_finish();quit(1);return
	await select_tool("Castle")
	for pos in [Vector3.ZERO,Vector3(4,0,-2)]:
		var point:Vector2=preview.player_camera.unproject_position(pos)
		await motion(point)
		_check("castle_click_valid_surface",not preview._over_gui(point) and not preview.pick(point).is_empty())
		var event_count:int=preview.ui_brush_events.size();var source:float=preview.domain.sand_source_m3
		await motion(point);await click(point,true)
		for i in 15:await process_frame
		await motion(point+Vector2(15,0));await click(point+Vector2(15,0),false);await wait_ui()
		_check("castle_new_press_once",preview.ui_brush_events.size()==event_count+1 and preview.ui_brush_events[-1].terminal.result.get("status")==1,preview.ui_brush_events[-1] if not preview.ui_brush_events.is_empty() else preview.ui_last_failure)
		_check("castle_new_press_actual_source",preview.domain.sand_source_m3>source and preview.ui_brush_events[-1].terminal.result.external_source_delta_m3==preview.domain.sand_source_m3-source)
	_check("castle_separate_stroke_identity",preview.ui_brush_events.size()==2 and preview.ui_brush_events[0].command.stroke_id!=preview.ui_brush_events[1].command.stroke_id and preview.ui_brush_events[0].command.baseline_token!=preview.ui_brush_events[1].command.baseline_token)
	await snapshot("two_real_castles")
	await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(output.path_join("two_castles.png"))
	await preview.shutdown();preview.queue_free();await process_frame
	_finish();var passed:=true
	for row in checks:passed=passed and row.pass
	quit(0 if passed else 1)

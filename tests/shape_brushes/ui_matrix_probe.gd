extends "res://tests/shape_brushes/ui_probe.gd"

func _run() -> void:
	root.size=Vector2i(1280,720);pair_fields=27
	preview=load("res://tests/shape_brushes/ui_matrix_lab.tscn").instantiate();preview.playing=false;root.add_child(preview)
	var deadline:=Time.get_ticks_msec()+90000
	while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	_check("matrix_ready",preview.ready_for_ticks,preview.last_error)
	if not preview.ready_for_ticks:_finish();quit(1);return
	await select_tool("Castle")
	var spin:SpinBox=preview.brush_panel.get_node("Margin/Controls/CastleParams/CastleHeight")
	var line:LineEdit=spin.get_line_edit();var old_text:=line.text
	await motion(line.get_global_rect().get_center());await click(line.get_global_rect().get_center(),true);await click(line.get_global_rect().get_center(),false)
	_check("numeric_mouse_focus",root.gui_get_focus_owner()==line)
	var camera_transform:Transform3D=preview.player_camera.transform;var yaw:float=preview.brush_panel.parameters().yaw_rad
	for code in [KEY_W,KEY_A,KEY_S,KEY_D,KEY_Q,KEY_E,KEY_BRACKETLEFT,KEY_BRACKETRIGHT]:await key(code)
	_check("numeric_focus_camera_isolated",preview.player_camera.transform==camera_transform)
	_check("numeric_focus_yaw_isolated",preview.brush_panel.parameters().yaw_rad==yaw)
	line.text=old_text;await key(KEY_ENTER);root.gui_release_focus()
	await select_tool("Wall")
	var a:Vector2=preview.player_camera.unproject_position(Vector3(-4,0,0));var b:Vector2=preview.player_camera.unproject_position(Vector3(-4,0,1))
	preview.hold_shape_receipt=true
	preview.collision_proxy.hold_data=true
	await motion(a);await click(a,true);await motion(b)
	deadline=Time.get_ticks_msec()+30000
	while preview.held_shape_receipts.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	_check("switch_real_inflight",preview.held_shape_receipts.size()==1 and preview.ui_pump_running)
	var c:Vector2=preview.player_camera.unproject_position(Vector3(-3.5,0,1))
	await motion(c);await click(c,false)
	_check("released_inflight_tail",preview.stroke_controller.state==&"draining" and preview.stroke_controller.buffer_points()>0)
	await select_tool("Castle");_check("switch_inflight_cancels_tail",not preview.ui_pressed and preview.stroke_controller.buffer_points()==0)
	preview.release_shape_receipts()
	deadline=Time.get_ticks_msec()+30000
	while preview.collision_proxy.held_data.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	await physics_frame;await physics_frame
	await select_tool("Wall");await motion(b)
	var lag_hit:Dictionary=preview.pick(b)
	_check("real_collision_lag",not preview.collision_proxy.held_data.is_empty() and not lag_hit.is_empty() and not preview._pick_current(lag_hit))
	_check("operation_waits_collision",preview.ui_pump_running and preview.ui_brush_events.is_empty())
	var lag_before:=await snapshot("collision_lag_before")
	await click(b,true);await click(b,false)
	_check("collision_lag_blocks_input",preview.ui_brush_events.is_empty() and exact(lag_before,await snapshot("collision_lag_after")))
	preview.collision_proxy.release_data()
	deadline=Time.get_ticks_msec()+30000
	while not preview._pick_current(preview.pick(b)) and Time.get_ticks_msec()<deadline:await process_frame
	await physics_frame;await physics_frame
	var fresh:Dictionary=preview.pick(b)
	_check("collision_catches_up",not fresh.is_empty() and preview._pick_current(fresh) and fresh.position.y>0.05,fresh.get("position"))
	await wait_ui()
	_check("switch_inflight_settles_once",preview.ui_tool==&"wall_v1" and preview.ui_brush_events.size()==1 and preview.ui_brush_events[0].command.brush_id==&"wall_v1" and preview.ui_brush_events[0].terminal.result.status==1)
	await select_tool("Shovel")
	a=preview.player_camera.unproject_position(Vector3(3,0,0));b=preview.player_camera.unproject_position(Vector3(3,0,0.25))
	var gap:=Vector2(640,-2000);var events:int=preview.ui_brush_events.size()
	_check("no_hit_test_gap",preview.pick(gap).is_empty())
	if not preview.pick(gap).is_empty():await preview.shutdown();_finish();quit(1);return
	await motion(a);await click(a,true);await motion(gap);await motion(b);await click(b,false);await wait_ui()
	_check("no_hit_reanchor_no_bridge",preview.ui_brush_events.size()==events)
	await select_tool("Wall")
	a=preview.player_camera.unproject_position(Vector3(4,0,-2));b=preview.player_camera.unproject_position(Vector3(4,0,-1.5))
	await motion(a);await click(a,true);await motion(b);preview.playing=true;await key(KEY_SPACE)
	await wait_ui();_check("pause_key_drains_stroke",not preview.ui_pressed and preview.shape_stroke_id==0)
	preview.playing=false
	while preview.tick_pending or preview.busy:await process_frame
	await key(KEY_SPACE);_check("resume_key_operates",preview.playing)
	preview.playing=false
	while preview.tick_pending or preview.busy:await process_frame
	await preview.shutdown();preview.queue_free();await process_frame
	_finish();var passed:=true
	for row in checks:passed=passed and row.pass
	quit(0 if passed else 1)

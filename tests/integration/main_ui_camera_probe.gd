extends SceneTree
var preview
var output := ""
var checks := []
func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=")
	call_deferred("_run")
func check(name: String, ok: bool) -> void:
	checks.append({"name":name,"pass":ok});print("UI_CAMERA_CHECK ",name," ",ok)
func _run() -> void:
	root.size=Vector2i(1280,720)
	preview=load("res://scenes/main.tscn").instantiate();preview.playing=false;root.add_child(preview)
	while not preview.ready_for_ticks and preview.last_error.is_empty(): await process_frame
	if not preview.last_error.is_empty(): printerr(preview.last_error);quit(1);return
	for i in 2:
		var tick: int=preview.completed_ticks;preview._start_tick()
		while preview.completed_ticks==tick: await process_frame
	while preview.collision_proxy.staging_texture.is_valid() or not preview.collision_proxy.pending_revisions.is_empty(): await process_frame
	await physics_frame;await physics_frame
	var camera: Camera3D=preview.player_camera
	check("free_camera_default",camera.current)
	var dig: SpinBox=preview.get_node("Interface/EditPanel/Margin/Controls/DigAmount")
	var fill: SpinBox=preview.get_node("Interface/EditPanel/Margin/Controls/FillAmount")
	dig.value=0.025;fill.value=0.01
	check("independent_ui_values",is_equal_approx(preview.dig_amount_m3,0.025) and is_equal_approx(preview.fill_amount_m3,0.01))
	check("drag_quantity_scales",is_equal_approx(preview._brush_amount(&"remove_sand",0.75),0.025) and is_equal_approx(preview._brush_amount(&"place_sand",0.75),0.01))
	# Exercise actual projected collision picking through the input controller.
	var screen:=Vector2.ZERO
	var hit: Dictionary={}
	for y in range(300,650,40):
		for x in range(200,900,40):
			var candidate: Dictionary=preview.pick(Vector2(x,y))
			if not candidate.is_empty() and preview._pick_current(candidate): screen=Vector2(x,y);hit=candidate;break
		if not hit.is_empty(): break
	check("free_camera_pick",not hit.is_empty() and preview._pick_current(hit))
	for tool in [&"remove_sand",&"place_sand"]:
		preview.get_node("Interface/EditPanel/Margin/Controls/Tools/"+("DigTool" if tool==&"remove_sand" else "FillTool")).pressed.emit()
		var button: int=MOUSE_BUTTON_LEFT
		var n: int=preview.input_events.size()
		var event:=InputEventMouseButton.new();event.position=screen;event.button_index=button;event.pressed=true
		preview._unhandled_input(event)
		while preview.input_running: await process_frame
		event.pressed=false;preview._input(event)
		var requested: float=0.025 if tool==&"remove_sand" else 0.01
		check("gpu_command_volume_"+String(tool),preview.input_events.size()==n+1 and is_equal_approx(preview.input_events[-1].command.amount_m3,requested) and preview.input_results[-1].result.status==1)
	check("stock_updates_while_paused", "0.015" in preview.get_node("Interface/EditPanel/Margin/Controls/Stock").text)
	root.gui_release_focus()
	var start_position: Vector3=camera.position
	var move:=InputEventKey.new();move.keycode=KEY_W;move.physical_keycode=KEY_W;move.pressed=true;Input.parse_input_event(move.duplicate())
	await process_frame;await process_frame
	move.pressed=false;Input.parse_input_event(move.duplicate())
	check("wasd_without_mouse_button",not camera.look_active and camera.position.distance_to(start_position)>0.001)
	dig.get_line_edit().grab_focus();start_position=camera.position
	move.pressed=true;Input.parse_input_event(move.duplicate());await process_frame;await process_frame
	move.pressed=false;Input.parse_input_event(move.duplicate())
	check("numeric_focus_blocks_camera_move",camera.position==start_position)
	root.gui_release_focus()
	var before: int=preview.input_events.size()
	var gui_click:=InputEventMouseButton.new();gui_click.position=preview.get_node("Interface/EditPanel").get_global_rect().position+Vector2(10,10);gui_click.button_index=MOUSE_BUTTON_LEFT;gui_click.pressed=true
	Input.parse_input_event(gui_click);await process_frame
	gui_click.pressed=false;Input.parse_input_event(gui_click);await process_frame
	check("ui_click_does_not_edit",preview.input_events.size()==before)
	preview.gpu_brush=&"remove_sand"
	var middle:=InputEventMouseButton.new();middle.button_index=MOUSE_BUTTON_RIGHT;middle.pressed=true
	camera._unhandled_input(middle)
	var turn:=InputEventMouseMotion.new();turn.relative=Vector2(20,10)
	var prior: Vector3=camera.rotation;camera._input(turn)
	var initial_position: Vector3=camera.position
	var key:=InputEventKey.new();key.keycode=KEY_W;key.physical_keycode=KEY_W;key.pressed=true;Input.parse_input_event(key)
	await process_frame;await process_frame
	key.pressed=false;Input.parse_input_event(key)
	check("free_camera_moves",camera.position.distance_to(initial_position)>0.001)
	var click:=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_LEFT;click.pressed=true;click.position=screen
	preview._unhandled_input(click)
	check("camera_turn_no_brush",camera.look_active and camera.rotation!=prior and preview.gpu_brush.is_empty() and preview.input_events.size()==before)
	middle.pressed=false;camera._input(middle)
	check("mouse_released",not camera.look_active and Input.mouse_mode==Input.MOUSE_MODE_VISIBLE)
	preview.gpu_brush=&"remove_sand";click.pressed=false;preview._input(click)
	check("release_ends_world_drag",preview.gpu_brush.is_empty())
	# Window-size/layout check and one visible screenshot of the current panel.
	await process_frame;await RenderingServer.frame_post_draw
	var panel: Control=preview.get_node("Interface/EditPanel")
	check("panel_fits_viewport",root.get_visible_rect().encloses(panel.get_global_rect()))
	root.get_texture().get_image().save_png(output.path_join("main_ui.png"))
	await preview.shutdown()
	var passed:=true
	for row in checks: passed=passed and row.pass
	var file:=FileAccess.open(output.path_join("result.json"),FileAccess.WRITE);file.store_string(JSON.stringify({"pass":passed,"checks":checks},"\t"))
	print("UI_CAMERA_COMPLETE ",passed);quit(0 if passed else 1)

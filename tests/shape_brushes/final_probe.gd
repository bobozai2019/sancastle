extends "res://tests/shape_brushes/soak_cost_probe.gd"

var direct_entries := []

func actual_action(tool:String,pos:Vector3) -> void:
	await select_tool(tool)
	for frame in 2:await process_frame
	var start:Vector2=preview.player_camera.unproject_position(pos)
	var end:Vector2=preview.player_camera.unproject_position(pos+Vector3(0.4,0,0))
	await motion(start);await process_frame
	var hit:Dictionary=preview.pick(start)
	var observation:Dictionary={"screen":start,"over_gui":preview._over_gui(start),"hit":hit,"ready":preview.ready_for_ticks,"camera_current":preview.player_camera.current}
	_check(preview.scene_key+"_"+tool+"_actual_pick",not observation.over_gui and not hit.is_empty() and preview._pick_current(hit),observation)
	var count:int=preview.ui_brush_events.size()
	await click(start,true)
	for frame in 15:await process_frame
	if tool!="Castle":await motion(end);await process_frame
	await click(start if tool=="Castle" else end,false);await wait_ui()
	actions.append({"tool":tool,"events":preview.ui_brush_events.slice(count),"input_observation":observation,"status":preview.ui_last_failure})

func gui_button(button:Button) -> void:
	var point:Vector2=button.get_global_rect().get_center()
	await motion(point);await click(point,true);await click(point,false)

func legacy_gui(tool:String,amount:float,pos:Vector3) -> void:
	await select_tool(tool)
	var control:SpinBox=preview.brush_panel.get_node("Margin/Controls/OrdinaryParams/"+tool+"Amount")
	control.value=amount
	preview.get_viewport().gui_release_focus()
	var old_count:int=preview.input_results.size()
	var source:float=preview.domain.sand_source_m3;var sink:float=preview.domain.sand_sink_m3
	var point:Vector2=preview.player_camera.unproject_position(pos)
	await motion(point);await click(point,true);await click(point,false)
	var deadline:=Time.get_ticks_msec()+30000
	while preview.input_running and preview.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	var result:Dictionary=preview.input_results[-1].result if preview.input_results.size()>old_count else {}
	_check(preview.scene_key+"_legacy_"+tool+"_"+str(amount),result.get("status")==1 and not preview.input_running,result)
	_check(preview.scene_key+"_legacy_account_"+tool,preview.domain.tool_inventory_m3==0.0 and (preview.domain.sand_source_m3>source and preview.domain.sand_sink_m3==sink if tool=="Fill" else preview.domain.sand_sink_m3>sink and preview.domain.sand_source_m3==source))
	direct_entries[-1].legacy.append({"tool":tool,"amount":amount,"result":result})

func drain() -> void:
	var deadline:=Time.get_ticks_msec()+30000
	while preview.busy and preview.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	_check(preview.scene_key+"_drained",not preview.busy,preview.last_error)
	await physics_frame;await physics_frame

func held_key(code:int) -> void:
	var event:=InputEventKey.new();event.keycode=code;event.physical_keycode=code;event.pressed=true
	send_input(event)
	for frame in 3:await process_frame
	event=InputEventKey.new();event.keycode=code;event.physical_keycode=code;event.pressed=false
	send_input(event);await process_frame

func camera_controls() -> void:
	var original:Transform3D=preview.player_camera.transform
	preview.get_viewport().gui_release_focus()
	for code in [KEY_W,KEY_A,KEY_S,KEY_D]:
		var before:Vector3=preview.player_camera.global_position
		await held_key(code)
		_check(preview.scene_key+"_camera_"+str(code),preview.player_camera.global_position.distance_to(before)>0.001)
	var control:SpinBox=preview.brush_panel.get_node("Margin/Controls/OrdinaryParams/DigAmount")
	control.get_line_edit().grab_focus()
	var before:Vector3=preview.player_camera.global_position
	await held_key(KEY_W)
	_check(preview.scene_key+"_numeric_focus_blocks_camera",preview.player_camera.global_position==before)
	preview.get_viewport().gui_release_focus()
	var point:=Vector2(850,500)
	await motion(point);await process_frame
	_check(preview.scene_key+"_right_pick_outside_gui",not preview._over_gui(point))
	await click(point,true,MOUSE_BUTTON_RIGHT)
	_check(preview.scene_key+"_right_look",preview.player_camera.look_active)
	var old_rotation:Vector3=preview.player_camera.rotation
	var move:=InputEventMouseMotion.new();move.position=point;move.relative=Vector2(20,10);move.screen_relative=move.relative;move.button_mask=MOUSE_BUTTON_MASK_RIGHT
	send_input(move);await process_frame
	_check(preview.scene_key+"_mouse_turn",preview.player_camera.rotation.distance_to(old_rotation)>0.001)
	await click(point,false,MOUSE_BUTTON_RIGHT)
	_check(preview.scene_key+"_look_release",not preview.player_camera.look_active)
	preview.player_camera.transform=original

func direct_entry(path:String) -> void:
	preview=load(path).instantiate();preview.playing=false;mount_input_scene(preview)
	var deadline:=Time.get_ticks_msec()+90000
	while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	_check(path+"_direct_ready",preview.ready_for_ticks,preview.last_error)
	if not preview.ready_for_ticks:return
	await preview.get_node("Interface/PerformancePanel").stop_sampling()
	await drain()
	direct_entries.append({"path":path,"key":preview.scene_key,"source_signature":preview.source_signature,"legacy":[],"shape":[]})
	_check(preview.scene_key+"_production_bindings",preview.enable_brush_water and preview.enable_brush_checkpoint_v4 and preview.enable_brush_native_material and preview.brush_panel.visible and preview.brush_preview!=null)
	var initial:=await snapshot(preview.scene_key+"_direct_initial")
	var centers:=find_centers(initial)
	initial.clear();readbacks.clear()
	_check(preview.scene_key+"_eligible_centers",not centers.is_empty(),centers)
	if centers.is_empty():return
	# Reframe the existing free camera to put an eligible surface in the open
	# lane between the diagnostic panel and right controls. Terrain/profile stay
	# at the direct entry's production values; this is a recorded test camera.
	if preview.scene_key!="main":
		var target:Vector3=centers[0]
		preview.player_camera.global_position=target+Vector3(-7,8,-10)
		preview.player_camera.look_at(target,Vector3.UP)
		preview.player_camera.global_position-=preview.player_camera.global_basis.x*3.5
		direct_entries[-1].test_camera_transform=str(preview.player_camera.global_transform)
		centers=[target]
		await process_frame;await physics_frame
	for tool in ["Castle","Wall","Shovel"]:
		var pos:Vector3=centers[0 if tool=="Castle" else mini(1,centers.size()-1)]
		# Let readonly query consume this scene's current revision and parameters.
		await select_tool(tool)
		var point:Vector2=preview.player_camera.unproject_position(pos)
		await motion(point)
		deadline=Time.get_ticks_msec()+10000
		while (preview.preview_request_in_flight or preview.preview_cache.is_empty()) and Time.get_ticks_msec()<deadline:await process_frame
		await actual_action(tool,pos)
		var row:Dictionary=actions[-1];var applied:=false
		for event in row.events:applied=applied or event.terminal.result.get("status")==1
		_check(preview.scene_key+"_actual_"+tool,applied,row.events)
		direct_entries[-1].shape.append(row)
		await drain()
	for amount in [0.01,0.10,1.0]:
		await legacy_gui("Fill",amount,centers[0]);await drain()
		await legacy_gui("Dig",amount,centers[0]);await drain()
	await camera_controls()
	var before_wave:int=preview.wave_highwater_id
	await gui_button(preview.get_node("Interface/EditPanel/Margin/Controls/TriggerWave"))
	_check(preview.scene_key+"_wave_gui_admitted",preview.wave_highwater_id==before_wave+1)
	var tick:int=preview.completed_ticks
	preview.get_viewport().gui_release_focus();await key(KEY_SPACE)
	_check(preview.scene_key+"_resume_key",preview.playing)
	deadline=Time.get_ticks_msec()+10000
	while preview.completed_ticks<tick+3 and preview.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	await key(KEY_SPACE);await drain()
	_check(preview.scene_key+"_pause_key_and_ticks",not preview.playing and preview.completed_ticks>=tick+3)
	var anchor:=await snapshot(preview.scene_key+"_final_anchor")
	var selection:Dictionary=preview._capture_brush_selection()
	var save_path:=output.path_join(preview.scene_key+"_final.scp")
	var error:StringName=await preview.save_gpu_checkpoint(save_path)
	_check(preview.scene_key+"_final_save",error.is_empty(),String(error))
	if error.is_empty():
		error=await preview.restore_gpu_checkpoint(save_path)
		_check(preview.scene_key+"_final_restore",error.is_empty(),String(error))
		_check(preview.scene_key+"_final_raw27",exact(anchor,await snapshot(preview.scene_key+"_final_restored")))
		_check(preview.scene_key+"_final_selection",preview._capture_brush_selection()==selection)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(preview.scene_key+"_direct.png"))
	await preview.get_node("Interface/PerformancePanel").stop_sampling()
	await preview.shutdown();_check(preview.scene_key+"_direct_release",preview.gpu_release_done and preview.preview_query==null)
	preview.queue_free();await process_frame;await process_frame

func _run() -> void:
	root.size=Vector2i(1280,720);pair_fields=27
	for path in ["res://scenes/main.tscn","res://scenes/playable/test1_capture.tscn","res://scenes/playable/test1_backwash.tscn"]:
		await direct_entry(path)
	var file:=FileAccess.open(output.path_join("direct_entries.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"entries":direct_entries,"raw_index":raw_index,"scope":"Direct production entry functional regression; no cost measurement or long strict continuation"},"\t"));file.close()
	_finish();var passed:=true
	for row in checks:passed=passed and row.pass
	quit(0 if passed else 1)

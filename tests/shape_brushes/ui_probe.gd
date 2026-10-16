extends "res://tests/shape_brushes/material_edit_probe.gd"

var retained_ui_preview_query
var input_harness:Node
var input_viewport:SubViewport

func mount_input_scene(scene:Node) -> void:
	if input_harness==null:
		input_harness=load("res://tests/experiments/approx_gpu_edit/input_harness.tscn").instantiate()
		root.add_child(input_harness);input_viewport=input_harness.get_node("InputViewport")
		process_frame.connect(_sync_input_viewport)
	_sync_input_viewport();input_viewport.add_child(scene)

func _sync_input_viewport() -> void:
	if input_viewport!=null:
		input_viewport.size=Vector2i(root.get_visible_rect().size)
		input_harness.get_node("Display").size=root.get_visible_rect().size

func send_input(event:InputEvent) -> void:
	Input.parse_input_event(event);Input.flush_buffered_events()
	if input_viewport!=null:input_viewport.push_input(event,true)

func retain_ui_candidate() -> void:retained_ui_preview_query=preview._restore_preview_query

func key(code:int) -> void:
	var event:=InputEventKey.new();event.keycode=code;event.physical_keycode=code;event.pressed=true;send_input(event);await process_frame
	event=InputEventKey.new();event.keycode=code;event.physical_keycode=code;event.pressed=false;send_input(event);await process_frame

func motion(point:Vector2) -> void:
	var pixel:=point if input_viewport!=null else root.get_stretch_transform()*point
	var event:=InputEventMouseMotion.new();event.position=pixel;event.global_position=pixel;send_input(event);await process_frame

func click(point:Vector2,pressed:bool,button:int=MOUSE_BUTTON_LEFT) -> void:
	var pixel:=point if input_viewport!=null else root.get_stretch_transform()*point
	var event:=InputEventMouseButton.new();event.position=pixel;event.global_position=pixel;event.button_index=button;event.pressed=pressed;send_input(event);await process_frame

func select_tool(name:String) -> void:
	var button:Button=preview.brush_panel.get_node("Margin/Controls/Tools/"+name)
	await motion(button.get_global_rect().get_center());await click(button.get_global_rect().get_center(),true);await click(button.get_global_rect().get_center(),false)

func wait_ui() -> void:
	var deadline:=Time.get_ticks_msec()+30000
	while preview.ui_pump_running and preview.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	_check("ui_stroke_drained",not preview.ui_pump_running and preview.shape_stroke_id==0,preview.last_error)

func _run() -> void:
	root.size=Vector2i(1280,720);pair_fields=27
	preview=load("res://tests/shape_brushes/ui_lab.tscn").instantiate();mount_input_scene(preview)
	var deadline:=Time.get_ticks_msec()+90000
	while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	_check("ui_ready",preview.ready_for_ticks,preview.last_error)
	if not preview.ready_for_ticks:await preview.shutdown();_finish();quit(1);return
	var panel=preview.brush_panel
	_check("static_five_tools",panel.find_child("Tools",true,false).get_child_count()==5)
	_check("candidate_panel_no_overlap",not preview.get_node("Interface/PerformancePanel").visible)
	for name in ["Dig","Fill","Castle","Shovel","Wall"]:
		_check("static_signal_"+name,panel.get_node("Margin/Controls/Tools/"+name).get_signal_connection_list("pressed").size()==1)
	var initial:=await snapshot("ui_initial")
	var button:Button=panel.get_node("Margin/Controls/Tools/Castle")
	await motion(button.get_global_rect().get_center());await click(button.get_global_rect().get_center(),true);await click(button.get_global_rect().get_center(),false)
	_check("gui_select_castle",preview.ui_tool==&"castle_v1" and panel.selected_tool==&"castle_v1")
	var point:Vector2=preview.player_camera.unproject_position(Vector3.ZERO)
	await motion(point)
	deadline=Time.get_ticks_msec()+30000
	while (preview.preview_cache.is_empty() or preview.preview_request_in_flight) and Time.get_ticks_msec()<deadline:await process_frame
	_check("castle_readonly_base",not preview.preview_cache.is_empty() and preview.preview_cache.flags==0 and preview.preview_cache.base==0.0)
	var before:=await snapshot("ui_before_castle")
	_check("preview_reads_do_not_edit",exact(initial,before))
	var texture:Texture2D=preview.brush_preview.castle.material_override.get_shader_parameter("template_texture")
	_check("preview_same_template_bytes",texture.get_image().get_data()==FileAccess.get_file_as_bytes("res://assets/brushes/castle/four_towers_v1.rgba32f"))
	await key(KEY_BRACKETRIGHT);await motion(point)
	_check("castle_rotation_key",is_equal_approx(panel.parameters().yaw_rad,PI/12) and is_equal_approx(preview.brush_preview.castle.rotation.y,-PI/12))
	await key(KEY_BRACKETLEFT)
	var size_control:SpinBox=panel.get_node("Margin/Controls/CastleParams/CastleScale")
	var arrow:=size_control.get_global_rect().position+Vector2(size_control.size.x-8,size_control.size.y*0.25)
	await motion(arrow);await click(arrow,true);await click(arrow,false);await motion(point)
	await RenderingServer.frame_post_draw
	_check("castle_size_gui_control",panel.parameters().scale_xz>1.0 and is_equal_approx(preview.brush_preview.castle.scale.x,panel.parameters().scale_xz),{"control":panel.parameters().scale_xz,"ghost":preview.brush_preview.castle.scale.x})
	arrow=size_control.get_global_rect().position+Vector2(size_control.size.x-8,size_control.size.y*0.75)
	await motion(arrow);await click(arrow,true);await click(arrow,false);await motion(point)
	_check("castle_size_gui_reset",panel.parameters().scale_xz==1.0)
	var save_path:=output.path_join("ui_before_shape.scp")
	var saved:StringName=await preview.save_gpu_checkpoint(save_path);_check("ui_legacy_native_save",saved.is_empty(),String(saved))
	var active_query=preview.preview_query
	preview.inject_beach_restore_failure=true;preview.observe_beach_restore=true;preview.beach_restore_submitted.connect(retain_ui_candidate,CONNECT_ONE_SHOT)
	var restore_error:StringName=await preview.restore_gpu_checkpoint(save_path);preview.observe_beach_restore=false
	_check("ui_preview_candidate_failure",restore_error==&"candidate_injected_failure" and preview.preview_query==active_query and retained_ui_preview_query!=null and retained_ui_preview_query.rd==null and retained_ui_preview_query.owned.is_empty(),String(restore_error))
	_check("ui_preview_failed_restore_atomic",exact(before,await snapshot("ui_failed_restore")))
	restore_error=await preview.restore_gpu_checkpoint(save_path)
	_check("ui_preview_restore_swap",restore_error.is_empty() and preview.preview_query!=active_query and active_query.rd==null and preview.preview_query.initialized,String(restore_error))
	_check("ui_preview_restore_raw_exact",exact(before,await snapshot("ui_restored")))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("castle_preview.png"))
	await click(point,true)
	for i in 30:await process_frame
	await motion(point+Vector2(30,0));await click(point+Vector2(30,0),false);await wait_ui()
	var after:=await snapshot("ui_after_castle")
	_check("actual_mouse_castle_once",preview.ui_brush_events.size()==1 and preview.ui_brush_events[0].terminal.result.get("status")==1 and before.sand!=after.sand,preview.ui_brush_events.duplicate(true))
	_check("ui_castle_material",preview.solver.mold_field_ever_used and after.sand==after.published_sand)
	button=panel.get_node("Margin/Controls/Tools/Wall")
	await motion(button.get_global_rect().get_center());await click(button.get_global_rect().get_center(),true);await click(button.get_global_rect().get_center(),false)
	_check("gui_select_wall",preview.ui_tool==&"wall_v1")
	var a:Vector2=preview.player_camera.unproject_position(Vector3(-3,0,0));var b:Vector2=preview.player_camera.unproject_position(Vector3(-3,0,1))
	await motion(a);await click(a,true);await motion(a.lerp(b,0.5));await motion(b);await click(b,false);await wait_ui()
	_check("actual_mouse_wall",preview.ui_brush_events.size()>1 and preview.ui_brush_events[-1].command.brush_id==&"wall_v1" and preview.ui_brush_events[-1].terminal.result.get("status")==1,preview.ui_last_failure)
	await motion(b);await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("ui_tools.png"))
	await select_tool("Shovel");_check("gui_select_shovel",preview.ui_tool==&"shovel_v1")
	var ledger_before:=metadata();var event_count:int=preview.ui_brush_events.size()
	a=preview.player_camera.unproject_position(Vector3(3,0,0));b=preview.player_camera.unproject_position(Vector3(3,0,0.5))
	await motion(a);await click(a,true);await motion(b)
	await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(output.path_join("shovel_drag_preview.png"))
	deadline=Time.get_ticks_msec()+30000
	while (preview.busy or preview.stroke_controller.buffer_points()>0 or preview.stroke_controller.outstanding>0) and Time.get_ticks_msec()<deadline:await process_frame
	for i in 3:await process_frame
	await RenderingServer.frame_post_draw
	var footprint:ShaderMaterial=preview.brush_preview.footprint.material_override
	var tint:Color=footprint.get_shader_parameter("tint")
	_check("shovel_directional_preview_ready",preview.brush_preview.footprint.visible and footprint.get_shader_parameter("start_xz")!=footprint.get_shader_parameter("end_xz") and tint.g>tint.r)
	root.get_texture().get_image().save_png(output.path_join("shovel_drag_ready.png"))
	await click(b,false);await wait_ui()
	_check("actual_mouse_shovel",preview.ui_brush_events.size()>event_count and preview.ui_brush_events[-1].command.brush_id==&"shovel_v1" and preview.ui_brush_events[-1].terminal.result.get("status")==1,preview.ui_last_failure)
	_check("ui_shovel_ledger",preview.domain.sand_source_m3==ledger_before.source and preview.domain.sand_sink_m3==ledger_before.sink and preview.domain.tool_inventory_m3==ledger_before.inventory)
	await motion(b);await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(output.path_join("shovel_preview.png"))
	var idle:=await snapshot("ui_idle_before_negatives");event_count=preview.ui_brush_events.size()
	await motion(a);await click(a,true)
	for i in 15:await process_frame
	await motion(panel.get_global_rect().get_center());await click(panel.get_global_rect().get_center(),false);await wait_ui()
	_check("stationary_gui_release_no_edit",preview.ui_brush_events.size()==event_count and exact(idle,await snapshot("ui_gui_release")))
	await motion(a);await click(a,true);await key(KEY_ESCAPE);await wait_ui()
	_check("escape_no_ghost_stroke",not preview.ui_pressed and preview.ui_brush_events.size()==event_count)
	await motion(a);await click(a,true);await click(a,true,MOUSE_BUTTON_RIGHT);await click(a,false,MOUSE_BUTTON_RIGHT);await click(a,false);await wait_ui()
	_check("right_camera_no_edit",not preview.player_camera.look_active and preview.ui_brush_events.size()==event_count and exact(idle,await snapshot("ui_right_camera")))
	await motion(a);await click(a,true);preview.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT);await click(a,false);await wait_ui()
	_check("focus_out_cancels",not preview.ui_pressed and preview.ui_brush_events.size()==event_count)
	await select_tool("Wall");var rejected_before:=await snapshot("ui_before_rejected_edit")
	preview.shape_gpu.inject_candidate_failure_once=true
	a=preview.player_camera.unproject_position(Vector3(4,0,2));b=preview.player_camera.unproject_position(Vector3(4,0,2.5))
	await motion(a);await click(a,true);await motion(b);await click(b,false);await wait_ui()
	_check("ui_rejected_edit_atomic",preview.ui_brush_events[-1].terminal.result.get("status")==3 and exact(rejected_before,await snapshot("ui_after_rejected_edit")))
	await process_frame
	_check("ui_failure_visible",not preview.ui_last_failure.is_empty() and panel.get_node("Margin/Controls/BrushStatus").text==preview.ui_last_failure and not preview.ui_last_failure.contains("16"),preview.ui_last_failure)
	await select_tool("Fill");var source_before:float=preview.domain.sand_source_m3
	a=preview.player_camera.unproject_position(Vector3(4,0,-2));await motion(a);await click(a,true);await click(a,false);await settle()
	_check("gui_legacy_fill",preview.domain.sand_source_m3>source_before)
	await select_tool("Dig");var sink_before:float=preview.domain.sand_sink_m3
	await motion(a);await click(a,true);await click(a,false);await settle()
	_check("gui_legacy_dig",preview.domain.sand_sink_m3>sink_before)
	root.size=Vector2i(1024,768)
	for i in 3:await process_frame
	await select_tool("Castle")
	_check("resized_tool_panel",panel.get_global_rect().end.x<=root.get_visible_rect().size.x and panel.get_global_rect().end.y<=root.get_visible_rect().size.y and preview.ui_tool==&"castle_v1",{"viewport":root.get_visible_rect().size,"window":root.size,"tool":preview.ui_tool})
	await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(output.path_join("ui_1024x768.png"))
	panel.get_node("Margin/Controls/CastleParams/CastleScale").value=1.2
	panel.get_node("Margin/Controls/CastleParams/CastleHeight").value=0.9
	panel.get_node("Margin/Controls/CastleParams/CastleYaw").value=45.0
	panel.get_node("Margin/Controls/OrdinaryParams/DigAmount").value=0.2
	panel.get_node("Margin/Controls/OrdinaryParams/FillAmount").value=0.3
	var selection:Dictionary=preview._capture_brush_selection();var mixed_anchor:=await snapshot("ui_v4_mixed_anchor")
	var mixed_path:=output.path_join("ui_mixed_v4.scp")
	saved=await preview.save_gpu_checkpoint(mixed_path);_check("ui_v4_after_shapes_save",saved.is_empty(),String(saved))
	var loaded_mixed:Dictionary=preview.Store.load(mixed_path)
	_check("ui_v4_complete_mixed_header",loaded_mixed.error.is_empty() and loaded_mixed.checkpoint.gpu_beach_edit.version==4 and loaded_mixed.checkpoint.gpu_beach_native.version==2 and loaded_mixed.checkpoint.gpu_beach_edit.selection.brush==selection)
	await select_tool("Shovel")
	panel.get_node("Margin/Controls/CastleParams/CastleHeight").value=0.5
	restore_error=await preview.restore_gpu_checkpoint(mixed_path)
	_check("ui_v4_selection_restored",restore_error.is_empty() and preview.ui_tool==&"castle_v1" and panel.selected_tool==&"castle_v1" and preview._capture_brush_selection()==selection,String(restore_error))
	_check("ui_v4_mixed_27_raw_exact",exact(mixed_anchor,await snapshot("ui_v4_mixed_restored")))
	var request_path:=output.path_join("ui_request_v4.scp")
	var request_error:StringName=preview.request_checkpoint_save(request_path)
	while preview.brush_save_request_pending or preview.gpu_save_running:await process_frame
	_check("ui_v4_request_save_entry",request_error.is_empty() and preview.last_save_error.is_empty() and FileAccess.file_exists(request_path),String(preview.last_save_error))
	var query=preview.preview_query
	var file:=FileAccess.open(output.path_join("ui_evidence.json"),FileAccess.WRITE);file.store_string(JSON.stringify({"events":preview.ui_brush_events,"raw_index":raw_index,"preview_queries":query.query_count,"source_signature":preview.source_signature,"effective_compilation":preview.effective_compilation,"input":"Input state plus controlled visible SubViewport local events through GUI/unhandled/physics ray; no direct submit; native focus not covered"},"\t"));file.close()
	await preview.shutdown();_check("ui_preview_release",query.rd==null and query.owned.is_empty() and preview.gpu_release_done)
	_finish();var passed:=true
	for row in checks:passed=passed and row.pass
	quit(0 if passed else 1)

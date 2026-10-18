extends "res://tests/integration/unified_edit_playable_probe.gd"

func _run() -> void:
	orphan_baseline=int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	DisplayServer.window_set_size(Vector2i(1280,720))
	scene=load("res://scenes/unified_edit/playable/main.tscn").instantiate();scene.playing=false;scene.generation=1001;root.add_child(scene)
	var start:=Time.get_ticks_msec()
	while not scene.ready_for_ticks and scene.last_error.is_empty() and Time.get_ticks_msec()-start<90000:await process_frame
	check("pointer_entry_ready",scene.ready_for_ticks and scene.last_error.is_empty())
	if not scene.ready_for_ticks:await _close();return
	observations.sources=scene.configuration.sources.duplicate(true)
	scene.panel.get_node("Margin/Controls/Tools/Fill").pressed.emit()
	scene.hide_hud=true
	await process_frame;await process_frame
	var position:=Vector2(640,360)
	check("real_camera_hits_active_height_surface",not scene.pick(position).is_empty())
	_motion(position);_button(position,true)
	await process_frame;await process_frame
	check("viewport_press_declares_fill",scene.runtime.highwater()>0 and scene.gpu_brush==&"place_sand" and not scene.input.gesture.is_empty())
	_button(position,false);await _idle()
	check("viewport_release_ends_fill",scene.gpu_brush.is_empty() and scene.input.gesture.is_empty())
	var applied:=false
	for row in scene.input.terminal:applied=applied or row.outcome==L.Outcome.APPLIED
	check("viewport_fill_actual_gpu_application",applied)
	scene.panel.get_node("Margin/Controls/Tools/Wall").pressed.emit()
	_button(position,true);await process_frame
	_motion(position+Vector2(16,0),Vector2(16,0));await process_frame
	check("viewport_drag_declares_shape_samples",scene.gpu_brush==&"wall_v1" and scene.input.gesture.get("sample",0)>=2)
	# Release over a visible control: the root input observer must still close
	# the stroke even when GUI owns the eventual release event.
	scene.hide_hud=false;await process_frame;await process_frame
	_button(Vector2(50,160),false);await _idle()
	check("gui_release_closes_common_stroke",scene.gpu_brush.is_empty() and scene.input.gesture.is_empty())
	check("shape_preview_hidden_on_release",not scene.get_node("BrushPreview/Footprint").visible)
	await _key(KEY_SPACE)
	observations.first_space={"playing":scene.playing,"tick":scene.runtime.current.completed_tick}
	start=Time.get_ticks_msec()
	while scene.runtime.current.completed_tick<1 and Time.get_ticks_msec()-start<15000:await process_frame
	await _key(KEY_SPACE);await _idle()
	observations.second_space={"playing":scene.playing,"tick":scene.runtime.current.completed_tick}
	check("viewport_space_controls_clock",not scene.playing and scene.runtime.current.completed_tick>=1)
	var previous: bool=scene.use_player_camera
	await _key(KEY_F5)
	var source: Camera3D=scene.get_viewport().get_camera_3d()
	var reflection: Camera3D=scene.get_node("ReflectionViewport/ReflectionCamera")
	observations.camera={"before":previous,"after":scene.use_player_camera,"source_projection":source.projection,"reflection_projection":reflection.projection,"source_fov":source.fov,"reflection_fov":reflection.fov}
	check("viewport_f5_changes_camera_and_reflection",scene.use_player_camera!=previous and reflection.projection==source.projection and is_equal_approx(reflection.fov,source.fov))
	await _key(KEY_F5)
	observations.results=scene.input.terminal.duplicate(true)
	await RenderingServer.frame_post_draw
	check("pointer_render_saved",root.get_texture().get_image().save_png(output+"/pointer.png")==OK)
	await _close()

func _button(position: Vector2, down: bool) -> void:
	var event:=InputEventMouseButton.new();event.position=position;event.global_position=position;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down;event.button_mask=MOUSE_BUTTON_MASK_LEFT if down else 0
	Input.parse_input_event(event)

func _motion(position: Vector2, relative: Vector2=Vector2.ZERO) -> void:
	var event:=InputEventMouseMotion.new();event.position=position;event.global_position=position;event.relative=relative
	Input.parse_input_event(event)

func _key(code: Key) -> void:
	var event:=InputEventKey.new();event.keycode=code;event.pressed=true;Input.parse_input_event(event)
	await process_frame
	var release:=InputEventKey.new();release.keycode=code;release.pressed=false;Input.parse_input_event(release)
	await process_frame;await RenderingServer.frame_post_draw;await process_frame

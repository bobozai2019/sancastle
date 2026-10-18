extends "res://tests/integration/unified_edit_playable_probe.gd"

func _run() -> void:
	orphan_baseline=int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	DisplayServer.window_set_size(Vector2i(1280,720))
	scene=load("res://scenes/main.tscn").instantiate();scene.playing=false;root.add_child(scene)
	var start:=Time.get_ticks_msec()
	while (not scene.ready_for_ticks or scene._booting) and scene.last_error.is_empty() and Time.get_ticks_msec()-start<90000:await process_frame
	check("main_ready",scene.ready_for_ticks and scene.last_error.is_empty())
	if not scene.ready_for_ticks:await _close();return
	var toggle=scene.get_node("Interface/ShapeBrushPanel/Margin/Controls/ConnectedDrainage")
	scene._update_status()
	check("authored_toggle_default_on",toggle.button_pressed and not toggle.disabled and scene.water_policy==3)
	var speed: float=scene.signed_speed_m_s
	toggle.button_pressed=false
	check("toggle_selects_velocity_only",scene.water_policy==2 and scene.signed_speed_m_s==speed)
	var preview: Dictionary=scene.input.preview_request(&"fill_v1",Vector2(3,0),{},0.1,scene.water_policy,speed)
	check("preview_uses_selected_policy",preview.error.is_empty() and preview.request.features.water_policy==2 and preview.request.parameters.speed_m_s==speed)
	var params:={"trench_width_m":0.5,"depth_m":0.15,"shoulder_width_m":0.5}
	check("stroke_off_admitted",scene.input.begin(&"shovel_v1",Vector2(3,0),params,0.1,scene.water_policy,speed).accepted)
	check("stroke_freezes_off",scene.input.gesture.get("policy",-1)==2)
	toggle.button_pressed=true
	await _idle()
	check("toggle_ends_stroke",scene.input.gesture.is_empty() and scene.water_policy==3)
	var valid:=true
	for row in scene.input.terminal:valid=valid and row.outcome in [L.Outcome.APPLIED,L.Outcome.NO_CHANGE]
	check("off_stroke_completes",valid and not scene.input.terminal.is_empty())
	toggle.button_pressed=false
	var path:=output+"/drainage.sandue"
	check("save_off",(await scene.save_gpu_checkpoint(path)).is_empty())
	toggle.button_pressed=true
	check("restore_off",(await scene.restore_gpu_checkpoint(path)).is_empty())
	scene._update_status()
	check("restore_syncs_toggle",scene.water_policy==2 and not toggle.button_pressed and scene.signed_speed_m_s==speed)
	scene.panel.get_node("Margin/Controls/Tools/Shovel").pressed.emit()
	await RenderingServer.frame_post_draw;await RenderingServer.frame_post_draw
	check("ui_screenshot",root.get_texture().get_image().save_png(output+"/drainage_ui.png")==OK)
	observations.sources=scene.configuration.sources.duplicate(true)
	await _close()

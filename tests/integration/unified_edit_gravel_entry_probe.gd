extends "res://tests/integration/unified_edit_pointer_probe.gd"

func _run() -> void:
	orphan_baseline=int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	DisplayServer.window_set_size(Vector2i(1280,720))
	scene=load(_entry_path(scene_key)).instantiate();scene.playing=false;scene.generation=1001;root.add_child(scene)
	var start:=Time.get_ticks_msec()
	while not scene.ready_for_ticks and scene.last_error.is_empty() and Time.get_ticks_msec()-start<_ready_timeout_ms():await process_frame
	check("gravel_entry_ready",scene.ready_for_ticks and scene.last_error.is_empty())
	if not scene.ready_for_ticks:await _close();return
	observations.sources=scene.configuration.sources.duplicate(true)
	var initial: int=scene.runtime.current.visuals.active_count
	scene.panel.get_node("Margin/Controls/Tools/GravelDrop").pressed.emit()
	scene.panel.get_node("Margin/Controls/GravelParams/GravelCount").value=17
	check("gravel_tool_connected",scene.selected_sand_tool==&"gravel_drop" and scene.panel.parameters().count==17)
	check("gravel_declaration",scene.input.begin(scene.selected_sand_tool,Vector2(3,0),scene.panel.parameters(),0.1,3,0.25).accepted)
	check("renderer_does_not_predict_admission",scene.get_node("GravelLayer").multimesh.visible_instance_count==initial)
	scene.input.finish();await _idle()
	check("renderer_uses_actual_receipt_count",scene.runtime.current.visuals.active_count==initial+17 and scene.get_node("GravelLayer").multimesh.visible_instance_count==initial+17 and scene.get_node("GravelLayer").visible)
	var path:=output+"/gravel.sandue"
	check("gravel_native_save",(await scene.save_gpu_checkpoint(path)).is_empty());await process_frame
	check("second_gravel_declaration",scene.input.begin(&"gravel_drop",Vector2(4,0),{"count":31},0.1,3,0.25).accepted);scene.input.finish();await _idle()
	check("population_grows",scene.runtime.current.visuals.active_count==initial+48)
	check("gravel_native_restore",(await scene.restore_gpu_checkpoint(path)).is_empty())
	start=Time.get_ticks_msec()
	while not scene.runtime.retired.is_empty() and Time.get_ticks_msec()-start<30000:await process_frame
	await process_frame
	check("restore_rebinds_renderer_population",scene.generation==1002 and scene.runtime.current.visuals.active_count==initial+17 and scene.get_node("GravelLayer").multimesh.visible_instance_count==initial+17)
	scene.runtime.current.transport.inject_upload_failure_once=true
	check("failure_gravel_admitted",scene.input.begin(&"gravel_drop",Vector2(2,1),{"count":7},0.1,3,0.25).accepted);scene.input.finish()
	start=Time.get_ticks_msec()
	while scene.last_error.is_empty() and Time.get_ticks_msec()-start<10000:await process_frame
	check("lifecycle_result_does_not_break_frontend",not scene.last_error.is_empty() and scene.runtime.current.visuals.active_count==initial+17)
	check("native_recovers_failed_current_domain",(await scene.restore_gpu_checkpoint(path)).is_empty())
	start=Time.get_ticks_msec()
	while not scene.runtime.retired.is_empty() and Time.get_ticks_msec()-start<30000:await process_frame
	await process_frame;await process_frame
	check("recovered_entry_ready",scene.ready_for_ticks and scene.last_error.is_empty() and scene.generation==1003 and scene.get_node("GravelLayer").multimesh.visible_instance_count==initial+17)
	if scene_key=="main":
		scene.hide_hud=true;await process_frame;await process_frame
		var position:=Vector2(640,360)
		check("pointer_hits_gravel_drop_surface",not scene.pick(position).is_empty())
		_motion(position);_button(position,true);await process_frame;await process_frame;_button(position,false);await _idle()
		check("actual_pointer_spawns_gravel",scene.runtime.current.visuals.active_count==initial+34 and scene.get_node("GravelLayer").multimesh.visible_instance_count==initial+34)
	observations.initial_count=initial;observations.final_count=scene.runtime.current.visuals.active_count;observations.results=scene.input.terminal.duplicate(true)
	observations.events=scene.runtime.events.duplicate(true)
	await RenderingServer.frame_post_draw
	check("gravel_entry_render",root.get_texture().get_image().save_png(output+"/gravel.png")==OK)
	await _close()

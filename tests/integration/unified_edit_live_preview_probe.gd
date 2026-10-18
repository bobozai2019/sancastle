extends "res://tests/integration/unified_edit_pointer_probe.gd"

func _run() -> void:
	orphan_baseline=int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	DisplayServer.window_set_size(Vector2i(1280,720))
	scene=load(_entry_path(scene_key)).instantiate();scene.playing=false;scene.generation=1001;root.add_child(scene)
	var start:=Time.get_ticks_msec()
	while not scene.ready_for_ticks and scene.last_error.is_empty() and Time.get_ticks_msec()-start<_ready_timeout_ms():await process_frame
	check("preview_entry_ready",scene.ready_for_ticks and scene.last_error.is_empty())
	if not scene.ready_for_ticks:await _close();return
	observations.sources=scene.configuration.sources.duplicate(true)
	scene.panel.get_node("Margin/Controls/Tools/Castle").pressed.emit()
	scene.preview_at(Vector2(3,0));scene.playing=true
	await _received_count(3)
	check("playing_water_does_not_starve_preview",scene.preview_received_count>=3 and scene.runtime.current.completed_tick>0 and scene.preview_result.get("freshness")==1)
	check("castle_snapshot_displayed",scene.get_node("BrushPreview/CastleGhost").visible and scene.preview_result.generation==scene.generation and scene.preview_result.advisory)
	observations.playing=_small_result(scene.preview_result)
	scene.playing=false;await _idle()
	var time: float=scene.runtime.current.advanced_time_s
	var count: int=scene.preview_received_count
	await _received_count(count+2)
	check("paused_queries_do_not_advance_clock",scene.runtime.current.advanced_time_s==time and scene.preview_received_count>=count+2)
	var owner=scene.runtime.current
	owner.views.hold_delivery=true
	while owner.views.held.is_empty() and Time.get_ticks_msec()-start<90000:await process_frame
	check("old_tool_query_actually_held",not owner.views.held.is_empty())
	scene.panel.get_node("Margin/Controls/Tools/Wall").pressed.emit()
	owner.views.deliver_held();await process_frame;await process_frame
	check("changed_tool_hides_old_preview",scene.preview_result.is_empty() and not scene.get_node("BrushPreview/CastleGhost").visible)
	var params: Dictionary=scene.panel.parameters()
	check("active_wall_begin",scene.input.begin(&"wall_v1",Vector2(3,2),params,0.1,3,0.25).accepted)
	scene.preview_at(Vector2(3.5,2));count=scene.preview_received_count
	await _received_count(count+1)
	check("actual_stroke_baseline_preview",scene.preview_result.get("uses_baseline",false) and scene.get_node("BrushPreview/Footprint").material_override.get_shader_parameter("use_stroke_baseline")==true)
	observations.baseline=_small_result(scene.preview_result)
	scene._finish_ui_stroke(false);await _idle()
	check("finish_hides_stroke_preview",not scene.get_node("BrushPreview/Footprint").visible)
	var path:=output+"/preview.sandue"
	check("preview_native_save",(await scene.save_gpu_checkpoint(path)).is_empty());await process_frame
	scene.panel.get_node("Margin/Controls/Tools/Castle").pressed.emit();owner.views.hold_delivery=true;scene.preview_at(Vector2(3,0))
	start=Time.get_ticks_msec()
	while owner.views.held.is_empty() and Time.get_ticks_msec()-start<10000:await process_frame
	check("old_generation_query_held",not owner.views.held.is_empty())
	check("restore_with_preview_in_flight",(await scene.restore_gpu_checkpoint(path)).is_empty());await process_frame
	check("old_query_keeps_its_domain_owner",not owner.released and scene.runtime.retired.size()==1)
	scene.preview_at(Vector2(3,0));count=scene.preview_received_count
	await _received_count(count+1)
	check("new_generation_preview_before_old_retires",scene.preview_result.get("generation")==1002 and not owner.released)
	scene._preview_has_target=false
	start=Time.get_ticks_msec()
	while scene._preview_pending!=0 and Time.get_ticks_msec()-start<10000:await process_frame
	count=scene.preview_received_count;owner.views.deliver_held();await process_frame;await process_frame
	check("old_generation_reply_cannot_replace_new",scene.preview_received_count==count and scene.preview_result.get("generation")==1002)
	start=Time.get_ticks_msec()
	while not scene.runtime.retired.is_empty() and Time.get_ticks_msec()-start<15000:await process_frame
	check("old_preview_owner_eventually_released",owner.released and scene.runtime.retired.is_empty())
	observations.restored=_small_result(scene.preview_result);observations.events=scene.runtime.events.duplicate(true)
	scene.panel.get_node("Margin/Controls/Tools/Castle").pressed.emit()
	var highwater: int=scene.runtime.highwater()
	scene.preview_at(Vector2(15.9,0));await process_frame;await process_frame
	start=Time.get_ticks_msec()
	while scene._preview_state!=&"invalid" and Time.get_ticks_msec()-start<10000:await process_frame
	check("invalid_footprint_red_without_admission",scene._preview_state==&"invalid" and scene.preview_result.is_empty())
	check("preview_does_not_reserve_commands",scene.runtime.highwater()==highwater)
	scene.preview_at(Vector2(3,0));count=scene.preview_received_count;await _received_count(count+1)
	await RenderingServer.frame_post_draw
	check("live_preview_render",root.get_texture().get_image().save_png(output+"/preview.png")==OK)
	scene._finish_ui_stroke(false);scene._preview_retry_elapsed=0.0
	scene.runtime.current.views.inject_readback_failure_once=true;scene.preview_at(Vector2(3,0))
	start=Time.get_ticks_msec()
	while not scene.runtime.current.views._query.get("unknown",false) and Time.get_ticks_msec()-start<10000:await process_frame
	check("close_starts_with_real_unknown_preview",scene.runtime.current.views.pending and scene.runtime.current.views._query.get("unknown",false))
	await _close()

func _received_count(target: int) -> void:
	var start:=Time.get_ticks_msec()
	while scene.preview_received_count<target and Time.get_ticks_msec()-start<15000:await process_frame
	check("preview_received_"+str(target),scene.preview_received_count>=target)

func _small_result(value: Dictionary) -> Dictionary:
	var result:=value.duplicate(true)
	if result.has("raw"):
		var path:=output+"/query_"+str(scene.preview_received_count)+".bin"
		FileAccess.open(path,FileAccess.WRITE).store_buffer(result.raw);result.erase("raw");result.raw_file={"path":path,"bytes":96,"sha256":FileAccess.get_sha256(path)}
	return result

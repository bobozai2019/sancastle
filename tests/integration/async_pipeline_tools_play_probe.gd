extends "res://tests/integration/async_pipeline_tools_boundary_probe.gd"

func percentile(values: Array, fraction: float) -> float:
	var sorted:=values.duplicate();sorted.sort()
	return float(sorted[clampi(ceili(fraction*sorted.size())-1,0,sorted.size()-1)]) if not sorted.is_empty() else 0.0

func play(tool: StringName, identity: int) -> void:
	preview.playing=true
	if not await ui_stroke(tool,identity):return
	var start_tick: int=preview.completed_ticks
	var start_time: float=preview.async_controller.actual_time
	var frames: Array=[]
	var start:=Time.get_ticks_usec();var previous:=start
	while Time.get_ticks_usec()-start<4000000 and preview.ui_pump_running and preview.last_error.is_empty():
		var u: float=minf(float(Time.get_ticks_usec()-start)/4000000.0,1.0)
		var position:=Vector2(3.0+1.25*sin(u*PI),u*4.0)
		var error: StringName=preview.stroke_controller.append_path_sample(position)
		check("play_path_"+String(tool)+"_%d"%frames.size(),error.is_empty())
		preview.ui_preview_start=preview.ui_preview_end;preview.ui_preview_end=position
		await process_frame
		var now:=Time.get_ticks_usec();frames.append(float(now-previous)/1000.0);previous=now
	check("play_clock_while_stroke_"+String(tool),preview.completed_ticks>start_tick and preview.async_controller.actual_time>start_time)
	check("play_hud_consumes_completed_tick_"+String(tool),preview.status_label.text.contains("Tick %d"%preview.completed_ticks) and preview.status_label.text.contains("模拟 %.2f s"%preview.async_controller.actual_time))
	var open_end_tick: int=preview.completed_ticks
	var open_end_time: float=preview.async_controller.actual_time
	preview._finish_ui_stroke(true)
	var deadline:=Time.get_ticks_msec()+30000
	while preview.ui_pump_running and Time.get_ticks_msec()<deadline:await process_frame
	preview.playing=false
	check("play_drains_"+String(tool),not preview.ui_pump_running and await idle())
	check("play_no_legacy_"+String(tool),preview.async_last_shadow_drain.is_empty() and not preview.async_controller.legacy and preview.last_error.is_empty())
	evidence[String(tool)]={"frames":frames.size(),"measured_window_ms":float(previous-start)/1000.0,"p50_frame_ms":percentile(frames,0.50),"p95_frame_ms":percentile(frames,0.95),"max_frame_ms":percentile(frames,1.0),"water_ticks_during_open_stroke":open_end_tick-start_tick,"advanced_time_s":open_end_time-start_time,"start_tick":start_tick,"open_end_tick":open_end_tick,"drained_tick":preview.completed_ticks,"scope":"short visible-window observation, open-stroke tick window excludes drain; no before/after performance claim"}
	await RenderingServer.frame_post_draw
	var path:=output.get_basename()+"_"+String(tool)+".png"
	check("play_screenshot_"+String(tool),root.get_texture().get_image().save_png(path)==OK)
	evidence[String(tool)].screenshot=path
	evidence[String(tool)].effective_parameters=preview.stroke_controller.params

func _run() -> void:
	preview=load(scene_path).instantiate();preview.playing=false;root.add_child(preview)
	var deadline:=Time.get_ticks_msec()+60000
	while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	check("play_ready",preview.ready_for_ticks and preview.last_error.is_empty())
	if not failed:await play(&"wall_v1",1001)
	if not failed:await play(&"shovel_v1",1002)
	evidence.hardware={"engine":Engine.get_version_info(),"gpu":RenderingServer.get_video_adapter_name(),"driver":RenderingServer.get_current_rendering_driver_name(),"window":DisplayServer.window_get_size(),"visible":root.visible,"vsync":DisplayServer.window_get_vsync_mode(),"profile_passes":preview.solver.profile_passes}
	evidence.configuration=preview.source_signature
	await preview.shutdown()
	check("play_shutdown",preview.gpu_release_done and preview.solver.rd==null)
	preview.queue_free();await process_frame
	var log:=FileAccess.get_file_as_string(output.get_basename()+".log")
	check("play_no_engine_errors",not log.contains("SCRIPT ERROR:") and not log.contains("\nERROR:"))
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"pass":not failed,"checks":checks,"evidence":evidence},"\t"))
	quit(1 if failed else 0)

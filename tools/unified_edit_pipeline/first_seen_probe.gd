extends "res://tools/unified_edit_pipeline/workload_probe.gd"

# Diagnostic only: framebuffer readback deliberately excluded from cost runs.
var visibility:={}

func pixels_changed(a: Image,b: Image) -> int:
	var count:=0
	for y in a.get_height():
		for x in a.get_width():
			var p:=a.get_pixel(x,y);var q:=b.get_pixel(x,y)
			if maxf(absf(p.r-q.r),maxf(absf(p.g-q.g),absf(p.b-q.b)))>2.0/255.0:count+=1
	return count

func _run() -> void:
	preview=load(scene_path).instantiate();preview.playing=false;root.add_child(preview)
	var deadline:=Time.get_ticks_msec()+60000
	while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	check("ready",preview.ready_for_ticks and preview.last_error.is_empty())
	if failed:await _finish_visible();return
	check("fixed_target",_target())
	if failed:await _finish_visible();return
	await preview.get_node("Interface/PerformancePanel").stop_sampling()
	preview.hide_hud=true
	preview.get_node("Interface").visible=false
	check("diagnostic_ui_hidden",not preview.get_node("Interface").visible)
	hardware={"engine":Engine.get_version_info(),"adapter":RenderingServer.get_video_adapter_name(),"driver":RenderingServer.get_current_rendering_driver_name(),"window":DisplayServer.window_get_size(),"viewport":root.get_visible_rect().size,"vsync":DisplayServer.window_get_vsync_mode(),"profile":preview._runtime_configuration_signature(),"effective_profile":preview._effective_profile_request(),"loaded_gdscript_sha256":loaded_code()}
	RenderingServer.call_on_render_thread(_configure_render)
	while not configure_done:await process_frame
	var value:=_fixture(0)
	var p:=_path(0)
	var x:=clampi(floori((p.x+16.0)/0.125),0,255)
	var z:=clampi(floori((p.y+16.0)/0.125),0,255)
	var i:=z*256+x
	var h: float=preview.shadow_domain.rock[i]+preview.shadow_domain.sand[i]
	var center:=Vector3(p.x,h,p.y)
	preview.player_camera.position=center+Vector3(3,5,5)
	preview.player_camera.look_at(center)
	check("fixture_camera_is_active",preview.get_viewport().get_camera_3d()==preview.player_camera)
	hardware.camera_transform=str(preview.player_camera.global_transform)
	hardware.scope="paused pixel-change diagnostic; UI hidden and camera aimed at fixture; screenshot stalls excluded from cost samples"
	for frame in 8:await process_frame
	check("diagnostic_ui_stays_hidden",not preview.get_node("Interface").visible)
	await RenderingServer.frame_post_draw
	var whole:=root.get_texture().get_image()
	var projected: Vector2=preview.player_camera.unproject_position(center)
	var roi:=Rect2i(Vector2i(projected)-Vector2i(80,80),Vector2i(160,160)).intersection(Rect2i(Vector2i.ZERO,whole.get_size()))
	check("visible_roi",roi.size.x==160 and roi.size.y==160)
	var baseline:=whole.get_region(roi)
	whole.save_png(output.get_basename()+"_before.png")
	var noise:=0
	var controls: Array=[]
	for frame in 6:
		await RenderingServer.frame_post_draw
		check("control_ui_hidden_%d"%frame,not preview.get_node("Interface").visible)
		var sample:=root.get_texture().get_image().get_region(roi)
		var changed:=pixels_changed(baseline,sample)
		noise=maxi(noise,changed);controls.append(changed)
	var offered:=Time.get_ticks_usec()
	check("input_admitted",preview.input_scheduler.submit(value).is_empty())
	var shots: Array=[]
	var first:={}
	var previous:=offered
	for frame in 16:
		await RenderingServer.frame_post_draw
		check("capture_ui_hidden_%d"%frame,not preview.get_node("Interface").visible)
		var at:=Time.get_ticks_usec()
		whole=root.get_texture().get_image()
		var changed:=pixels_changed(baseline,whole.get_region(roi))
		var row:={"frame":Engine.get_process_frames(),"capture_started_us":at,"capture_done_us":Time.get_ticks_usec(),"changed_pixels":changed,"interval_start_us":previous}
		shots.append(row)
		if first.is_empty() and changed>noise+10:
			first=row.duplicate(true);whole.save_png(output.get_basename()+"_first_change.png")
		previous=at
	check("first_visible_change_exceeds_control",not first.is_empty())
	if case_id in ["wall","shovel"]:check("stroke_end",(await preview.end_shape_stroke()).is_empty())
	check("drained",await super.idle())
	visibility={"command":value,"admitted_at_us":offered,"roi":roi,"control_pixel_changes":controls,"control_max":noise,"threshold_pixels":noise+10,"first_change":first,"frames":shots,"before_path":output.get_basename()+"_before.png","first_change_path":output.get_basename()+"_first_change.png","interpretation":"first framebuffer ROI change above no-input controls after sole paused edit; frame/readback bounded, not physical monitor scanout"}
	await _finish_visible()

func _finish_visible() -> void:
	check("no_runtime_failure",preview.last_error.is_empty())
	await preview.shutdown()
	check("released",preview.gpu_release_done and preview.solver.rd==null)
	preview.queue_free();await process_frame
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"pass":not failed,"checks":checks,"case":case_id,"wet":wet_target,"runtime":hardware,"target":target_witness,"visibility":visibility},"\t"))
	quit(1 if failed else 0)

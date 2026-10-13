extends "res://tests/edit_validation/beach_gpu_probe.gd"

var samples := []
var attempts := []
var measuring := false
var summary := {}
var native_begin_utc := 0

func _process(_delta: float) -> bool:
	if measuring:
		if "--native-wait-dump" in OS.get_cmdline_user_args():
			var heartbeat:=FileAccess.open(output.path_join("native_heartbeat.bin"),FileAccess.WRITE)
			heartbeat.store_64(native_begin_utc);heartbeat.store_64(int(Time.get_unix_time_from_system()*1000000.0));heartbeat.close()
		samples.append({"at_us":Time.get_ticks_usec(),"tick":preview.completed_ticks,"gpu_busy":preview.gpu_busy,"tick_pending":preview.tick_pending,"pending":preview.command_queue.pending.size(),"accumulator":preview.accumulator,"input_running":preview.input_running,"shadow_reason":preview.shadow_sync_reason,"prefetch":preview.sand_prefetch_in_flight,"collision_replace_ms":preview.collision_proxy.last_replace_ms,"physics_process_ms":Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0,"process_ms":Performance.get_monitor(Performance.TIME_PROCESS)*1000.0})
	return false

func _write() -> void:
	var file:=FileAccess.open(output.path_join("beach_continuous_probe.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass":not failed,"checks":checks,"summary":summary,"samples":samples,"attempts":attempts,"inputs":preview.input_events if preview!=null else [],"terminal":preview.input_results if preview!=null else [],"wait_phases":preview.gpu_wait_phases if preview!=null else [],"applied_log":preview.command_queue.applied_log if preview!=null else [],"tick_rows":preview.profile_tick_rows if preview!=null else [],"collision_candidate":{"reuse":preview.collision_proxy.reuse_chunk_shapes,"allocations":preview.collision_proxy.shape_allocations,"reuses":preview.collision_proxy.shape_reuses},"scope":"3s realtime full beach E drag screening; engine mouse events, CPU frame intervals and completed-tick timestamps; not first-visible or formal 300s/long-stability acceptance"},"\t"))

func _event(point: Vector3, first: bool=false, release: bool=false) -> void:
	var screen: Vector2=preview.get_viewport().get_camera_3d().unproject_position(point)
	var physical: Vector2=preview.get_viewport().get_final_transform()*screen
	var before: int=preview.input_events.size()
	if first or release:
		var event:=InputEventMouseButton.new();event.position=physical;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=not release;Input.parse_input_event(event)
	else:
		var event:=InputEventMouseMotion.new();event.position=physical;event.button_mask=MOUSE_BUTTON_MASK_LEFT;Input.parse_input_event(event)
	if not release: attempts.append({"at_us":Time.get_ticks_usec(),"point":point,"before":before,"after":preview.input_events.size(),"playing":preview.playing,"busy":preview.busy})

func _run() -> void:
	root.size=Vector2i(1920,1080);DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	preview=load("res://tests/edit_validation/edit_beach_interaction_lab.tscn").instantiate();preview.playing=false
	root.add_child(preview)
	while not preview.ready_for_ticks and preview.last_error.is_empty(): await process_frame
	if not preview.last_error.is_empty(): _error(preview.last_error);_write();finished=true;quit(1);return
	await _ticks(15)
	while preview.collision_proxy.staging_texture.is_valid() or not preview.collision_proxy.pending_revisions.is_empty(): await process_frame
	await physics_frame;await physics_frame
	var state: Dictionary=await _snapshot("initial")
	var sand: PackedFloat32Array=state.sand.to_float32_array();var rock: PackedFloat32Array=state.rock.to_float32_array();var water: PackedFloat32Array=state.water.to_float32_array()
	var points:=[]
	for z in range(32,224,4):
		for x in range(32,208,4):
			var candidate:=[]
			for k in 16:
				var i: int=z*256+x+k
				if sand[i]<0.1 or water[i]<0.005: break
				var p:=Vector3((x+k+0.5)*0.125-16,rock[i]+sand[i],(z+0.5)*0.125-16)
				var projected: Vector2=preview.get_viewport().get_camera_3d().unproject_position(p)
				if not preview.get_viewport().get_visible_rect().has_point(projected): break
				var hit: Dictionary=preview.pick(projected)
				if hit.is_empty() or not preview._pick_current(hit): break
				if Vector2(hit.position.x,hit.position.z).distance_to(Vector2(p.x,p.z))>0.001: break
				candidate.append(p)
			if candidate.size()==16: points=candidate;break
		if points.size()==16: break
	if points.size()!=16:
		_error("no current visible wet drag path");await preview.shutdown();_write();finished=true;quit(1);return
	Input.use_accumulated_input=false;preview.water_policy=3;preview.signed_speed_m_s=0.25
	preview.profile_tick_timing=true;preview.profile_tick_rows.clear();preview.observe_gpu_wait_phases=true
	var utc_start: int=int(Time.get_unix_time_from_system()*1000000.0)
	native_begin_utc=utc_start
	var start: int=Time.get_ticks_usec();var end: int=start+3000000
	var initial_tick: int=preview.completed_ticks
	preview.playing=true;measuring=true
	for k in 16:
		while Time.get_ticks_usec()<start+k*200000 and preview.last_error.is_empty(): await process_frame
		_event(points[k],k==0)
	while Time.get_ticks_usec()<end and preview.last_error.is_empty(): await process_frame
	var stop: int=Time.get_ticks_usec();var final_tick: int=preview.completed_ticks
	measuring=false
	if "--native-wait-dump" in OS.get_cmdline_user_args():
		var heartbeat:=FileAccess.open(output.path_join("native_heartbeat.bin"),FileAccess.WRITE)
		heartbeat.store_64(0);heartbeat.store_64(int(Time.get_unix_time_from_system()*1000000.0));heartbeat.close()
	_event(points[-1],false,true);preview.playing=false
	while (preview.input_running or preview.busy) and preview.last_error.is_empty(): await process_frame
	var frames:=[]
	for k in range(1,samples.size()): frames.append(float(samples[k].at_us-samples[k-1].at_us)/1000.0)
	frames.sort()
	var frame_p99: float=frames[mini(frames.size()-1,int(ceil(frames.size()*0.99))-1)] if not frames.is_empty() else INF
	var within:=[]
	for row in preview.profile_tick_rows:
		if row[5]>=start and row[5]<stop: within.append({"tick":row[0],"start_us":row[1],"complete_us":row[5]})
	var once: bool=preview.input_events.size()==16 and preview.input_results.size()==16 and preview.gpu_prefix.size()==16
	var ids:={}
	for item in preview.input_results:
		once=once and item.result.get("status")==1 and not ids.has(item.command.command_id)
		ids[item.command.command_id]=true
	var all_admitted:=true
	for item in preview.input_events: all_admitted=all_admitted and item.admission_error.is_empty()
	var hz: float=float(within.size())*1000000.0/float(stop-start)
	summary={"utc_start_us":utc_start,"utc_stop_us":int(Time.get_unix_time_from_system()*1000000.0),"start_us":start,"stop_us":stop,"duration_s":float(stop-start)/1000000.0,"initial_tick":initial_tick,"final_tick":final_tick,"completed_in_window":within,"completed_hz":hz,"p99_frame_ms":frame_p99,"max_frame_ms":frames[-1] if not frames.is_empty() else INF,"attempted":attempts.size(),"admitted":preview.input_events.size(),"terminal":preview.input_results.size(),"collision_rejections":preview.input_rejections,"max_pending":preview.input_scheduler.max_pending}
	_check("continuous_drag_exactly_once_all16",once and all_admitted and preview.input_scheduler.reserved_total()==0.0 and preview.command_queue.pending.is_empty())
	_check("realtime_original_full_load_progress",final_tick>initial_tick and preview.wave_requests.size()==80 and preview.enable_erosion and preview.last_error.is_empty())
	summary.acceptance={"version":"user_v1.58","minimum_completed_hz":15.0,"maximum_p99_frame_ms":63.0,"scope":"short diagnostic screen; formal windows remain required"}
	_check("short_completed_15hz_screen",hz>=15.0,summary)
	_check("short_p99_frame_screen",frame_p99<=63.0,summary)
	state=await _snapshot("final")
	visual_bytes.clear();RenderingServer.call_on_render_thread(_read_visual)
	while visual_bytes.size()<4: await process_frame
	_check("continuous_final_published_sand_water",visual_bytes.sand==state.sand and visual_bytes.water==state.water)
	for item in checks: failed=failed or not item.pass
	await preview.shutdown();_write();preview.queue_free();finished=true;print("BEACH_CONTINUOUS_COMPLETE pass=%s"%str(not failed));quit(1 if failed else 0)

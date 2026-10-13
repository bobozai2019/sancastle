extends SceneTree

# Observer only: loads the real main scene, enables existing timing hooks.
var preview
var output := ""
var detailed := false
var dense := false
var measuring := false
var label := ""
var rows := []
var cases := []
var previous_us := 0
var seen_gpu_frame := -1
var seen_batches := 0
var seen_phases := 0
var seen_ticket := 0
var seen_revision := -1
var seen_callback := -1
var start_us := 0
var camera_screen := Vector2.ZERO

func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=")
		if arg=="--detailed": detailed=true
		if arg=="--dense": dense=true
	RenderingServer.frame_post_draw.connect(_post_draw)
	call_deferred("_run")

func _process(_delta: float) -> bool:
	if not measuring: return false
	var now:=Time.get_ticks_usec()
	rows.append({"type":"frame","case":label,"us":now,"interval_us":now-previous_us,"tick":preview.completed_ticks,"pending":preview.command_queue.pending.size(),"busy":preview.busy})
	previous_us=now
	while seen_phases<preview.gpu_wait_phases.size():
		rows.append({"type":"phase","case":label,"value":preview.gpu_wait_phases[seen_phases].duplicate(true)})
		seen_phases+=1
	var collision=preview.collision_proxy
	if collision.completed_batches!=seen_batches:
		rows.append({"type":"collision","case":label,"us":now,"batch":collision.completed_batches,"replace_ms":collision.last_replace_ms,"readback_ms":collision.last_readback_ms,"stages":collision.applied_stage_usec.duplicate(true)})
		seen_batches=collision.completed_batches
	if preview.gpu_settled and preview.ticket_id!=seen_ticket:
		seen_ticket=preview.ticket_id
		rows.append({"type":"receipt","case":label,"ticket":seen_ticket,"command_id":preview.gpu_receipt.command_id,"callback_us":preview.solver.receipt_callback_us,"settle_us":preview.settle_us,"receipt":preview.gpu_receipt.duplicate(true)})
	if detailed: RenderingServer.call_on_render_thread(_gpu_times)
	return false

func _gpu_times() -> void:
	if preview==null or preview.closing: return
	var rd: RenderingDevice=preview.solver.rd
	var frame:=rd.get_captured_timestamps_frame()
	if frame==seen_gpu_frame: return
	seen_gpu_frame=frame
	var marks:=[]
	for i in rd.get_captured_timestamps_count():
		marks.append({"name":rd.get_captured_timestamp_name(i),"gpu_ns":rd.get_captured_timestamp_gpu_time(i),"cpu_us":rd.get_captured_timestamp_cpu_time(i)})
	call_deferred("_gpu_record",frame,marks)

func _gpu_record(frame: int, marks: Array) -> void:
	if measuring: rows.append({"type":"gpu","case":label,"frame":frame,"marks":marks})

func _post_draw() -> void:
	if not measuring or not preview.gpu_published: return
	var revision: int=preview.solver.state_revision
	if revision!=seen_revision:
		seen_revision=revision
		rows.append({"type":"post_draw","case":label,"revision":revision,"command_id":preview.gpu_receipt.get("command_id",-1),"us":Time.get_ticks_usec()})

func _enable_gpu_times() -> void:
	preview.solver.profile_passes=detailed
	preview.collision_proxy.profile_passes=detailed

func _wait_idle() -> void:
	while preview.busy or preview.input_running or not preview.command_queue.pending.is_empty() or preview.collision_proxy.staging_texture.is_valid() or not preview.collision_proxy.pending_revisions.is_empty():
		await process_frame

func _input_event(kind: StringName, screen: Vector2, drag: bool=false) -> void:
	preview.selected_sand_tool=kind
	var pick_start:=Time.get_ticks_usec()
	var hit: Dictionary=preview.pick(screen)
	var pick_end:=Time.get_ticks_usec()
	var before: int=preview.input_events.size()
	var event: InputEvent
	if drag:
		var motion:=InputEventMouseMotion.new();motion.position=screen;event=motion
	else:
		var button:=InputEventMouseButton.new();button.position=screen;button.button_index=MOUSE_BUTTON_LEFT;button.pressed=true;event=button
	var begin:=Time.get_ticks_usec()
	preview._unhandled_input(event)
	var end:=Time.get_ticks_usec()
	if measuring:
		rows.append({"type":"input_call","case":label,"begin_us":begin,"end_us":end,"separate_pick_us":pick_end-pick_start,"screen":screen,"hit_position":hit.get("position"),"admitted":preview.input_events.size()>before,"event":"motion" if drag else "click"})
	if not drag:
		var release:=InputEventMouseButton.new();release.button_index=MOUSE_BUTTON_LEFT;release.pressed=false
		preview._input(release)

func _run_case(name: String, live: bool, kind: StringName, drag: bool) -> void:
	preview.playing=false;await _wait_idle()
	var restored: StringName=await preview.restore_gpu_checkpoint(output.path_join("origin.scgpu"))
	if not restored.is_empty(): printerr("restore failed ",restored);quit(1);return
	await _wait_idle();await physics_frame;await physics_frame
	# Restore creates a new solver; timing switches must follow that actual owner.
	RenderingServer.call_on_render_thread(_enable_gpu_times)
	await process_frame
	preview.gpu_wait_phases.clear();seen_phases=0;seen_batches=preview.collision_proxy.completed_batches
	seen_ticket=preview.ticket_id;seen_revision=-1;seen_gpu_frame=-1
	label=name;start_us=Time.get_ticks_usec();previous_us=start_us
	var begin_inputs: int=preview.input_events.size()
	var begin_tick: int=preview.completed_ticks
	measuring=true;preview.accumulator=0.0;preview.playing=live
	var slot:=0
	var duration_us:=3000000
	while Time.get_ticks_usec()-start_us<duration_us and preview.last_error.is_empty():
		if not kind.is_empty() and slot<(32 if dense else 8) and Time.get_ticks_usec()-start_us>=slot*(50000 if dense else 300000)+200000:
			var screen:=camera_screen+Vector2(slot*3 if drag else 0,0)
			if drag and slot==0:
				preview.selected_sand_tool=kind
				var button:=InputEventMouseButton.new();button.position=screen;button.button_index=MOUSE_BUTTON_LEFT;button.pressed=true
				var begin:=Time.get_ticks_usec();preview._unhandled_input(button)
				rows.append({"type":"input_call","case":label,"begin_us":begin,"end_us":Time.get_ticks_usec(),"event":"drag_begin"})
			else: _input_event(kind,screen,drag)
			slot+=1
		await process_frame
	preview.playing=false
	var stop:=Time.get_ticks_usec()
	var release:=InputEventMouseButton.new();release.button_index=MOUSE_BUTTON_LEFT;release.pressed=false;preview._input(release)
	await _wait_idle();await process_frame;await RenderingServer.frame_post_draw
	measuring=false
	var record: Dictionary={"name":name,"live":live,"start_us":start_us,"stop_us":stop,"drained_us":Time.get_ticks_usec(),"begin_tick":begin_tick,"end_tick":preview.completed_ticks,"inputs":preview.input_events.slice(begin_inputs).duplicate(true),"terminals":preview.input_results.duplicate(true),"rejections":preview.input_rejections.duplicate(true),"max_pending":preview.input_scheduler.max_pending,"error":preview.last_error,"stock_m3":preview.domain.tool_inventory_m3}
	cases.append(record)
	if name=="dig_paused": root.get_texture().get_image().save_png(output.path_join("visible_main.png"))
	print("DIAG_CASE ",name," tick=",preview.completed_ticks," inputs=",record.inputs.size())

func _run() -> void:
	root.size=Vector2i(1280,720)
	preview=load("res://scenes/main.tscn").instantiate();preview.playing=false;root.add_child(preview)
	while not preview.ready_for_ticks and preview.last_error.is_empty(): await process_frame
	if not preview.last_error.is_empty(): printerr(preview.last_error);quit(1);return
	for i in 2:
		preview._start_tick()
		while preview.tick_pending: await process_frame
	await _wait_idle();await physics_frame;await physics_frame
	# Fixed world point projected into the actual main camera; real collision picking.
	camera_screen=preview.player_camera.unproject_position(Vector3(-2,0,0))
	var hit: Dictionary=preview.pick(camera_screen)
	if hit.is_empty() or not preview._pick_current(hit): printerr("fixed pick failed");quit(1);return
	# Obtain inventory through production GPU digging before saving the common origin.
	preview.dig_amount_m3=0.20
	_input_event(&"remove_sand",preview.player_camera.unproject_position(Vector3(2,0,0)))
	await _wait_idle()
	preview.dig_amount_m3=0.015;preview.fill_amount_m3=0.015
	var saved: StringName=await preview.save_gpu_checkpoint(output.path_join("origin.scgpu"))
	if not saved.is_empty(): printerr("save failed ",saved);quit(1);return
	preview.observe_gpu_wait_phases=true;preview.collision_proxy.profile_latency_details=true
	RenderingServer.call_on_render_thread(_enable_gpu_times)
	var config: Dictionary={"engine":Engine.get_version_info(),"adapter":RenderingServer.get_video_adapter_name(),"driver":ProjectSettings.get_setting("rendering/rendering_device/driver.windows"),"window":DisplayServer.window_get_size(),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"physics_hz":Engine.physics_ticks_per_second,"water_policy":preview.water_policy,"speed":preview.signed_speed_m_s,"wave_count":preview.wave_requests.size(),"erosion":preview.enable_erosion,"camera_transform":preview.player_camera.global_transform,"screen":camera_screen,"first_pick":hit.position,"profile":preview.configuration_signature(),"render_profile_sha256":preview.requested_render_profile_sha256,"effective_compilation":preview.effective_compilation,"diagnostic_gpu_timestamps":detailed,"origin_sha256":FileAccess.get_sha256(output.path_join("origin.scgpu")),"origin_stock":preview.domain.tool_inventory_m3,"scope":"main scene; 2 warm ticks; checkpoint reset per case; synthetic calls to actual input handler; frame intervals on monotonic clock; post_draw is submission observation, not display scanout"}
	var sequence: Array=[["idle_live",true,&"",false],["dig_live",true,&"remove_sand",false],["fill_live",true,&"place_sand",false],["drag_live",true,&"remove_sand",true],["dig_paused",false,&"remove_sand",false],["fill_paused",false,&"place_sand",false]]
	if dense: sequence=[["dense_drag_live",true,&"remove_sand",true]]
	for item in sequence:
		await _run_case(item[0],item[1],item[2],item[3])
	await preview.shutdown()
	var file:=FileAccess.open(output.path_join("trace.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"configuration":config,"cases":cases,"rows":rows,"released":preview.gpu_release_done},"\t"));file.close()
	print("DIAG_COMPLETE ",output);quit()

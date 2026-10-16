extends SceneTree

# Loads the production scene. Synthetic mouse events use its real picking,
# stroke admission and drain code. No checkpoints, captures or field dumps.
var preview
var output:=""
var detailed:=false
var measuring:=false
var label:=""
var rows:=[]
var cases:=[]
var checks:=[]
var failed:=false
var previous_us:=0
var seen_gpu_frame:=-1
var gpu_collect_pending:=false
var sample_epoch:=0

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
		if arg=="--detailed":detailed=true
	RenderingServer.frame_post_draw.connect(_post_draw)
	call_deferred("_run")

func check(name: String, value: bool) -> void:
	checks.append({"name":name,"pass":value});failed=failed or not value
	print("DRAG_PROFILE ",name," ",value)

func _process(_delta: float) -> bool:
	if not measuring:return false
	var now:=Time.get_ticks_usec()
	var viewport:=root.get_viewport_rid()
	rows.append({"type":"frame","case":label,"us":now,"interval_us":now-previous_us,
		"tick":preview.completed_ticks,"process_frame":Engine.get_process_frames(),"physics_frame":Engine.get_physics_frames(),
		"pending":preview.command_queue.pending.size(),"gpu_busy":preview.gpu_busy,"busy":preview.busy,"tick_pending":preview.tick_pending,
		"process_ms":Performance.get_monitor(Performance.TIME_PROCESS)*1000.0,
		"physics_ms":Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0,
		"render_cpu_ms":RenderingServer.viewport_get_measured_render_time_cpu(viewport),
		"render_gpu_ms":RenderingServer.viewport_get_measured_render_time_gpu(viewport),
		"render_setup_cpu_ms":RenderingServer.get_frame_setup_time_cpu()})
	previous_us=now
	if detailed and not gpu_collect_pending:
		gpu_collect_pending=true
		RenderingServer.call_on_render_thread(_gpu_times.bind(label,sample_epoch))
	return false

func _gpu_times(case_name: String, epoch: int) -> void:
	var marks:=[]
	var frame:=-1
	if preview!=null and not preview.closing and preview.solver.rd!=null:
		var rd: RenderingDevice=preview.solver.rd
		frame=rd.get_captured_timestamps_frame()
		if frame!=seen_gpu_frame:
			seen_gpu_frame=frame
			for i in rd.get_captured_timestamps_count():
				marks.append({"name":rd.get_captured_timestamp_name(i),"gpu_ns":rd.get_captured_timestamp_gpu_time(i),"cpu_us":rd.get_captured_timestamp_cpu_time(i)})
	call_deferred("_gpu_record",case_name,epoch,frame,marks)

func _gpu_record(case_name: String, epoch: int, frame: int, marks: Array) -> void:
	gpu_collect_pending=false
	if epoch==sample_epoch and not marks.is_empty():rows.append({"type":"gpu","case":case_name,"frame":frame,"marks":marks})

func _post_draw() -> void:
	if measuring:rows.append({"type":"post_draw","case":label,"us":Time.get_ticks_usec(),"revision":preview.solver.state_revision,"tick":preview.completed_ticks})

func _enable_profile() -> void:
	preview.solver.profile_passes=detailed
	preview.collision_proxy.profile_passes=detailed

func idle(timeout_ms: int=30000) -> bool:
	var deadline:=Time.get_ticks_msec()+timeout_ms
	while Time.get_ticks_msec()<deadline and preview.last_error.is_empty():
		if not preview.busy and not preview.input_running and not preview.input_scheduler.pumping and preview.command_queue.pending.is_empty() and not preview.collision_proxy.staging_texture.is_valid() and preview.collision_proxy.pending_revisions.is_empty() and not preview.collision_proxy.has_prepare_in_flight():return true
		await process_frame
	return false

func input_at(index: int, scheduled_us: int) -> void:
	var point:=Vector3(-2.0+4.0*float(index)/120.0,0,0.5)
	var screen: Vector2=preview.player_camera.unproject_position(point)
	var event: InputEvent
	if index==0:
		var button:=InputEventMouseButton.new();button.position=screen;button.button_index=MOUSE_BUTTON_LEFT;button.pressed=true;event=button
	else:
		var motion:=InputEventMouseMotion.new();motion.position=screen;motion.button_mask=MOUSE_BUTTON_MASK_LEFT;event=motion
	var before: int=preview.input_events.size()
	var begin:=Time.get_ticks_usec()
	preview._unhandled_input(event)
	rows.append({"type":"input","case":label,"index":index,"scheduled_us":scheduled_us,"begin_us":begin,"end_us":Time.get_ticks_usec(),"events_added":preview.input_events.size()-before,"screen":screen,"intended_world":point})

func run_case(name: String, live: bool, drag: bool) -> void:
	preview=load("res://scenes/main.tscn").instantiate();preview.playing=false;root.add_child(preview)
	var deadline:=Time.get_ticks_msec()+45000
	while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	check(name+"_ready",preview.ready_for_ticks and preview.last_error.is_empty())
	if failed:return
	for i in 2:
		preview._start_tick()
		while preview.tick_pending and preview.last_error.is_empty():await process_frame
	check(name+"_warm_idle",await idle())
	for i in 12:await process_frame
	await physics_frame
	var hit: Dictionary=preview.pick(preview.player_camera.unproject_position(Vector3(-2,0,0.5)))
	check(name+"_pick",not hit.is_empty() and preview._pick_current(hit))
	if failed:return
	preview.collision_proxy.profile_latency_details=true
	preview.collision_proxy.cost_samples.clear()
	RenderingServer.call_on_render_thread(_enable_profile)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	await process_frame
	label=name;sample_epoch+=1;seen_gpu_frame=-1
	var begin_tick: int=preview.completed_ticks
	var config: Dictionary={"engine":Engine.get_version_info(),"adapter":RenderingServer.get_video_adapter_name(),"driver":RenderingServer.get_current_rendering_driver_name(),"method":RenderingServer.get_current_rendering_method(),"window":DisplayServer.window_get_size(),"viewport":root.size,"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"physics_hz":Engine.physics_ticks_per_second,"physics_thread":ProjectSettings.get_setting("physics/3d/run_on_separate_thread",false),"render_thread_model":ProjectSettings.get_setting("rendering/driver/threads/thread_model",1),"water_policy":preview.water_policy,"speed":preview.signed_speed_m_s,"dig_amount_m3":preview.dig_amount_m3,"pipeline":preview.edit_frame_pipeline_enabled,"batch_limit":preview.edit_frame_batch_limit,"collision_prepare":preview.collision_proxy.prepare_policy,"erosion":preview.enable_erosion,"wave_count":preview.wave_requests.size(),"camera":preview.player_camera.global_transform,"profile":preview.configuration_signature(),"render_profile_sha256":preview.requested_render_profile_sha256,"effective_compilation":preview.effective_compilation,"detailed":detailed,"start_unix_s":Time.get_unix_time_from_system(),"pid":OS.get_process_id()}
	# Identity hashing can take hundreds of milliseconds. Complete it before
	# the input schedule and frame clock start, including its render boundary.
	await process_frame
	var start:=Time.get_ticks_usec();previous_us=start
	config.start_unix_s=Time.get_unix_time_from_system()
	measuring=true;preview.accumulator=0.0;preview.playing=live;preview.selected_sand_tool=&"remove_sand"
	var slot:=0
	var duration_us:=6000000 if drag else 4000000
	while Time.get_ticks_usec()-start<duration_us and preview.last_error.is_empty():
		if drag:
			while slot<=120 and Time.get_ticks_usec()-start>=slot*50000:
				input_at(slot,start+slot*50000);slot+=1
		await process_frame
	if drag and slot<=120:
		while slot<=120:input_at(slot,start+slot*50000);slot+=1
	var stopped:=Time.get_ticks_usec()
	var stop_tick: int=preview.completed_ticks
	var pending_at_stop: int=preview.command_queue.pending.size()
	preview._input(_release_event());preview.playing=false
	check(name+"_drained",await idle())
	var drained:=Time.get_ticks_usec()
	for i in 8:await process_frame
	measuring=false
	while gpu_collect_pending:await process_frame
	var inputs: Array=preview.input_events.duplicate(true)
	var terminals: Array=preview.input_scheduler.terminal.duplicate(true)
	var admitted:=inputs.filter(func(row):return row.admission_error.is_empty()).size()
	if drag:
		check(name+"_drag_path",slot==121 and admitted>=90)
		check(name+"_all_settled",terminals.size()==admitted and terminals.all(func(row):return row.result.get("status")==1))
	check(name+"_no_errors",preview.last_error.is_empty() and preview.collision_proxy.invalid_readbacks==0)
	cases.append({"name":name,"live":live,"drag":drag,"start_us":start,"stop_us":stopped,"drained_us":drained,"begin_tick":begin_tick,"stop_tick":stop_tick,"end_tick":preview.completed_ticks,"pending_at_stop":pending_at_stop,"config":config,"input_events":inputs,"terminals":terminals,"rejections":preview.input_rejections.duplicate(true),"batches":preview.frame_pipeline.history.duplicate(true) if preview.frame_pipeline!=null else [],"collision":preview.collision_proxy.cost_samples.duplicate(true),"error":preview.last_error})
	await preview.shutdown();check(name+"_released",preview.gpu_release_done)
	preview.queue_free();await process_frame;preview=null

func _release_event() -> InputEventMouseButton:
	var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=false
	return event

func _run() -> void:
	root.size=Vector2i(1920,1080);DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	for item in [["idle_live",true,false],["drag_live",true,true],["drag_paused",false,true]]:
		await run_case(item[0],item[1],item[2])
		if failed:break
	var file:=FileAccess.open(output,FileAccess.WRITE)
	if file!=null:
		file.store_string(JSON.stringify({"pass":not failed,"checks":checks,"cases":cases,"rows":rows,"scope":"Visible production main, same initial two completed ticks per case, 4m six-second synthetic drag through actual input handler; OS delivery/GUI dispatch/scanout not measured. Timings overlap and must not be summed blindly."}));file.close()
	quit(1 if failed else 0)

extends "res://tests/edit_validation/beach_scene_probe.gd"

var backend := "gpu"
var warmup_s := 2.0
var seconds := 10.0
var policy := 0
var measuring := false
var stream: FileAccess
var start_us := 0
var stop_us := 0
var previous_us := 0
var next_flush_us := 0
var input_index := 0
var terminal_index := 0
var admitted := 0
var rejected := 0
var ticks_in_window := 0
var initial_tick := 0
var submitted_ids := {}
var native_begin_utc := 0
var seen_timestamp_frame := -1
var seen_water_ticket := 0
var pending_cost_readbacks := 0
var trace_closed := false

func _collect_gpu_cost() -> void:
	if preview==null or preview.closing: return
	var rd: RenderingDevice=preview.solver.rd
	var captured:=rd.get_captured_timestamps_frame()
	if captured==seen_timestamp_frame: return
	seen_timestamp_frame=captured
	var marks:=[]
	for i in rd.get_captured_timestamps_count():
		var name:=rd.get_captured_timestamp_name(i)
		if name.begins_with("edit_") or "--cost-render-timing" in OS.get_cmdline_user_args():
			marks.append({"name":name,"gpu_ns":rd.get_captured_timestamp_gpu_time(i),"cpu_us":rd.get_captured_timestamp_cpu_time(i)})
	if not marks.is_empty(): call_deferred("_record_gpu_cost",captured,marks)

func _record_gpu_cost(captured: int, marks: Array) -> void:
	if not trace_closed: _row({"type":"gpu_timestamps","frame":captured,"marks":marks})

func _read_water_cost(ticket: int, command: int) -> void:
	if preview.solver.rd.buffer_get_data_async(preview.solver.water_receipt,_water_cost_data.bind(ticket,command),0,128)!=OK:
		call_deferred("_water_cost_record",PackedByteArray(),ticket,command)

func _water_cost_data(bytes: PackedByteArray, ticket: int, command: int) -> void:
	call_deferred("_water_cost_record",bytes,ticket,command)

func _water_cost_record(bytes: PackedByteArray, ticket: int, command: int) -> void:
	pending_cost_readbacks-=1
	if not trace_closed: _row({"type":"water_cost_receipt","ticket":ticket,"id":command,"bytes":bytes.hex_encode()})

func _heartbeat(active: bool) -> void:
	if "--native-wait-dump" not in OS.get_cmdline_user_args(): return
	var file:=FileAccess.open(output.path_join("native_heartbeat.bin"),FileAccess.WRITE)
	file.store_64(native_begin_utc if active else 0)
	file.store_64(int(Time.get_unix_time_from_system()*1000000.0));file.close()

func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--backend="): backend=arg.trim_prefix("--backend=")
		elif arg.begins_with("--warmup="): warmup_s=float(arg.trim_prefix("--warmup="))
		elif arg.begins_with("--seconds="): seconds=float(arg.trim_prefix("--seconds="))
		elif arg.begins_with("--policy="): policy=int(arg.trim_prefix("--policy="))
	super._init()

func _row(value: Dictionary) -> void:
	stream.store_line(JSON.stringify(value))

func _process(_delta: float) -> bool:
	if not measuring: return false
	var now := Time.get_ticks_usec()
	_heartbeat(true)
	var frame_row: Dictionary={"type":"frame","us":now,"interval_us":now-previous_us,"tick":preview.completed_ticks,
		"pending":preview.command_queue.pending.size(),"memory_bytes":Performance.get_monitor(Performance.MEMORY_STATIC)}
	if "--cost-render-timing" in OS.get_cmdline_user_args():
		frame_row.viewport_cpu_ms=RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid())
		frame_row.viewport_gpu_ms=RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid())
	_row(frame_row)
	previous_us=now
	_take_ticks()
	_take_phases()
	if backend=="gpu" and ("--profile-edit-passes" in OS.get_cmdline_user_args() or "--cost-render-timing" in OS.get_cmdline_user_args()):
		RenderingServer.call_on_render_thread(_collect_gpu_cost)
		if "--profile-edit-passes" in OS.get_cmdline_user_args() and preview.gpu_settled and preview.ticket_id>seen_water_ticket:
			seen_water_ticket=preview.ticket_id;pending_cost_readbacks+=1
			RenderingServer.call_on_render_thread(_read_water_cost.bind(seen_water_ticket,int(preview.gpu_receipt.command_id)))
	if now>=next_flush_us:
		stream.flush();next_flush_us=now+1000000
		var progress:=FileAccess.open(output.path_join("progress.json"),FileAccess.WRITE)
		progress.store_string(JSON.stringify({"phase":"measure","elapsed_s":float(now-start_us)/1000000.0,"tick":preview.completed_ticks,"admitted":admitted,"rejected":rejected}))
	return false

func _take_ticks() -> void:
	for tick_row in preview.profile_tick_rows:
		if tick_row[5]>=start_us and (stop_us==0 or tick_row[5]<stop_us):
			ticks_in_window+=1
			_row({"type":"tick","tick":tick_row[0],"start_us":tick_row[1],"complete_us":tick_row[5],"substeps":tick_row[6]})
	preview.profile_tick_rows.clear()

func _take_phases() -> void:
	if backend!="gpu" or not preview.observe_gpu_wait_phases: return
	for row in preview.gpu_wait_phases: _row({"type":"wait_phase","value":row})
	preview.gpu_wait_phases.clear()

func _submit(index: int) -> void:
	# One deterministic 20s cycle: idle, digging, placing, then alternating drag.
	# Nominal wall-clock slots are shared; actual consumed simulation ticks are logged.
	var phase := index%100
	if phase<25: return
	var kind: StringName=&"remove_sand" if phase<50 or (phase>=75 and index%2==0) else &"place_sand"
	var shape: StringName=&"swept_segment" if phase>=75 else &"circle"
	var point:=Vector3(-2.0+float(index%8)*0.125,0.0,0.0)
	var end:=point+Vector3(0.125,0.0,0.0)
	var command: Dictionary={"domain_id":preview.shadow_domain.domain_id,"generation":preview.generation,
		"sim_tick":preview.completed_ticks,"command_id":index+1,"kind":kind,"shape":shape,
		"transform":{"position_m":point,"end_position_m":end},"radius_m":0.3,
		"strength":1.0,"amount_m3":0.0025 if shape==&"swept_segment" else 0.015,"seed":101}
	var error: StringName
	if backend=="gpu":
		error=preview.input_scheduler.submit(command)
		if error.is_empty() and not preview.input_running:
			preview.input_running=true;preview.call_deferred("_drain_input")
	else:
		# The original CPU entry targets the next tick when a water tick is in flight.
		command.sim_tick+=1 if preview.water_tick_in_flight else 0
		error=preview.command_queue.submit(command)
		if error.is_empty() and not preview.tick_pending: preview._dispatch_paused_patch()
	if error.is_empty(): admitted+=1;submitted_ids[command.command_id]=true
	else: rejected+=1
	_row({"type":"input","slot":index,"nominal_us":start_us+index*200000,"us":Time.get_ticks_usec(),
		"command":command,"error":String(error),"entry":"scheduler" if backend=="gpu" else "original_cpu_queue"})

func _run() -> void:
	if output.is_empty() or backend not in ["cpu","gpu"] or seconds<=0 or warmup_s<0 or policy not in [0,1,2,3] or (backend=="cpu" and policy!=0):
		printerr("invalid cost arguments (CPU comparison requires B0)");quit(2);return
	root.size=Vector2i(1920,1080);DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	if "--cost-render-timing" in OS.get_cmdline_user_args(): RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	var scene_path: String="res://tests/edit_validation/edit_beach_interaction_lab.tscn" if backend=="gpu" else "res://tests/edit_validation/edit_beach_cost_cpu.tscn"
	preview=load(scene_path).instantiate();preview.playing=false;root.add_child(preview)
	var deadline:=Time.get_ticks_msec()+240000
	while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_msec()<deadline: await process_frame
	if not preview.ready_for_ticks or not preview.last_error.is_empty(): printerr("cost initialization failed: "+preview.last_error);quit(1);return
	await _snapshot("initial")
	preview.shadow_domain.tool_inventory_m3=0.5
	if backend=="gpu":
		preview.water_policy=policy;preview.signed_speed_m_s=0.25 if policy>=2 else 0.0
		preview.observe_gpu_wait_phases="--cost-wait-phases" in OS.get_cmdline_user_args()
	# Equal physical warm state, with at least the requested wall-clock warm time.
	# A wall-only warmup leaves different physical ticks on different backends.
	var warm_end:=Time.get_ticks_usec()+int(warmup_s*1000000.0)
	var warm_ticks:=int(ceil(warmup_s*30.0))
	for tick in warm_ticks:
		preview._start_tick()
		while preview.tick_pending and preview.last_error.is_empty(): await process_frame
		if not preview.last_error.is_empty(): break
	while Time.get_ticks_usec()<warm_end and preview.last_error.is_empty(): await process_frame
	await _snapshot("warm")
	stream=FileAccess.open(output.path_join("cost_trace.jsonl"),FileAccess.WRITE)
	preview.profile_tick_timing=true;preview.profile_tick_rows.clear()
	initial_tick=preview.completed_ticks;start_us=Time.get_ticks_usec();previous_us=start_us;next_flush_us=start_us+1000000
	native_begin_utc=int(Time.get_unix_time_from_system()*1000000.0)
	_row({"type":"configuration","backend":backend,"policy":policy,"warmup_s":warmup_s,"seconds":seconds,
		"start_us":start_us,"utc_start_us":native_begin_utc,"warm_ticks":warm_ticks,"trace_version":2,"window_size":DisplayServer.window_get_size(),"vsync":DisplayServer.window_get_vsync_mode(),
		"engine":Engine.get_version_info(),"max_fps":Engine.max_fps,"physics_ticks_per_second":Engine.physics_ticks_per_second,"adapter":RenderingServer.get_video_adapter_name(),"arguments":OS.get_cmdline_user_args(),
		"wave_count":preview.wave_requests.size(),"erosion":preview.enable_erosion,"initial_tick":initial_tick,
		"scope":"full beach wall-clock input; no per-frame GPU state capture; original CPU baseline semantics retained"})
	measuring=true
	_heartbeat(true)
	preview.accumulator=0.0;preview.playing=true
	var end:=start_us+int(seconds*1000000.0)
	while Time.get_ticks_usec()<end and preview.last_error.is_empty():
		if Time.get_ticks_usec()>=start_us+input_index*200000:
			_submit(input_index);input_index+=1
		await process_frame
	stop_us=Time.get_ticks_usec();measuring=false;_take_ticks();preview.playing=false
	_heartbeat(false)
	deadline=Time.get_ticks_msec()+60000
	while (preview.tick_pending or not preview.command_queue.pending.is_empty() or (backend=="gpu" and preview.input_running)) and preview.last_error.is_empty() and Time.get_ticks_msec()<deadline:
		await process_frame
	_take_phases()
	while pending_cost_readbacks>0: await process_frame
	var terminal_ids := {}
	var terminal_count := 0
	if backend=="gpu":
		for item in preview.input_results:
			terminal_count+=1
			_row({"type":"terminal","value":item})
			if item.result.get("status")==1: terminal_ids[int(item.command.command_id)]=true
	else:
		for item in preview.command_queue.applied_log:
			terminal_count+=1
			_row({"type":"terminal","value":item})
			terminal_ids[int(item.command_id)]=true
	var all_terminal: bool=terminal_ids.size()==submitted_ids.size() and terminal_count==submitted_ids.size()
	for id in submitted_ids: all_terminal=all_terminal and terminal_ids.has(id)
	var summary: Dictionary={"backend":backend,"policy":policy,"start_us":start_us,"stop_us":stop_us,
		"duration_s":float(stop_us-start_us)/1000000.0,"completed":ticks_in_window,
		"completed_hz":float(ticks_in_window)*1000000.0/float(stop_us-start_us),"admitted":admitted,"rejected":rejected,
		"all_admitted_terminal":all_terminal,"slots_consumed":input_index,"slots_expected":int(ceil(seconds*5.0)),"error":preview.last_error,"pending":preview.command_queue.pending.size(),
		"pass":all_terminal and input_index==int(ceil(seconds*5.0)) and rejected==0 and preview.last_error.is_empty() and preview.command_queue.pending.is_empty(),
		"performance_verdict":"pending offline frame quantiles; baseline does not require candidate thresholds"}
	_row({"type":"summary","value":summary});stream.flush();trace_closed=true;stream.close()
	var file:=FileAccess.open(output.path_join("beach_cost_probe.json"),FileAccess.WRITE);file.store_string(JSON.stringify(summary,"\t"));file.close()
	if backend=="gpu":
		await preview.shutdown()
	else:
		# CPU baseline owns its original _exit_tree worker and render release path.
		root.remove_child(preview)
		while not preview.cost_released: await process_frame
	preview.queue_free()
	var closed_file:=FileAccess.open(output.path_join("closed.json"),FileAccess.WRITE)
	closed_file.store_string(JSON.stringify({"backend":backend,"released":true}));closed_file.close()
	print("BEACH_COST_COMPLETE "+JSON.stringify(summary));quit(0 if summary.pass else 1)

extends SceneTree

var scene
var original := false
var live := false
var duration_s := 30.0
var run_id := "cost_probe"
var rows: Array = []
var inputs: Array = []
var next_id := 1
var original_busy := false
var shutting_down := false
var initial := {}
var started_us := 0
var initial_tick := 0
var snapshot := {}
var observations: Array = []

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var mode := 2
	var exact := false
	var diagnostics := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--run-id="): run_id = arg.get_slice("=",1)
		elif arg.begins_with("--seconds="): duration_s = arg.get_slice("=",1).to_float()
		elif arg.begins_with("--water-mode="): mode = arg.get_slice("=",1).to_int()
		elif arg == "--original": original = true
		elif arg == "--exact": exact = true
		elif arg == "--live": live = true
		elif arg == "--diagnostic": diagnostics = true
	scene = load("res://scenes/main.tscn" if original else "res://scenes/approx_gpu_edit.tscn").instantiate()
	if not original:
		scene.trial_profile = scene.trial_profile.duplicate()
		scene.trial_profile.water_mode = mode
		scene.trial_profile.diagnostics = diagnostics
		scene.trial_profile.exact_backend = exact
	root.add_child(scene)
	root.gui_disable_input = true
	scene.set_process_input(false)
	scene.set_process_unhandled_input(false)
	if original:
		scene.get_node("Interface/PerformancePanel/Margin/Rows/Header/Sampling").button_pressed = false
		scene.player_camera.set_process(false)
		scene.player_camera.set_process_input(false)
		scene.player_camera.set_process_unhandled_input(false)
	var setup_start := Time.get_ticks_usec()
	while not scene.ready_for_ticks and scene.last_error.is_empty():
		if Time.get_ticks_usec()-setup_start > 45000000: push_error("setup timeout"); quit(1); return
		await process_frame
	scene.playing = false
	while scene.tick_pending: await process_frame
	if original:
		while scene.collision_proxy.shapes.size() < 64 and scene.last_error.is_empty():
			if Time.get_ticks_usec()-setup_start > 45000000: push_error("collision setup timeout"); quit(1); return
			await process_frame
	for field in ["rock","sand","water","sediment","wetness","compaction"]:
		var values: PackedFloat32Array = scene.shadow_domain.get(field)
		var hash := HashingContext.new(); hash.start(HashingContext.HASH_SHA256); hash.update(values.to_byte_array())
		initial[field] = hash.finish().hex_encode()
	initial_tick = scene.completed_ticks
	scene.playing = live
	started_us = Time.get_ticks_usec()
	var next_input := started_us
	var prev := started_us
	var next_observation := started_us+60000000
	while Time.get_ticks_usec()-started_us < duration_s*1000000.0 and scene.last_error.is_empty():
		await process_frame
		var now := Time.get_ticks_usec()
		rows.append([now,now-prev,scene.completed_ticks,int(scene.tick_pending),scene.trial_queue.size() if not original else int(scene.gpu_busy),int(DisplayServer.window_is_focused()),DisplayServer.window_get_mode()])
		prev = now
		if duration_s >= 300.0 and now >= next_observation:
			root.get_texture().get_image().save_png("res://test_output/approx_gpu_edit_trial/"+run_id+"/observe_%03d.png" % int((now-started_us)/1000000))
			RenderingServer.call_on_render_thread(read_snapshot)
			next_observation += 60000000
		if now >= next_input:
			if original:
				if not original_busy and not scene.tick_pending and not scene.gpu_busy:
					original_busy = true
					submit_original(next_id,now)
					next_id += 1
					next_input += 250000
			else:
				var pair := (next_id-1)/2
				var a := Vector2(-2.0+float(pair%10)*0.2,-0.5)
				var admission: Dictionary = scene.submit_brush({"generation":scene.generation,"command_id":next_id,"kind":"dig" if next_id%2==1 else "fill","start_xz_m":a,"end_xz_m":a+Vector2(0.1,0),"radius_m":0.3,"nominal_amount_m3":0.015,"input_us":now,"requested_tick":scene.completed_ticks,"seed":101})
				inputs.append({"id":next_id,"input_us":now,"admission":admission})
				next_id += 1
				next_input += 250000
	var window_end := Time.get_ticks_usec()
	scene.playing = false
	while scene.tick_pending or original_busy or (scene.gpu_busy if original else scene.trial_busy or not scene.trial_queue.is_empty()): await process_frame
	RenderingServer.call_on_render_thread(read_snapshot)
	snapshot = {}
	while snapshot.is_empty(): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://test_output/approx_gpu_edit_trial/"+run_id+"/end.png")
	var report := {"run_id":run_id,"original":original,"exact":exact,"live":live,"diagnostic":diagnostics,"mode":mode,"duration_s":duration_s,"start_us":started_us,"end_us":window_end,"drain_end_us":Time.get_ticks_usec(),"initial_hashes":initial,"initial_tick":initial_tick,"final_tick":scene.completed_ticks,"frames":rows,"inputs":inputs,"events":scene.gpu_events if original else scene.trial_events,"gpu_timestamps":[] if original else scene.trial_gpu_rows,"snapshot":snapshot,"observations":observations,"effective_profile":scene.effective_render_profile,"wave_request_count":scene.wave_requests.size(),"erosion":scene.enable_erosion,"size":root.size,"vsync":DisplayServer.window_get_vsync_mode(),"engine":Engine.get_version_info(),"adapter":RenderingServer.get_video_adapter_name(),"error":scene.last_error,"measurement":"CPU frame intervals plus submission/publication/post_draw; GPU diagnostics separate; scanout unknown"}
	report["input_isolation"] = true
	report["all_admitted"] = inputs.all(func(e): return e.result.get("status")==1 if original else e.admission.accepted)
	report["controlled"] = report.all_admitted and (original or scene.trial_events.filter(func(e): return e.phase=="queued").size()==inputs.size())
	var file := FileAccess.open("res://test_output/approx_gpu_edit_trial/"+run_id+"/result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"));file.close()
	scene.queue_free()
	await process_frame
	await process_frame
	print("PASS: cost operation" if report.error.is_empty() and snapshot.invalid==0 else "FAIL: cost operation")
	quit(0 if report.error.is_empty() and snapshot.invalid==0 else 1)

func submit_original(id: int,input_us: int) -> void:
	var pair := (id-1)/2
	var a := Vector3(-2.0+float(pair%10)*0.2,0,-0.5)
	var command := {"generation":scene.generation,"command_id":id,"kind":&"remove_sand" if id%2==1 else &"place_sand","shape":&"swept_segment","transform":{"position_m":a,"end_position_m":a+Vector3(0.1,0,0)},"radius_m":0.3,"amount_m3":0.015,"strength":1.0,"seed":101,"sim_tick":scene.completed_ticks}
	command["domain_id"] = scene.shadow_domain.domain_id
	var result: Dictionary = await scene.apply_gpu_command(command)
	inputs.append({"id":id,"input_us":input_us,"return_us":Time.get_ticks_usec(),"result":result})
	original_busy = false

func read_snapshot() -> void:
	var invalid := 0
	var totals := {}
	var extrema := {}
	for field in ["sand","water","momentum_x","momentum_z"]:
		var data: PackedFloat32Array = scene.solver.rd.texture_get_data(scene.solver.current_texture(field),0).to_float32_array()
		var total := 0.0
		var maximum := 0.0
		for value in data:
			if not is_finite(value) or (field in ["sand","water"] and value<0.0): invalid += 1
			total += value*0.015625
			maximum = maxf(maximum,absf(value))
		totals[field] = total
		extrema[field] = maximum
	call_deferred("snapshot_ready",{"invalid":invalid,"totals":totals,"max_abs":extrema,"at_us":Time.get_ticks_usec()})
func snapshot_ready(value: Dictionary) -> void:
	snapshot = value
	observations.append(value)

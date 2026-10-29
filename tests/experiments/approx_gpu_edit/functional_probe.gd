extends SceneTree

var trial
var failures: Array[String] = []
var snapshot := {}
var started_us := 0
var run_id := "functional_v1"
var initial_identity := {}
var initial_totals := {}
var report_output := ""
var pointer_diagnostics := []
var input_harness:Node
var input_viewport:SubViewport

func record_pointer(phase:String,requested:Vector2) -> void:
	var hovered:Control=input_viewport.gui_get_hovered_control()
	pointer_diagnostics.append({"phase":phase,"requested":requested,"actual":input_viewport.get_mouse_position(),"hovered":String(hovered.get_path()) if hovered!=null else "","left_pressed":Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT),"drag":trial.trial_drag,"hit":trial._brush_hit(),"ready":trial.ready_for_ticks,"closing":trial.closing,"shutdown":trial.trial_shutdown})

func send_pointer(event:InputEvent) -> void:
	# Global Input state and the viewport's local event position are both needed
	# by this unmodified legacy scene. No native cursor movement is required.
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	input_viewport.push_input(event,true)

func _initialize() -> void:
	started_us = Time.get_ticks_usec()
	call_deferred("run")

func check(condition: bool,message: String) -> void:
	if not condition: failures.append(message)

func wait_idle() -> void:
	while trial.tick_pending or trial.trial_busy or not trial.trial_queue.is_empty():
		if Time.get_ticks_usec()-started_us > 60000000: failures.append("idle timeout"); return
		await process_frame

func command(id: int,kind: String,a: Vector2=Vector2.ZERO,amount: float=0.015) -> Dictionary:
	return {"generation":trial.generation,"command_id":id,"kind":kind,"start_xz_m":a,"end_xz_m":a,"radius_m":0.3,"nominal_amount_m3":amount,"input_us":Time.get_ticks_usec(),"requested_tick":trial.completed_ticks,"seed":101}

func run() -> void:
	trial = load("res://scenes/approx_gpu_edit.tscn").instantiate()
	trial.trial_profile = trial.trial_profile.duplicate()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): report_output=arg.trim_prefix("--output=")
		if arg.begins_with("--run-id="): run_id = arg.get_slice("=",1)
		if arg.begins_with("--water-mode="): trial.trial_profile.water_mode = arg.get_slice("=",1).to_int()
		if arg == "--exact": trial.trial_profile.exact_backend = true
		if arg.begins_with("--exact-policy="): trial.trial_profile.exact_water_policy = arg.get_slice("=",1).to_int()
		if arg == "--diagnostic": trial.trial_profile.diagnostics = true
	input_harness=load("res://tests/experiments/approx_gpu_edit/input_harness.tscn").instantiate()
	root.add_child(input_harness)
	input_viewport=input_harness.get_node("InputViewport")
	input_viewport.add_child(trial)
	while not trial.ready_for_ticks and trial.last_error.is_empty():
		if Time.get_ticks_usec()-started_us > 30000000: failures.append("ready timeout"); break
		await process_frame
	check(trial.last_error.is_empty(),"startup: "+trial.last_error)
	if failures.is_empty():
		trial.playing = false
		await wait_idle()
		for field in ["rock","sand","water","sediment","wetness","compaction"]:
			var values: PackedFloat32Array = trial.shadow_domain.get(field)
			var hash := HashingContext.new(); hash.start(HashingContext.HASH_SHA256); hash.update(values.to_byte_array())
			initial_identity[field] = hash.finish().hex_encode()
			var total := 0.0
			for value in values: total += value * 0.015625
			initial_totals[field] = total
		check(root.find_children("*","CollisionShape3D",true,false).is_empty(),"collision shape created")
		check(trial.collision_proxy.rd == null,"collision RenderingDevice initialized")
		check(trial.plane_hit(Vector3(0,1,0),Vector3.RIGHT) == null,"parallel ray")
		check(trial.plane_hit(Vector3(0,1,0),Vector3.UP) == null,"backward ray")
		check(trial.plane_hit(Vector3(16,1,0),Vector3.DOWN) == null,"half-open domain")
		check(trial.plane_hit(Vector3(0,1,0),Vector3.DOWN) == Vector3.ZERO,"plane hit")
		check(not trial.submit_brush(command(1,"fill")).accepted,"empty stock fill")
		check(not trial.submit_brush(command(1,"fill",Vector2.ZERO,1e-12)).accepted,"tiny empty stock fill")
		var invalid := command(1,"dig"); invalid.command_id = 1.5
		check(trial.submit_brush(invalid).error == "invalid_request","fractional ID")
		invalid = command(1,"dig"); invalid.radius_m = NAN
		check(trial.submit_brush(invalid).error == "invalid_request","NaN radius")
		invalid = command(1,"dig"); invalid.start_xz_m = Vector2(INF,0)
		check(trial.submit_brush(invalid).error == "invalid_request","infinite position")
		check(trial.submit_brush(command(1,"dig")).accepted,"dig admission")
		check(is_equal_approx(trial.nominal_stock_m3,0.015),"nominal dig stock")
		check(not trial.submit_brush(command(1,"dig")).accepted,"duplicate ID")
		check(trial.submit_brush(command(2,"fill")).accepted,"fill admission")
		check(is_zero_approx(trial.nominal_stock_m3),"nominal fill stock")
		var stale := command(3,"dig"); stale.generation -= 1
		check(trial.submit_brush(stale).error == "stale_generation","epoch rejection")
		check(trial.submit_brush(command(3,"dig",Vector2(16,0))).error == "out_of_domain","domain rejection")
		for id in range(3,65): check(trial.submit_brush(command(id,"dig",Vector2(0,float(id%6)*0.1))).accepted,"queue admission %d" % id)
		check(trial.submit_brush(command(65,"dig")).error == "queue_full","queue cap")
		await wait_idle()
		check(trial.completed_ticks == 0,"paused edit advanced tick")
		check(trial.trial_events.filter(func(e): return e.phase == "dispatched").size() == 64,"dispatch count")
		RenderingServer.call_on_render_thread(read_snapshot)
		while snapshot.is_empty(): await process_frame
		check(snapshot.invalid == 0,"nonfinite/negative snapshot")
		check(snapshot.sand_changed > 0,"GPU sand did not change")
		await RenderingServer.frame_post_draw
		var image_output:String=report_output if not report_output.is_empty() else "res://test_output/approx_gpu_edit_trial/"+run_id
		DirAccess.make_dir_recursive_absolute(image_output)
		check(root.get_texture().get_image().save_png(image_output.path_join("paused_edit.png"))==OK,"paused edit image export failed")
		trial.playing = true
		var target: int = trial.completed_ticks+6
		while trial.completed_ticks < target and trial.last_error.is_empty():
			if Time.get_ticks_usec()-started_us > 60000000: failures.append("tick timeout"); break
			await process_frame
		trial.playing = false
		await wait_idle()
		check(trial.last_error.is_empty(),"simulation: "+trial.last_error)
		var point: Vector2 = trial.player_camera.unproject_position(Vector3(-2,0,-0.5))
		var before_id: int = trial.trial_highwater
		record_pointer("before_world_press",point)
		push_mouse(point,true)
		record_pointer("after_world_press",point)
		await process_frame
		record_pointer("after_world_press_frame",point)
		check(input_viewport.get_mouse_position().distance_to(point)<1.0,"viewport pointer missed requested target")
		var world_hit:Variant=trial._brush_hit()
		check(world_hit is Vector3 and world_hit.distance_to(Vector3(-2,0,-0.5))<0.01,"world pointer ray missed requested target")
		check(trial.trial_drag,"world press did not begin drag")
		var motion := InputEventMouseMotion.new()
		motion.position = point+Vector2(20,0); motion.global_position = motion.position
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		send_pointer(motion)
		await process_frame
		await process_frame
		var ui_button: Button = trial.get_node("Interface/TrialPanel/Fill")
		var before_ui: int = trial.trial_highwater
		motion.position = ui_button.get_global_rect().get_center()
		motion.global_position = motion.position
		send_pointer(motion)
		await process_frame
		await process_frame
		check(input_viewport.get_mouse_position().distance_to(motion.position)<1.0,"UI pointer missed requested target")
		check(input_viewport.gui_get_hovered_control()!=null,"UI pointer did not hover a control")
		check(not trial.trial_drag,"drag entering UI did not stop")
		check(trial.trial_highwater == before_ui,"drag entering UI submitted edit")
		push_mouse(motion.position,false)
		await process_frame
		check(not trial.trial_drag,"release did not stop drag")
		await wait_idle()
		check(trial.trial_highwater > before_id,"mouse path did not submit")
		before_id = trial.trial_highwater
		var button: Button = trial.get_node("Interface/TrialPanel/Fill")
		point = button.get_global_rect().get_center()
		push_mouse(point,true)
		await process_frame
		push_mouse(point,false)
		await process_frame
		check(trial.trial_highwater == before_id,"UI click submitted terrain edit")
		check(not trial.trial_drag,"UI release left drag active")
	var report := {"failures":failures,"initial_identity":initial_identity,"initial_totals":initial_totals,"snapshot":snapshot,"events":trial.trial_events,"frames":trial.trial_frame_rows,"gpu_timestamps":trial.trial_gpu_rows,"ticks":trial.completed_ticks,"effective_profile":trial.effective_render_profile,"wave_requests":trial.wave_requests,"erosion":trial.enable_erosion,"size":root.size,"vsync":DisplayServer.window_get_vsync_mode(),"engine":Engine.get_version_info(),"adapter":RenderingServer.get_video_adapter_name(),"water_mode":trial.trial_water_mode,"exact":trial.trial_profile.exact_backend,"exact_water_policy":trial.trial_profile.exact_water_policy,"last_error":trial.last_error}
	var destination: String=report_output if not report_output.is_empty() else "res://test_output/approx_gpu_edit_trial/"+run_id
	report["pointer_diagnostics"]=pointer_diagnostics
	report["input_scope"]="Original scene in a visible 1280x720 SubViewport; actual local input and GUI dispatch, global Input state, no native cursor warp. Does not prove OS window focus/cursor behavior."
	DirAccess.make_dir_recursive_absolute(destination)
	report["pass"]=failures.is_empty()
	var file := FileAccess.open(destination.path_join("result.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t")); file.close()
	trial.queue_free()
	await process_frame
	input_harness.queue_free()
	await process_frame
	print("PASS: trial functional" if failures.is_empty() else "FAIL: "+str(failures))
	quit(0 if failures.is_empty() else 1)

func read_snapshot() -> void:
	var invalid := 0
	var changed := 0
	var totals := {}
	for field in ["sand","water","momentum_x","momentum_z"]:
		var data: PackedFloat32Array = trial.solver.rd.texture_get_data(trial.solver.current_texture(field),0).to_float32_array()
		var total := 0.0
		for index in data.size():
			var value := data[index]
			if not is_finite(value) or (field in ["sand","water"] and value < 0.0): invalid += 1
			if field == "sand" and absf(value-trial.shadow_domain.sand[index]) > 1e-6: changed += 1
			total += value * 0.015625
		totals[field] = total
	call_deferred("snapshot_ready",{"invalid":invalid,"sand_changed":changed,"totals":totals})

func snapshot_ready(value: Dictionary) -> void: snapshot = value

func push_mouse(point: Vector2,pressed: bool) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point; motion.global_position = point
	send_pointer(motion)
	var event := InputEventMouseButton.new()
	event.position = point; event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT; event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	send_pointer(event)

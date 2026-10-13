extends SceneTree
var preview
var output := ""
var checks := []
func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=")
	call_deferred("_run")
func check(name: String, ok: bool) -> void:
	checks.append({"name":name,"pass":ok});print("MANUAL_WAVE_CHECK ",name," ",ok)
func _tick() -> void:
	var before: int=preview.completed_ticks;preview._start_tick()
	while preview.completed_ticks==before and preview.last_error.is_empty(): await process_frame
func _run() -> void:
	root.size=Vector2i(1280,720)
	preview=load("res://scenes/main.tscn").instantiate();preview.playing=false;root.add_child(preview)
	while not preview.ready_for_ticks and preview.last_error.is_empty(): await process_frame
	if not preview.last_error.is_empty(): printerr(preview.last_error);quit(1);return
	var spin: SpinBox=preview.get_node("Interface/EditPanel/Margin/Controls/WaveAmount")
	var button: Button=preview.get_node("Interface/EditPanel/Margin/Controls/TriggerWave")
	check("ready_button",not button.disabled)
	check("automatic_packets_preserved",preview.wave_requests.size()==80)
	var baseline: float=preview._wave_height_at_tick(46)
	var input_count: int=preview.input_events.size()
	spin.value=0.08
	# Real GUI mouse press/release proves the button does not reach sand input.
	var click:=InputEventMouseButton.new();click.position=button.get_global_rect().get_center();click.button_index=MOUSE_BUTTON_LEFT;click.pressed=true
	Input.parse_input_event(click);await process_frame
	click.pressed=false;Input.parse_input_event(click);await process_frame
	check("gui_button_native_request",preview.wave_requests.size()==81 and is_equal_approx(preview.wave_requests[-1].amplitude_m,0.08) and preview.wave_requests[-1].duration_s==3.0)
	check("pause_queues_wave",not preview.playing and preview.completed_ticks==0 and "继续" in preview.manual_wave_message)
	check("wave_button_no_sand_edit",preview.input_events.size()==input_count)
	# A tick is in flight: the request must be scheduled strictly beyond it.
	preview._start_tick();spin.value=0.03;button.pressed.emit()
	check("inflight_future_tick",preview.wave_requests.size()==82 and preview.wave_requests[-1].start_tick>preview.completed_ticks+1)
	while preview.tick_pending: await process_frame
	check("independent_amount_and_ids",is_equal_approx(preview.wave_requests[-2].amplitude_m,0.08) and is_equal_approx(preview.wave_requests[-1].amplitude_m,0.03) and preview.wave_requests[-1].request_id>preview.wave_requests[-2].request_id)
	check("waveform_changed",preview._wave_height_at_tick(46)>baseline+0.08)
	for i in 45: await _tick()
	check("gpu_wave_ticks",preview.completed_ticks==46 and preview.last_error.is_empty() and is_finite(preview.solver.water_source_m3) and is_finite(preview.solver.water_sink_m3))
	var saved: StringName=await preview.save_gpu_checkpoint(output.path_join("manual_wave.bin"))
	check("wave_checkpoint_save",saved.is_empty())
	var requests: Array=preview.wave_requests.duplicate(true)
	var restored: StringName=await preview.restore_gpu_checkpoint(output.path_join("manual_wave.bin"))
	var equal: bool=preview.wave_requests.size()==requests.size()
	for i in requests.size():
		var before: Dictionary=requests[i].duplicate(true);var after: Dictionary=preview.wave_requests[i].duplicate(true);before.erase("generation");after.erase("generation");equal=equal and before==after and preview.wave_requests[i].generation==preview.generation
	check("wave_checkpoint_restores",restored.is_empty() and equal and preview.wave_highwater_id==82)
	await process_frame;check("button_reenabled_after_restore",not button.disabled)
	var count: int=preview.wave_requests.size();preview.gpu_save_running=true;preview._on_trigger_wave_pressed();preview.gpu_save_running=false
	check("save_boundary_rejects_new_wave",preview.wave_requests.size()==count)
	preview._update_status();await process_frame;await RenderingServer.frame_post_draw
	var panel: Control=preview.get_node("Interface/EditPanel")
	check("panel_fits",root.get_visible_rect().encloses(panel.get_global_rect()))
	root.get_texture().get_image().save_png(output.path_join("manual_wave_ui.png"))
	await preview.shutdown()
	var passed:=true
	for row in checks: passed=passed and row.pass
	var file:=FileAccess.open(output.path_join("result.json"),FileAccess.WRITE);file.store_string(JSON.stringify({"pass":passed,"checks":checks},"\t"));print("MANUAL_WAVE_COMPLETE ",passed);quit(0 if passed else 1)

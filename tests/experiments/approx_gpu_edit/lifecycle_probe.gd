extends SceneTree

var trial
var run_id := "lifecycle"
var errors: Array[String] = []
var started_us := 0
var report := {}
var report_output := ""

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): report_output=arg.trim_prefix("--output=")
		if arg.begins_with("--run-id="): run_id = arg.get_slice("=",1)
	started_us = Time.get_ticks_usec()
	call_deferred("run")

func ready_scene() -> void:
	while not trial.ready_for_ticks and trial.last_error.is_empty():
		if Time.get_ticks_usec()-started_us > 45000000: errors.append("ready timeout");return
		await process_frame
	trial.playing = false
	while trial.tick_pending: await process_frame

func queue_edits() -> void:
	for id in range(1,33):
		var result: Dictionary = trial.submit_brush({"generation":trial.generation,"command_id":id,"kind":"dig","start_xz_m":Vector2.ZERO,"end_xz_m":Vector2(0.1,0),"radius_m":0.3,"nominal_amount_m3":0.015,"requested_tick":trial.completed_ticks,"seed":101})
		if not result.accepted: errors.append("admission rejected")

func run() -> void:
	trial = load("res://scenes/approx_gpu_edit.tscn").instantiate()
	root.add_child(trial)
	current_scene = trial
	await ready_scene()
	queue_edits()
	var old = trial
	var id: int = old.get_instance_id()
	var old_epoch: int = old.generation
	old._reset_trial()
	while current_scene == null or current_scene.get_instance_id()==id:
		if Time.get_ticks_usec()-started_us > 45000000: errors.append("reset timeout");break
		await process_frame
	trial = current_scene
	await ready_scene()
	if trial.generation <= old_epoch: errors.append("reset epoch not advanced")
	var stale: Dictionary = trial.submit_brush({"generation":old_epoch,"command_id":1,"kind":"dig","start_xz_m":Vector2.ZERO,"end_xz_m":Vector2.ZERO,"radius_m":0.3,"nominal_amount_m3":0.015,"requested_tick":0,"seed":101})
	if stale.error != "stale_generation": errors.append("reset accepted old epoch")
	if not is_zero_approx(trial.nominal_stock_m3) or trial.trial_highwater != 0 or not trial.trial_queue.is_empty(): errors.append("reset state not fresh")
	if is_instance_valid(old): errors.append("old scene survived reset")
	queue_edits()
	trial._reset_trial()
	trial._close_trial()
	trial._toggle_trial_pause()
	if trial.playing: errors.append("shutdown pause toggle restarted ticks")
	var rejected: Dictionary = trial.submit_brush({"generation":trial.generation,"command_id":33})
	if rejected.error != "closing": errors.append("closing admission accepted")
	while not trial.trial_queue.is_empty() or trial.trial_busy or trial.tick_pending:
		if Time.get_ticks_usec()-started_us > 60000000: errors.append("close drain timeout");break
		await process_frame
	report = {"errors":errors,"reset_from_epoch":old_epoch,"final_epoch":trial.generation,"close_won_reset":trial.trial_close_requested,"stock":trial.nominal_stock_m3,"queued":trial.trial_queue.size(),"events":trial.trial_events,"last_error":trial.last_error}
	write_report()
	print("PASS: lifecycle" if errors.is_empty() else "FAIL: lifecycle "+str(errors))
	quit(0 if errors.is_empty() else 1)

func write_report() -> void:
	var destination: String=report_output if not report_output.is_empty() else "res://test_output/approx_gpu_edit_trial/"+run_id
	DirAccess.make_dir_recursive_absolute(destination)
	report["pass"]=errors.is_empty()
	var file := FileAccess.open(destination.path_join("result.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"));file.close()

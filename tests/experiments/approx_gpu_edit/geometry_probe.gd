extends SceneTree

var trial
var run_id := "geometry"
var errors: Array[String] = []
var snapshots: Array = []
var read_pending := false
var next_id := 1
var sample_indices: Array[int] = []

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--run-id="): run_id = arg.get_slice("=",1)
	call_deferred("run")

func point(index: int) -> Vector2:
	return Vector2((float(index%256)+0.5-128.0)*0.125,(float(index/256)+0.5-128.0)*0.125)

func edit_batch(kind: String,at: Vector2,count: int=64) -> void:
	for index in count:
		var result: Dictionary = trial.submit_brush({"generation":trial.generation,"command_id":next_id,"kind":kind,"start_xz_m":at,"end_xz_m":at,"radius_m":0.3,"nominal_amount_m3":0.06,"requested_tick":0,"seed":101})
		if not result.accepted: errors.append("geometry admission "+result.error)
		next_id += 1
	while trial.trial_busy or not trial.trial_queue.is_empty(): await process_frame
	read_pending = true
	RenderingServer.call_on_render_thread(read_snapshot)
	while read_pending: await process_frame

func run() -> void:
	trial = load("res://scenes/approx_gpu_edit.tscn").instantiate()
	trial.trial_profile = trial.trial_profile.duplicate()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--water-mode="): trial.trial_profile.water_mode = arg.get_slice("=",1).to_int()
	root.add_child(trial)
	root.gui_disable_input = true
	trial.set_process_input(false);trial.set_process_unhandled_input(false)
	while not trial.ready_for_ticks and trial.last_error.is_empty(): await process_frame
	trial.playing = false
	while trial.tick_pending: await process_frame
	var peak := 0
	var wet := 0
	for index in trial.shadow_domain.sand.size():
		if trial.shadow_domain.bed_at(index) > trial.shadow_domain.bed_at(peak): peak=index
		if trial.shadow_domain.water[index] > trial.shadow_domain.water[wet]: wet=index
	sample_indices = [peak,wet]
	await edit_batch("dig",point(peak))
	if absf(snapshots.back().samples[0].sand)>1e-6: errors.append("dig floor failed")
	var stock: float = trial.nominal_stock_m3
	await edit_batch("dig",point(peak))
	if absf(snapshots.back().samples[0].sand)>1e-6 or not is_equal_approx(trial.nominal_stock_m3,stock+3.84): errors.append("empty sand nominal semantics")
	await edit_batch("fill",point(peak))
	if absf(snapshots.back().samples[0].sand-4.0)>1e-5: errors.append("fill ceiling failed")
	await edit_batch("dig",point(wet),32)
	await edit_batch("fill",point(wet),32)
	await edit_batch("fill",Vector2(15.99,15.99),32)
	if trial.completed_ticks != 0: errors.append("geometry advanced tick")
	if not trial.last_error.is_empty(): errors.append(trial.last_error)
	for sample in snapshots:
		if sample.invalid>0: errors.append("invalid field snapshot")
		if trial.trial_water_mode>0 and sample.max_speed>1.001: errors.append("template velocity bound failed")
	var report := {"errors":errors,"water_mode":trial.trial_water_mode,"peak":point(peak),"wet":point(wet),"snapshots":snapshots,"stock":trial.nominal_stock_m3,"events":trial.trial_events,"tick":trial.completed_ticks}
	var file := FileAccess.open("res://test_output/approx_gpu_edit_trial/"+run_id+"/result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"));file.close()
	trial.queue_free();await process_frame;await process_frame
	print("PASS: geometry" if errors.is_empty() else "FAIL: geometry "+str(errors))
	quit(0 if errors.is_empty() else 1)

func read_snapshot() -> void:
	var fields := {}
	var invalid := 0
	var totals := {}
	for field in ["sand","water","momentum_x","momentum_z"]:
		fields[field] = trial.solver.rd.texture_get_data(trial.solver.current_texture(field),0).to_float32_array()
		var total := 0.0
		for value in fields[field]:
			if not is_finite(value) or (field in ["sand","water"] and value<0): invalid+=1
			total+=value*0.015625
		totals[field]=total
	var max_speed := 0.0
	for index in fields.water.size():
		if fields.water[index]>0.0001:
			max_speed=maxf(max_speed,Vector2(fields.momentum_x[index],fields.momentum_z[index]).length()/fields.water[index])
	var samples: Array = []
	for index in sample_indices:
		samples.append({"sand":fields.sand[index],"water":fields.water[index],"qx":fields.momentum_x[index],"qz":fields.momentum_z[index]})
	call_deferred("snapshot_ready",{"invalid":invalid,"totals":totals,"samples":samples,"max_speed":max_speed})
func snapshot_ready(value: Dictionary) -> void:
	snapshots.append(value)
	read_pending=false

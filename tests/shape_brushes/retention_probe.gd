extends "res://tests/shape_brushes/legacy_pair_probe.gd"

const Fixture = preload("res://tests/shape_brushes/retention_fixture.gd")
var mode := "baseline"
var target_ticks := 900
var samples := []

func _retention_scene_path() -> String:
	return "res://tests/shape_brushes/retention_lab.tscn"

func _retention_resources_released() -> bool:
	return preview.gpu_release_done and preview.shape_gpu==null

func capture(tick: int) -> void:
	var index_before := raw_index.size()
	await snapshot("tick_%04d"%tick)
	samples.append(raw_index[index_before])
	root.get_texture().get_image().save_png(output.path_join("tick_%04d.png"%tick))

func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--mode="): mode=arg.trim_prefix("--mode=")
		if arg.begins_with("--ticks="): target_ticks=int(arg.trim_prefix("--ticks="))
	if mode not in ["baseline","compact","cohesion"] or target_ticks not in [5,400,900]:
		_check("retention_arguments",false); _finish(); quit(1); return
	root.size=Vector2i(1280,720)
	preview=load(_retention_scene_path()).instantiate()
	preview.retention_mode=mode; preview.playing=false; preview.visual_time_s=0.0
	preview.capture_substep_trace=true
	preview.sand_cohesion_yield_height_m=0.9 if mode=="cohesion" else 0.0
	root.add_child(preview)
	var deadline := Time.get_ticks_msec()+90000
	while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_msec()<deadline: await process_frame
	_check("retention_ready",preview.ready_for_ticks,preview.last_error)
	if not preview.ready_for_ticks: _finish(); quit(1); return
	await capture(0)
	var start_us := Time.get_ticks_usec()
	for tick in range(1,target_ticks+1):
		await _ticks(1)
		if not preview.last_error.is_empty(): break
		if tick%150==0 or tick==target_ticks:
			await capture(tick)
			print("RETENTION_PROGRESS mode=",mode," tick=",tick," of=",target_ticks)
	_check("retention_target_tick",preview.completed_ticks==target_ticks and preview.last_error.is_empty(),preview.last_error)
	var consumed: Array=preview.material_coupler.actual_pushes.duplicate(true)
	var consumed_ok := not consumed.is_empty()
	for row in consumed:
		consumed_ok=consumed_ok and row.values.size()==8 and is_equal_approx(row.values[7],preview.sand_cohesion_yield_height_m) and row.values[1]==0.125
	_check("actual_material_push_observed",consumed_ok,consumed)
	var file := FileAccess.open(output.path_join("retention_evidence.json"),FileAccess.WRITE)
	var substeps := []
	for row in preview.capture_substep_rows: substeps.append([row.x,row.y,row.z])
	file.store_string(JSON.stringify({"mode":mode,"target_ticks":target_ticks,"completed_ticks":preview.completed_ticks,"simulation_delta_s":1.0/30.0,"samples":samples,"rois":Fixture.ROIS,"consumed_slope_pushes":consumed,"staged_shader_hashes":preview.material_coupler.staged_shader_hashes,"source_signature":preview.source_signature,"profile_sha256":preview.requested_render_profile_sha256,"enable_erosion":preview.enable_erosion,"cohesion_yield_height_m":preview.sand_cohesion_yield_height_m,"elapsed_us":Time.get_ticks_usec()-start_us,"substeps":substeps,"cfl_inputs":preview.cfl_inputs,"scope":"ordinary material controls; 400 ticks is diagnostic only, 900 ticks is 30s; not selected molded acceptance"},"\t")); file.close()
	await preview.shutdown(); _check("retention_pool_released",_retention_resources_released())
	_finish(); var ok := true
	for row in checks: ok=ok and row.pass
	quit(0 if ok else 1)

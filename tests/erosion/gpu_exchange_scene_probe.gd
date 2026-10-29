extends "res://tests/water_material_natural/rdc_main_smoke.gd"

func _settled() -> void:
	var deadline := Time.get_ticks_msec()+30000
	while (preview.busy or preview.input_running or preview.collision_proxy.staging_texture.is_valid() or not preview.collision_proxy.pending_revisions.is_empty() or preview.collision_proxy.has_prepare_in_flight()) and Time.get_ticks_msec()<deadline:
		await process_frame
	_check("collision_settled",Time.get_ticks_msec()<deadline)

func _sand_total(state: Dictionary) -> float:
	var total := 0.0
	for field in ["sand","sediment"]:
		for value in state[field].to_float32_array(): total+=value*0.015625
	return total

func _run() -> void:
	if output.is_empty(): output="res://test_output/erosion_capacity_20261016/scenes"
	DirAccess.make_dir_recursive_absolute(output)
	root.size=Vector2i(1280,720)
	for path in ["res://scenes/main.tscn","res://scenes/playable/test1_capture.tscn","res://scenes/playable/test1_backwash.tscn"]:
		preview=load(path).instantiate(); preview.playing=false; root.add_child(preview)
		var deadline:=Time.get_ticks_msec()+90000
		while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_msec()<deadline: await process_frame
		_check(path+"_ready",preview.ready_for_ticks,preview.last_error)
		if not preview.ready_for_ticks: _finish(); quit(1); return
		await _settled()
		var initial:=await _snapshot()
		var total:=_sand_total(initial)
		_check("production_exchange_profile",preview.sediment_coupler.capacity_per_speed_s==0.003 and preview.enable_erosion)
		for interval in 3:
			await _ticks(30)
			await _settled()
			var state:=await _snapshot()
			var invalid:=0
			for field in ["sand","sediment","water"]:
				for value in state[field].to_float32_array():
					if not is_finite(value) or value<0.0: invalid+=1
			_check(path+"_interval_"+str(interval),invalid==0 and preview.last_error.is_empty() and absf(_sand_total(state)-total)<0.001,
				{"tick":preview.completed_ticks,"invalid":invalid,"sand_error_m3":_sand_total(state)-total,"error":preview.last_error})
			_check("rock_unchanged",initial.rock==state.rock)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join(preview.scene_key+"_tick90.png"))
		var before:=await _snapshot()
		var checkpoint:=output.path_join(preview.scene_key+".sandcp")
		var error: StringName=await preview.save_gpu_checkpoint(checkpoint)
		_check("save_"+preview.scene_key,error.is_empty(),String(error))
		if error.is_empty():
			await _ticks(3); await _settled()
			error=await preview.restore_gpu_checkpoint(checkpoint)
			_check("restore_"+preview.scene_key,error.is_empty(),String(error))
			var restored:=await _snapshot()
			_check("restore_all10_exact",before==restored)
			await _ticks(5); await _settled()
			_check("continue_after_restore",preview.last_error.is_empty(),preview.last_error)
		var tick: int=preview.completed_ticks
		for frame in 8: await process_frame
		_check("paused_clock",preview.completed_ticks==tick)
		await preview.get_node("Interface/PerformancePanel").stop_sampling()
		await preview.shutdown(); _check("shutdown",preview.gpu_release_done)
		preview.queue_free(); await process_frame
	_finish()
	var passed:=true
	for row in checks: passed=passed and row.pass
	quit(0 if passed else 1)

extends "res://tests/shape_brushes/stage_cost_probe.gd"

func _run() -> void:
	root.size=Vector2i(1280,720);pair_fields=27
	preview=load("res://scenes/main.tscn").instantiate();preview.playing=false;root.add_child(preview);current_scene=preview
	var deadline:=Time.get_ticks_msec()+90000
	while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	_check("memory_ready",preview.ready_for_ticks,preview.last_error)
	if not preview.ready_for_ticks:_finish();quit(1);return
	await preview.get_node("Interface/PerformancePanel").stop_sampling()
	mark_memory("initial")
	var rows:=[]
	for index in 10:
		var path:=output.path_join("memory_%d.scp" % index)
		var error:StringName=await preview.save_gpu_checkpoint(path)
		_check("memory_save_%d" % index,error.is_empty(),String(error))
		for frame in 4:await process_frame
		var count:int=preview.checkpoints.size()
		_check("memory_history_bound_%d" % index,count==mini(index+1,8),count)
		rows.append({"index":index,"history_count":count,"memory_static":Performance.get_monitor(Performance.MEMORY_STATIC),"objects":Performance.get_monitor(Performance.OBJECT_COUNT),"capture_raw_bytes":retained_bytes(preview.capture_raw),"capture_original_bytes":retained_bytes(preview.capture_original),"checkpoint_capture_empty":preview.checkpoint_capture.is_empty()})
	mark_memory("ten_saves_history_capped")
	# Diagnostic intervention after all writes; it preserves every disk checkpoint.
	# Production keeps these eight intentional rewind snapshots.
	preview.checkpoints.clear();preview.capture_raw.clear();preview.capture_original.clear()
	for frame in 10:await process_frame
	mark_memory("diagnostic_history_and_capture_clear")
	var before_shutdown:float=Performance.get_monitor(Performance.MEMORY_STATIC)
	var decrease:float=float(rows[-1].memory_static)-before_shutdown
	_check("memory_retained_buffers_explain_growth",decrease>180000000,decrease)
	# Last three writes replace snapshots at the cap; ignore tiny metadata noise.
	var last_min:float=minf(rows[7].memory_static,minf(rows[8].memory_static,rows[9].memory_static))
	var last_max:float=maxf(rows[7].memory_static,maxf(rows[8].memory_static,rows[9].memory_static))
	_check("memory_capped_plateau",last_max-last_min<1000000,{"spread_bytes":last_max-last_min,"scope":"only capped checkpoint history, not a global leak threshold"})
	var file:=FileAccess.open(output.path_join("checkpoint_memory.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"round":3,"rows":rows,"memory_phases":memory_phases,"diagnostic_decrease_bytes":decrease,"cap_spread_bytes":last_max-last_min,"scope":"Ten actual disk saves; production eight-snapshot cap preserved, diagnostic clear after writes attributes retained memory; no physics or acceptance tolerance change"},"\t"));file.close()
	await preview.shutdown();_check("memory_release",preview.gpu_release_done and preview.preview_query==null)
	preview.queue_free();await process_frame;_finish()
	var passed:=true
	for row in checks:passed=passed and row.pass
	quit(0 if passed else 1)

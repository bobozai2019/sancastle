extends "res://tests/shape_brushes/gpu_framework_probe.gd"

var close_done := false
var close_observed := false
var held_helper

func close_baseline() -> void:
	var deadline := Time.get_ticks_msec()+30000
	while not preview.shape_gpu.begin_pending and Time.get_ticks_msec()<deadline: await process_frame
	close_observed=preview.shape_gpu.begin_pending and preview.solver.receipt_pending
	held_helper=preview.shape_gpu
	await preview.shutdown(); close_done=true

func close_receipt() -> void:
	close_observed=preview.gpu_busy and preview.solver.publication_pending and not preview.gpu_settled
	held_helper=preview.shape_gpu
	await preview.shutdown(); close_done=true

func _run() -> void:
	root.size=Vector2i(1280,720)
	for phase in ["baseline","receipt"]:
		preview=load("res://tests/shape_brushes/brush_lab.tscn").instantiate()
		preview.brush_fixture="dry_slope"; preview.playing=false; root.add_child(preview)
		var deadline := Time.get_ticks_msec()+90000
		while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_msec()<deadline: await process_frame
		_check(phase+"_ready",preview.ready_for_ticks)
		if not preview.ready_for_ticks: _finish(); quit(1); return
		close_done=false; close_observed=false
		if phase=="baseline":
			call_deferred("close_baseline")
			var error: StringName=await preview.begin_shape_stroke(300)
			_check("baseline_begin_terminates",error.is_empty() or error==&"invalid_baseline",String(error))
		else:
			var error: StringName=await preview.begin_shape_stroke(301)
			_check("receipt_baseline",error.is_empty())
			preview.hold_shape_receipt=true
			_check("receipt_command_admitted",preview.input_scheduler.submit(command(Vector2.ZERO,Vector2(0.125,0))).is_empty())
			deadline=Time.get_ticks_msec()+30000
			while preview.held_shape_receipts.is_empty() and preview.last_error.is_empty() and Time.get_ticks_msec()<deadline: await process_frame
			_check("receipt_arrived",not preview.held_shape_receipts.is_empty())
			call_deferred("close_receipt")
			await process_frame
			_check("shutdown_waits_actual_receipt_owner",preview.shutdown_requested and not close_done and preview.shape_gpu!=null)
			preview.release_shape_receipts()
		deadline=Time.get_ticks_msec()+30000
		while not close_done and Time.get_ticks_msec()<deadline: await process_frame
		_check(phase+"_close_observed_live_lock",close_observed)
		_check(phase+"_close_terminates",close_done and preview.gpu_release_done and preview.last_error.is_empty(),preview.last_error)
		_check(phase+"_pool_released_after_callbacks",held_helper!=null and held_helper.rd==null and held_helper.owned.is_empty() and preview.shape_gpu==null)
		if phase=="receipt":
			_check("close_settles_accepted_command_once",preview.gpu_prefix.size()==1 and preview.shadow_domain.sand_source_m3==preview.gpu_prefix[0].result.added_m3 and preview.command_queue.applied_log.size()==1)
		preview.queue_free(); preview=null
		for i in 4: await process_frame
	_finish(); var ok := true
	for row in checks: ok=ok and row.pass
	quit(0 if ok else 1)

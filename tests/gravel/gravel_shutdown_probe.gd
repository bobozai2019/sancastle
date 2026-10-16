extends "res://tests/gravel/gravel_lifecycle_probe.gd"

var restore_done := false
var restore_result: StringName = &""

func _restore_while_closing(checkpoint: Dictionary) -> void:
	restore_result=await preview.restore_gpu_checkpoint_data(checkpoint)
	restore_done=true

func _boot() -> bool:
	preview=load("res://scenes/main.tscn").instantiate()
	preview.playing=false
	root.add_child(preview)
	var deadline := Time.get_ticks_msec()+120000
	while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_msec()<deadline: await process_frame
	return preview.ready_for_ticks

func _run() -> void:
	if output.is_empty(): output="res://test_output/gpu_gravel/shutdown_"+str(Time.get_unix_time_from_system()).replace(".","_")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	_check("readback_scene_ready",await _boot())
	var old_field=preview.gravel_field
	gravel_data.clear()
	RenderingServer.call_on_render_thread(_read_gravel)
	await preview.shutdown()
	await _frames()
	_check("shutdown_drains_diagnostic_capture",preview.gpu_release_done and old_field.pending==0 and old_field.rd==null and gravel_data.size()==2)
	preview.queue_free()
	await _frames()
	_check("candidate_scene_ready",await _boot())
	await _ticks(2)
	await _settle()
	var path := output.path_join("checkpoint.bin")
	var error: StringName=await preview.save_gpu_checkpoint(path)
	_check("candidate_checkpoint",error.is_empty(),String(error))
	var checkpoint: Dictionary=Store.load(path).checkpoint
	preview.observe_beach_restore=true
	_restore_while_closing.call_deferred(checkpoint)
	await preview.beach_restore_submitted
	var candidate=preview.beach_restore_candidate
	_check("restore_candidate_in_flight",candidate!=null and preview.beach_restore_running)
	await preview.shutdown()
	_check("shutdown_waits_candidate_discard",restore_done and restore_result==&"closed_before_restore_commit" and candidate.released and candidate.pending==0 and candidate.gravel_field==null and preview.gravel_field==null and preview.gravel_capture_callbacks==0,{"restore_error":String(restore_result),"candidate_released":candidate.released,"pending":candidate.pending,"active_rd_released":preview.solver.rd==null})
	_finish()
	print("GRAVEL_SHUTDOWN_OUTPUT ",output)
	var passed := true
	for row in checks: passed=passed and row.pass
	quit(0 if passed else 1)

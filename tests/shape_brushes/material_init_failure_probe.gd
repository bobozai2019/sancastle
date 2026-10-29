extends "res://tests/water_material_natural/rdc_main_smoke.gd"

func _run() -> void:
	root.size=Vector2i(1280,720)
	for mode in ["wrong_type","short","negative","overflow","nan"]:
		preview=load("res://tests/shape_brushes/invalid_material_lab.tscn").instantiate()
		preview.invalid_mode=mode;root.add_child(preview)
		var deadline:=Time.get_ticks_msec()+90000
		while preview.last_error.is_empty() and not preview.ready_for_ticks and Time.get_ticks_msec()<deadline: await process_frame
		_check(mode+"_initialization_error_reported",preview.last_error=="GPU shallow solver initialization failed",preview.last_error)
		_check(mode+"_never_ready_or_ticked",not preview.ready_for_ticks and preview.completed_ticks==0 and not preview.shape_backend_ready)
		_check(mode+"_no_solver_or_helper_rd_allocation",preview.solver!=null and preview.solver.rd==null and preview.solver.textures.is_empty() and preview.shape_gpu==null)
		_check(mode+"_no_material_transaction_allocation",preview.solver.legacy_material_transaction==null)
		await preview.shutdown()
		_check(mode+"_partial_scene_shutdown_finishes",preview.gpu_release_done)
		preview.queue_free();await process_frame
	_finish();var passed:=true
	for row in checks: passed=passed and row.pass
	quit(0 if passed else 1)

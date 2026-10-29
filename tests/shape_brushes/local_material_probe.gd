extends "res://tests/shape_brushes/retention_probe.gd"

var selector_samples := []
var selector_ready := false

func selector_result(bytes: PackedByteArray, tick: int) -> void:
	call_deferred("selector_done",bytes,tick)
func selector_done(bytes: PackedByteArray, tick: int) -> void:
	selector_samples.append({"tick":tick,"groups":Array(bytes.to_int32_array())}); selector_ready=true
func selector_read(tick: int) -> void:
	preview.solver.rd.buffer_get_data_async(preview.material_coupler.support_indirect,selector_result.bind(tick))

func capture(tick: int) -> void:
	await super.capture(tick)
	if tick>0 and preview.solver.mold_field_ever_used:
		selector_ready=false; RenderingServer.call_on_render_thread(selector_read.bind(tick))
		while not selector_ready: await process_frame

func read_all() -> void:
	super.read_all()
	for slot in 2: preview.solver.rd.texture_get_data_async(preview.solver.textures.mold_support[slot],0,_record.bind("mold_support_"+str(slot)))

func _run() -> void:
	mode="local"; target_ticks=900; pair_fields=27
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--mode="): mode=arg.trim_prefix("--mode=")
		if arg.begins_with("--ticks="): target_ticks=int(arg.trim_prefix("--ticks="))
	if mode not in ["local","zero_support"] or target_ticks not in [5,400,900]: _check("local_arguments",false); _finish(); quit(1); return
	root.size=Vector2i(1280,720)
	preview=load("res://tests/shape_brushes/local_retention_lab.tscn").instantiate()
	preview.use_local_support=mode=="local"; preview.playing=false; preview.visual_time_s=0.0
	preview.capture_substep_trace=true
	preview.sand_cohesion_yield_height_m=0.0; root.add_child(preview)
	var deadline := Time.get_ticks_msec()+90000
	while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_msec()<deadline: await process_frame
	_check("local_material_ready",preview.ready_for_ticks,preview.last_error)
	if not preview.ready_for_ticks: _finish(); quit(1); return
	var material=preview.material_coupler
	await capture(0)
	for tick in range(1,target_ticks+1):
		await _ticks(1)
		if not preview.last_error.is_empty(): break
		if tick%150==0 or tick==target_ticks:
			await capture(tick); print("LOCAL_MATERIAL_PROGRESS mode=",mode," tick=",tick)
	_check("local_target_ticks",preview.completed_ticks==target_ticks and preview.last_error.is_empty(),preview.last_error)
	var pushes: Array=material.local_pushes.duplicate(true)
	var valid := not pushes.is_empty()
	for row in pushes:
		valid=valid and row.values[7]==0.0
		if mode=="local": valid=valid and row.values.size()==12 and is_equal_approx(row.values[8],0.9) and row.values[9]==0.125
		else: valid=valid and row.values.size()==8 and row.get("branch")=="ordinary_direct"
	_check("local_actual_pushes",valid,pushes)
	var file := FileAccess.open(output.path_join("retention_evidence.json"),FileAccess.WRITE)
	var substeps := []
	for row in preview.capture_substep_rows: substeps.append([row.x,row.y,row.z])
	file.store_string(JSON.stringify({"mode":mode,"target_ticks":target_ticks,"completed_ticks":preview.completed_ticks,"samples":samples,"rois":Fixture.ROIS,"simulation_delta_s":1.0/30.0,"consumed_slope_pushes":pushes,"staged_shader_hashes":material.staged_shader_hashes,"ordinary_shader_hash":material.ordinary_shader_hash,"selector_samples":selector_samples,"material_profile":material.profile,"material_profile_sha256":material.profile_sha256,"source_signature":preview.source_signature,"cohesion_yield_height_m":0.0,"substeps":substeps,"cfl_inputs":preview.cfl_inputs,"scope":"local simulation prototype; 400 ticks diagnostic only; brush/legacy transactions, damage and native v2 pending"},"\t")); file.close()
	var save_error: StringName=await preview.save_gpu_checkpoint(output.path_join("unsafe_native.scp"))
	_check("nonzero_support_old_checkpoint_refused",save_error==&"brush_native_checkpoint_not_implemented" if mode=="local" else save_error.is_empty(),String(save_error))
	if mode=="local":
		var request_error: StringName=preview.request_checkpoint_save(output.path_join("unsafe_request.scp"))
		_check("nonzero_support_old_request_checkpoint_refused",request_error==&"brush_native_checkpoint_not_implemented" and not FileAccess.file_exists(output.path_join("unsafe_request.scp")),String(request_error))
	await preview.shutdown()
	_check("local_material_released",preview.gpu_release_done and not material.support_result.is_valid() and not material.support_set.is_valid() and not material.support_pipeline.is_valid())
	_finish(); var ok := true
	for row in checks: ok=ok and row.pass
	quit(0 if ok else 1)

extends "res://tests/shape_brushes/gpu_framework_probe.gd"

var fault_mode := "transport"
var seed_values := PackedFloat32Array()
var candidate_cells := PackedByteArray()
var candidate_receipt := PackedByteArray()
var backups := {}

func read_candidate() -> void:
	preview.solver.rd.buffer_get_data_async(preview.shape_gpu.buffers.cells,receive_cells)
	preview.solver.rd.buffer_get_data_async(preview.shape_gpu.buffers.receipt,receive_receipt)
	for name in ["backup_sand0","backup_sand1","backup_coverage"]:
		preview.solver.rd.texture_get_data_async(preview.shape_gpu.images[name],0,receive_backup.bind(name))

func receive_backup(bytes: PackedByteArray, name: String) -> void: call_deferred("backup_done",bytes,name)
func backup_done(bytes: PackedByteArray, name: String) -> void: backups[name]=bytes

func receive_cells(bytes: PackedByteArray) -> void: call_deferred("cells_done",bytes)
func receive_receipt(bytes: PackedByteArray) -> void: call_deferred("receipt_done",bytes)
func cells_done(bytes: PackedByteArray) -> void: candidate_cells=bytes
func receipt_done(bytes: PackedByteArray) -> void: candidate_receipt=bytes

func seed_spare() -> void:
	var source: RID = preview.solver._create_texture(RenderingDevice.DATA_FORMAT_R32_SFLOAT,seed_values.to_byte_array())
	var ok: bool = preview.shape_gpu._copy(source,preview.solver.textures.sand[1-preview.solver.current_index])
	preview.solver.rd.free_rid(source)
	call_deferred("locked_done",ok)

func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--fault="): fault_mode=arg.trim_prefix("--fault=")
	root.size=Vector2i(1280,720)
	preview=load("res://tests/shape_brushes/brush_lab.tscn").instantiate()
	preview.brush_fixture="dry_slope"; root.add_child(preview)
	var deadline := Time.get_ticks_msec()+90000
	while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_msec()<deadline: await process_frame
	_check("fault_backend_ready",preview.ready_for_ticks,preview.last_error)
	if not preview.ready_for_ticks: _finish(); quit(1); return
	seed_values=preview.domain.sand.duplicate()
	seed_values[128*256+128]=0.25
	direct_result=null; RenderingServer.call_on_render_thread(seed_spare)
	while direct_result==null: await process_frame
	_check("distinct_spare_preimage_initialized",direct_result==true)
	var begin_error: StringName=await preview.begin_shape_stroke(91)
	_check("fault_baseline_ready",begin_error.is_empty())
	var before := await snapshot("fault_before")
	_check("spare_is_distinct_at_edited_cell",before.spare_sand.to_float32_array()[128*256+128]==0.25 and before.sand.to_float32_array()[128*256+128]==1.0)
	if fault_mode=="transport": preview.shape_gpu.inject_transport_failure_once=true
	else: preview.shape_gpu.inject_wrong_receipt_once=true
	var error: StringName=preview.input_scheduler.submit(command(Vector2.ZERO,Vector2(0.125,0)))
	_check("fault_command_admitted",error.is_empty())
	deadline=Time.get_ticks_msec()+30000
	while (not preview.command_queue.pending.is_empty() or preview.busy or preview.input_running) and Time.get_ticks_msec()<deadline: await process_frame
	_check("fault_owner_terminates",not preview.busy and not preview.input_running and preview.command_queue.pending.is_empty(),preview.last_error)
	var after := await snapshot("fault_after")
	_check("injection_consumed",not preview.shape_gpu.inject_transport_failure_once if fault_mode=="transport" else not preview.shape_gpu.inject_wrong_receipt_once)
	RenderingServer.call_on_render_thread(read_candidate)
	deadline=Time.get_ticks_msec()+30000
	while (candidate_cells.is_empty() or candidate_receipt.is_empty() or backups.size()!=3) and Time.get_ticks_msec()<deadline: await process_frame
	_check("validated_positive_candidate_before_injected_failure",candidate_cells.size()==4194304 and candidate_receipt.size()==256 and candidate_receipt.decode_u32(12)==1 and candidate_cells.decode_float((128*256+128)*64+4)>candidate_cells.decode_float((128*256+128)*64))
	for item in [["candidate_cells",candidate_cells],["candidate_receipt",candidate_receipt]]:
		var file := FileAccess.open(output.path_join(item[0]+".bin"),FileAccess.WRITE); file.store_buffer(item[1]); file.close()
	for name in backups:
		var file := FileAccess.open(output.path_join(name+".bin"),FileAccess.WRITE); file.store_buffer(backups[name]); file.close()
	_check("transport_or_identity_error_reported",preview.last_error==("shape GPU dispatch failed" if fault_mode=="transport" else "shape GPU receipt mismatch"),preview.last_error)
	_check("fault_rolls_back_current_spare_coverage_and_history",exact(before,after))
	_check("fault_does_not_settle_or_publish",preview.shadow_domain.sand_source_m3==0.0 and preview.shadow_domain.sand_sink_m3==0.0 and preview.solver.state_revision==0 and preview.gpu_prefix.is_empty() and not preview.solver.receipt_pending and not preview.solver.publication_pending)
	var record := FileAccess.open(output.path_join("fault_evidence.json"),FileAccess.WRITE)
	record.store_string(JSON.stringify({"fault":fault_mode,"raw_index":raw_index,"statistics":preview.shape_gpu.statistics(),"terminal":preview.input_scheduler.terminal,"source_signature":preview.source_signature,"expected_scene_error":preview.last_error,"scope":"GPU post-commit transport/identity rollback, with different input spare"},"\t")); record.close()
	await preview.shutdown()
	_check("fault_shutdown_releases_resources",preview.gpu_release_done and preview.shape_gpu==null)
	_finish(); var passed := true
	for row in checks: passed=passed and row.pass
	quit(0 if passed else 1)

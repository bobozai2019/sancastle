extends "res://tests/edit_validation/beach_save_boundary_probe.gd"

var raw_expected := {}
var raw_observed := {}
var native_done := false

func _write(ok: bool, error: String="") -> void:
	var file:=FileAccess.open(output.path_join("beach_undo_failure_probe.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass":ok,"rows":rows,"error":error,"scope":"actual undo memory checkpoint request failure, unchanged full native state and owned close"},"\t"));file.close()

func _read_native() -> void:
	for field in Native.FIELD_BYTES:
		preview.solver.rd.texture_get_data_async(preview.solver.current_texture(field),0,_on_native.bind("fields:"+field))
	for field in ["sand","water","momentum_x","momentum_z","sediment","wetness","compaction","flux"]:
		preview.solver.rd.texture_get_data_async(preview.solver.textures[field][1-preview.solver.current_index],0,_on_native.bind("spare:"+field))
	for index in 2:
		preview.solver.rd.texture_get_data_async(preview.foam_field.textures[index],0,_on_native.bind("foam_%d"%index))
		preview.solver.rd.texture_get_data_async(preview.foam_field.bed_textures[index],0,_on_native.bind("bed_%d"%index))
	preview.solver.rd.texture_get_data_async(preview.local_front_field.texture,0,_on_native.bind("front"))

func _on_native(bytes: PackedByteArray, key: String) -> void: call_deferred("_native_record",bytes,key)
func _native_record(bytes: PackedByteArray, key: String) -> void:
	raw_observed[key]=bytes
	if raw_observed.size()==23: native_done=true

func _run() -> void:
	root.size=Vector2i(1920,1080);DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	preview=load("res://tests/edit_validation/edit_beach_undo_fault_lab.tscn").instantiate();preview.playing=false;root.add_child(preview)
	while not preview.ready_for_ticks and preview.last_error.is_empty(): await process_frame
	if not preview.last_error.is_empty():
		preview.set_process(false);_write(false,preview.last_error);finished=true;quit(1);return
	await _ticks(17)
	preview.water_policy=3;preview.signed_speed_m_s=0.25
	var receipt: Dictionary=await preview.apply_gpu_command(_command(9007199254741103,0.01))
	var saved: StringName=await preview.save_gpu_checkpoint(output.path_join("before.scp"))
	var before: Dictionary=Store.load(output.path_join("before.scp")).checkpoint
	for group in ["fields","spare"]:
		for field in before.gpu_beach_native[group]: raw_expected[group+":"+field]=before.gpu_beach_native[group][field]
	for field in ["foam_0","foam_1","bed_0","bed_1"]: raw_expected[field]=before.gpu_beach_native.foam[field]
	raw_expected.front=before.local_front_history.to_byte_array()
	var owned=preview.solver;var generation_before: int=preview.generation;var stock_before: float=preview.domain.tool_inventory_m3
	var prefix_before: Array=preview.gpu_prefix.duplicate(true)
	preview.capture_request_count=0;preview.fail_capture_request=27
	var result: Dictionary=await preview.undo_latest()
	RenderingServer.call_on_render_thread(_read_native)
	while not native_done: await process_frame
	rows.append({"case":"undo_request_failure_retains_all_23_native_fields","pass":receipt.get("status")==1 and saved==&"" and result.get("error")=="capture_failed" and raw_observed==raw_expected and preview.domain.tool_inventory_m3==stock_before and preview.gpu_prefix==prefix_before and preview.generation==generation_before and preview.solver==owned,"result":result,"capture_requests":preview.capture_request_count})
	rows.append({"case":"failed_memory_capture_is_drained_and_quarantined","pass":preview.capture_request_count==27 and preview.pending_beach_native_readbacks==0 and not preview.checkpoint_capture_pending and preview.checkpoint_capture.is_empty() and not preview.gpu_save_running and not preview.undo_running and not preview.ready_for_ticks and not preview.input_scheduler.accepting and preview.full_history.records.size()==1 and preview.redo_records.is_empty()})
	await preview.shutdown()
	rows.append({"case":"failed_undo_actual_close_releases_history_owner","pass":owned.rd==null and preview.collision_proxy.rd==null and preview.gpu_release_done and preview.full_history.bytes_owned==0 and preview.gpu_release_us>=preview.beach_native_callback_us})
	var ok:=true
	for row in rows: ok=ok and row.pass
	_write(ok,preview.last_error);preview.queue_free();for i in 4: await process_frame
	finished=true;print("BEACH_UNDO_FAILURE_COMPLETE pass=%s"%str(ok));quit(0 if ok else 1)

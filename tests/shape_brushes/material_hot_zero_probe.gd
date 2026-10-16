extends "res://tests/shape_brushes/material_edit_probe.gd"

var selector := PackedByteArray()
func selector_result(bytes: PackedByteArray) -> void: call_deferred("selector_done",bytes)
func selector_done(bytes: PackedByteArray) -> void: selector=bytes
func read_selector() -> void: preview.solver.rd.buffer_get_data_async(preview.material_coupler.support_indirect,selector_result)

func _run() -> void:
	root.size=Vector2i(1280,720);pair_fields=27
	await open_material_lab()
	if not preview.ready_for_ticks: _finish();quit(1);return
	var formed_result:=await submit(molded_command())
	_check("hot_zero_formed",formed_result.get("status")==1 and preview.solver.mold_field_ever_used)
	await preview.end_shape_stroke()
	await snapshot("formed")
	var cut:=legacy_command(preview.command_queue.last_command_id+1,&"remove_sand")
	cut.radius_m=2.0;cut.amount_m3=100.0
	var error: StringName=preview.input_scheduler.submit(cut)
	await settle()
	var cut_result: Dictionary=preview.input_scheduler.terminal[-1].result
	_check("hot_zero_complete_cut_accepted",error.is_empty() and cut_result.get("status")==1,cut_result)
	var state:=await snapshot("hot_zero_after_cut")
	var zeros:=PackedByteArray();zeros.resize(65536*8);zeros.fill(0)
	_check("hot_zero_both_slots_canonical",state.mold_support_0==zeros and state.mold_support_1==zeros and preview.solver.mold_field_ever_used)
	var source_before: float=preview.shadow_domain.sand_source_m3;var sink_before: float=preview.shadow_domain.sand_sink_m3
	await _ticks(5)
	state=await snapshot("hot_zero_after_ticks")
	_check("hot_zero_remains_canonical",state.mold_support_0==zeros and state.mold_support_1==zeros and preview.solver.mold_field_ever_used)
	RenderingServer.call_on_render_thread(read_selector)
	var deadline:=Time.get_ticks_msec()+30000
	while selector.is_empty() and Time.get_ticks_msec()<deadline: await process_frame
	_check("hot_zero_ordinary_dispatch_selected",selector.to_int32_array()==PackedInt32Array([32,32,1,0,32,1]),Array(selector.to_int32_array()))
	_check("hot_zero_no_implicit_sand_source_sink",source_before==preview.shadow_domain.sand_source_m3 and sink_before==preview.shadow_domain.sand_sink_m3)
	var record:=preload("res://scripts/simulation/brushes/brush_material_state_codec.gd").make_record(state.mold_support_0,state.mold_support_1,true,preview.material_coupler.profile_sha256)
	_check("hot_zero_actual_subrecord_valid",preload("res://scripts/simulation/brushes/brush_material_state_codec.gd").validate(record,state.sand,state.spare_sand,preview.material_coupler.profile_sha256).is_empty())
	_check("hot_zero_old_save_still_refused",preview.request_checkpoint_save(output.path_join("unsafe_hot_zero.scp"))==&"brush_native_checkpoint_not_implemented")
	var file:=FileAccess.open(output.path_join("hot_zero_evidence.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"raw_index":raw_index,"commands":[cut],"receipts":[formed_result,cut_result],"selector_groups":Array(selector.to_int32_array()),"ever_used":preview.solver.mold_field_ever_used,"metadata":metadata(),"profile_sha256":preview.material_coupler.profile_sha256,"source_signature":preview.source_signature,"scope":"Actual hot-zero initialization/dispatch/subrecord test, five ticks only; no long strict or disk restore acceptance."},"\t"));file.close()
	var tx=preview.shape_gpu.material_transaction;var legacy_tx=preview.solver.legacy_material_transaction
	await preview.shutdown();_check("hot_zero_resources_released",preview.gpu_release_done and tx.rd==null and legacy_tx.rd==null)
	_finish();var passed:=true
	for row in checks: passed=passed and row.pass
	quit(0 if passed else 1)

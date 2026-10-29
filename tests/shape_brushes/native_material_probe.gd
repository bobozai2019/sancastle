extends "res://tests/shape_brushes/material_edit_probe.gd"

var retained_bundle
var retained_helper

func retain_native_candidate() -> void:
	retained_bundle=preview.beach_restore_candidate
	retained_helper=preview._restore_shape_candidate

func _run() -> void:
	root.size=Vector2i(1280,720);pair_fields=27
	preview=load("res://tests/shape_brushes/native_material_lab.tscn").instantiate();root.add_child(preview)
	var deadline:=Time.get_ticks_msec()+90000
	while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_msec()<deadline: await process_frame
	_check("native_material_ready",preview.ready_for_ticks and preview.solver.mold_field_ever_used,preview.last_error)
	if not preview.ready_for_ticks: _finish();quit(1);return
	await _ticks(2)
	var anchor:=await snapshot("native_material_anchor")
	var path:=output.path_join("material_v2.scp")
	var error: StringName=await preview.save_gpu_checkpoint(path)
	_check("native_v2_material_disk_save",error.is_empty(),String(error))
	if not error.is_empty():await preview.shutdown();_finish();quit(1);return
	var loaded: Dictionary=preview.Store.load(path)
	_check("native_v2_material_disk_load",loaded.error.is_empty(),String(loaded.error))
	var checkpoint: Dictionary=loaded.checkpoint
	_check("native_v2_complete_header",checkpoint.gpu_beach_native.version==2 and checkpoint.gpu_beach_native.material.ever_used and checkpoint.gpu_beach_edit.version in [2,3])
	_check("native_v2_actual_raw_slots",checkpoint.gpu_beach_native.material.current_support==anchor.mold_support_0 and checkpoint.gpu_beach_native.material.spare_support==anchor.mold_support_1)
	_check("native_v2_profile_and_sources_identity",checkpoint.gpu_beach_native.material.profile_sha256==preview.material_coupler.profile_sha256 and checkpoint.gpu_beach_edit.configuration.sources.has("res://assets/brushes/protocol_v2.json") and checkpoint.gpu_beach_edit.configuration.brush_native_material_enabled)
	await _ticks(2);var before:=await snapshot("native_before_rejections");var generation_before: int=preview.generation
	var bad: Dictionary=checkpoint.duplicate(true);bad.gpu_beach_native.material.profile_sha256="0".repeat(64)
	error=await preview.restore_gpu_checkpoint_data(bad)
	_check("native_v2_wrong_profile_rejected",error==&"material_profile_mismatch",String(error))
	bad=checkpoint.duplicate(true);bad.gpu_beach_native.material.erase("spare_support")
	error=await preview.restore_gpu_checkpoint_data(bad)
	_check("native_v2_missing_slot_rejected",error==&"invalid_material_header",String(error))
	preview.enable_brush_native_material=false
	error=await preview.restore_gpu_checkpoint_data(checkpoint)
	_check("native_v2_disabled_consumer_rejected",error==&"unsupported_native_version",String(error))
	preview.enable_brush_native_material=true
	var after:=await snapshot("native_after_rejections")
	_check("native_v2_invalid_preserves_scene",exact(before,after) and preview.generation==generation_before)
	preview.inject_beach_restore_failure=true;preview.observe_beach_restore=true
	preview.beach_restore_submitted.connect(retain_native_candidate,CONNECT_ONE_SHOT)
	error=await preview.restore_gpu_checkpoint_data(checkpoint)
	preview.observe_beach_restore=false
	_check("native_v2_candidate_injected_failure",error==&"candidate_injected_failure",String(error))
	after=await snapshot("native_after_failed_candidate")
	_check("native_v2_failed_candidate_atomic",exact(before,after) and preview.generation==generation_before)
	_check("native_v2_failed_candidate_material_released",retained_bundle!=null and retained_bundle.released and retained_bundle.solver.rd==null and retained_bundle.solver.legacy_material_transaction==null and retained_helper!=null and retained_helper.material_transaction==null)
	error=await preview.restore_gpu_checkpoint(path)
	_check("native_v2_material_restore_committed",error.is_empty() and preview.generation==generation_before+1 and preview.solver.mold_field_ever_used,String(error))
	after=await snapshot("native_material_restored")
	_check("native_v2_material_27_raw_exact",exact(anchor,after))
	_check("native_v2_restored_stroke_idle",preview.shape_stroke_id==0 and not preview.shape_gpu.active and preview._restore_shape_candidate==null)
	var file:=FileAccess.open(output.path_join("native_material_evidence.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"raw_index":raw_index,"native_version":2,"material_version":1,"source_signature":preview.source_signature,"restore_verifications":preview.beach_restore_verifications,"scope":"Initialized nonzero materials and original command prefix native v2 disk/raw/failure lifecycle. Schema2 prefix/strict continuation still pending."},"\t"));file.close()
	await preview.shutdown();_check("native_v2_material_shutdown",preview.gpu_release_done)
	_finish();var passed:=true
	for row in checks:passed=passed and row.pass
	quit(0 if passed else 1)

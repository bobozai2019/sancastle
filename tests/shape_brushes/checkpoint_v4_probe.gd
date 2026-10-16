extends "res://tests/shape_brushes/material_edit_probe.gd"

func stamp(id:StringName,params:Dictionary,start:Vector2,finish:Vector2,stroke:int,zero:bool=false) -> Dictionary:
	_check("v4_stroke_begin",(await preview.begin_shape_stroke(stroke)).is_empty())
	var value:=BrushProtocol.make_command(id,params,start,finish,preview.domain.domain_id,preview.generation,preview.command_queue.last_command_id+1,stroke,0,preview.completed_ticks,preview.shape_baseline_token)
	value.material_profile_id=&"molded_v1" if id!=&"shovel_v1" else &"plain_sand_v1"
	if zero:value.add_budget_m3=0.0
	var result:=await submit(value);await preview.end_shape_stroke();return result

func _run() -> void:
	root.size=Vector2i(1280,720);pair_fields=27
	preview=load("res://tests/shape_brushes/checkpoint_v4_lab.tscn").instantiate();root.add_child(preview)
	var deadline:=Time.get_ticks_msec()+90000
	while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	_check("v4_ready",preview.ready_for_ticks,preview.last_error)
	if not preview.ready_for_ticks:await preview.shutdown();_finish();quit(1);return
	var result:=await stamp(&"castle_v1",{"scale_xz":1.0,"height_m":0.7,"yaw_rad":PI/4},Vector2.ZERO,Vector2.ZERO,1000)
	_check("v4_real_castle",result.get("status")==1,result)
	result=await stamp(&"wall_v1",{"height_m":0.3,"bottom_width_m":1.0,"top_width_m":0.5},Vector2(-4,0),Vector2(-3,0),1001)
	_check("v4_real_wall",result.get("status")==1,result)
	result=await stamp(&"shovel_v1",{"trench_width_m":0.5,"depth_m":0.15,"shoulder_width_m":0.5},Vector2(0,-1),Vector2(0,1),1002)
	_check("v4_real_shovel",result.get("status")==1,result)
	result=await stamp(&"wall_v1",{"height_m":0.3,"bottom_width_m":1.0,"top_width_m":0.5},Vector2(4,0),Vector2(5,0),1003,true)
	_check("v4_rejected_candidate_record",result.get("status")==3,result)
	var error:StringName=preview.input_scheduler.submit(legacy_command(preview.command_queue.last_command_id+1,&"remove_sand"));await settle()
	_check("v4_legacy_remove",error.is_empty() and preview.input_scheduler.terminal[-1].result.get("status")==1)
	error=preview.input_scheduler.submit(legacy_command(preview.command_queue.last_command_id+1,&"place_sand"));await settle()
	_check("v4_legacy_place",error.is_empty() and preview.input_scheduler.terminal[-1].result.get("status")==1)
	var anchor:=await snapshot("v4_anchor");var anchor_meta:=metadata();var path:=output.path_join("mixed_v4.scp")
	error=await preview.save_gpu_checkpoint(path);_check("v4_disk_save",error.is_empty(),String(error))
	if not error.is_empty():await preview.shutdown();_finish();quit(1);return
	var loaded:Dictionary=preview.Store.load(path);var checkpoint:Dictionary=loaded.checkpoint
	_check("v4_native2_header",loaded.error.is_empty() and checkpoint.gpu_beach_edit.version==4 and checkpoint.gpu_beach_edit.brush_schema==2 and checkpoint.gpu_beach_native.version==2)
	_check("v4_mixed_prefix_raw",checkpoint.gpu_beach_edit.prefix.size()==6 and checkpoint.gpu_beach_edit.prefix[0].backend=="brush_v2" and checkpoint.gpu_beach_edit.prefix[4].backend=="legacy_v1" and checkpoint.gpu_beach_edit.prefix[0].receipt_raw.size()==256 and checkpoint.gpu_beach_edit.prefix[4].receipt_raw.size()==128)
	var mutations:Array=["hash","budget","receipt","backend","duplicate","order","selection","account","ledger","material"]
	var errors:Dictionary={}
	for name in mutations:
		var bad:Dictionary=checkpoint.duplicate(true)
		match name:
			"hash":bad.gpu_beach_edit.prefix[0].command.template_hash="0".repeat(64)
			"budget":bad.gpu_beach_edit.prefix[0].command.add_budget_m3=1000.0
			"receipt":bad.gpu_beach_edit.prefix[0].result.added_m3+=1.0
			"backend":bad.gpu_beach_edit.prefix[0].backend="legacy_v1"
			"duplicate":bad.gpu_beach_edit.prefix.append(bad.gpu_beach_edit.prefix[0].duplicate(true))
			"order":bad.gpu_beach_edit.prefix.reverse()
			"selection":bad.gpu_beach_edit.selection.brush.tool="unknown"
			"account":bad.gpu_beach_edit.selection.sand_accounting="inventory"
			"ledger":bad.gpu_beach_edit.ledger.sand_source_m3+=1.0;bad.shadow.sand_source_m3+=1.0
			"material":bad.gpu_beach_native.material.erase("spare_support")
		error=await preview.restore_gpu_checkpoint_data(bad);errors[name]=String(error);_check("v4_reject_"+name,not error.is_empty(),String(error))
	_check("v4_invalid_atomic",exact(anchor,await snapshot("v4_after_rejections")) and metadata()==anchor_meta)
	var prefix_before: Array=preview.gpu_prefix.duplicate(true)
	preview.gpu_prefix[0].result.added_m3+=1.0
	var invalid_path:=output.path_join("invalid_prefix_must_not_write.scp")
	error=await preview.save_gpu_checkpoint(invalid_path)
	_check("v4_save_audits_before_write",error==&"invalid_brush_prefix_receipt" and not FileAccess.file_exists(invalid_path) and preview.ready_for_ticks and preview.last_error.is_empty(),String(error))
	preview.gpu_prefix=prefix_before
	_check("v4_invalid_save_atomic",exact(anchor,await snapshot("v4_after_invalid_save")) and metadata()==anchor_meta)
	result=await stamp(&"wall_v1",{"height_m":0.3,"bottom_width_m":1.0,"top_width_m":0.5},Vector2(6,0),Vector2(7,0),1004)
	_check("v4_state_changed_after_anchor",result.get("status")==1)
	var generation_before:int=preview.generation
	error=await preview.restore_gpu_checkpoint(path);_check("v4_restore_committed",error.is_empty() and preview.generation==generation_before+1,String(error))
	_check("v4_restore_27_exact",exact(anchor,await snapshot("v4_restored")))
	_check("v4_restore_prefix_ledger",preview.gpu_prefix==checkpoint.gpu_beach_edit.prefix and preview.domain.sand_source_m3==anchor_meta.source and preview.domain.sand_sink_m3==anchor_meta.sink and preview.command_queue.last_command_id==anchor_meta.highwater and preview.shape_stroke_id==0)
	result=await stamp(&"shovel_v1",{"trench_width_m":0.5,"depth_m":0.15,"shoulder_width_m":0.5},Vector2(-4,-0.5),Vector2(-4,0.5),1005)
	_check("v4_restored_edit",result.get("status")==1,result)
	error=await preview.save_gpu_checkpoint(output.path_join("v4_after_restored_edit.scp"));_check("v4_resave_mixed_generations",error.is_empty(),String(error))
	var file:=FileAccess.open(output.path_join("v4_evidence.json"),FileAccess.WRITE);file.store_string(JSON.stringify({"errors":errors,"raw_index":raw_index,"prefix":preview.gpu_prefix,"source_signature":preview.source_signature,"scope":"actual mixed brush/legacy prefix, rejected row, raw 27 exact restore and subsequent edit; no strict long continuation/water/UI claim"},"\t"));file.close()
	await preview.shutdown();_check("v4_shutdown",preview.gpu_release_done)
	_finish();var passed:=true
	for row in checks:passed=passed and row.pass
	quit(0 if passed else 1)

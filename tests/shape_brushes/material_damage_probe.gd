extends "res://tests/shape_brushes/material_edit_probe.gd"

var damage_mode := "intact"
var damage_samples := []
var phase_states := {}
var initial_source := 0.0
var initial_sink := 0.0

func damage_capture(tick: int) -> void:
	await snapshot("damage_tick_%04d"%tick)
	damage_samples.append(raw_index[-1])
	root.get_texture().get_image().save_png(output.path_join("damage_tick_%04d.png"%tick))

func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--mode="): damage_mode=arg.trim_prefix("--mode=")
	if damage_mode not in ["intact","trench"]: _check("damage_arguments",false);_finish();quit(1);return
	root.size=Vector2i(1280,720);pair_fields=27
	await open_material_lab()
	if not preview.ready_for_ticks: _finish();quit(1);return
	preview.sand_cohesion_yield_height_m=0.0
	await snapshot("before_form");phase_states["before_form"]=raw_index[-1]
	var value:=BrushProtocol.make_command(&"wall_v1",{"height_m":0.6,"bottom_width_m":1.0,"top_width_m":0.5},Vector2(-1,0),Vector2(1,0),preview.domain.domain_id,preview.generation,preview.command_queue.last_command_id+1,preview.shape_stroke_id,0,preview.completed_ticks,preview.shape_baseline_token)
	value.material_profile_id=&"molded_v1"
	var result:=await submit(value)
	_check("actual_molded_wall_formed",result.get("status")==1,result)
	await preview.end_shape_stroke()
	await snapshot("formed");phase_states["formed"]=raw_index[-1]
	var command_records: Array=[value]
	var result_records: Array=[result]
	if damage_mode=="trench":
		var cut:=legacy_command(preview.command_queue.last_command_id+1,&"remove_sand")
		cut.transform={"position_m":Vector3(0,0,-1),"end_position_m":Vector3(0,0,1)}
		cut.radius_m=0.4;cut.amount_m3=1.5
		var error: StringName=preview.input_scheduler.submit(cut)
		await settle();result=preview.input_scheduler.terminal[-1].result
		_check("actual_trench_cut",error.is_empty() and result.get("status")==1 and preview.completed_ticks==0,result)
		command_records.append(cut);result_records.append(result)
	initial_source=preview.shadow_domain.sand_source_m3;initial_sink=preview.shadow_domain.sand_sink_m3
	await damage_capture(0)
	for tick in range(1,901):
		await _ticks(1)
		if not preview.last_error.is_empty(): break
		if tick%150==0:
			await damage_capture(tick);print("MATERIAL_DAMAGE_PROGRESS ",damage_mode," ",tick)
	_check("damage_30_sim_seconds",preview.completed_ticks==900 and preview.last_error.is_empty(),preview.last_error)
	_check("damage_no_implicit_external_sand",preview.shadow_domain.sand_source_m3==initial_source and preview.shadow_domain.sand_sink_m3==initial_sink)
	var file:=FileAccess.open(output.path_join("damage_evidence.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"mode":damage_mode,"phases":phase_states,"samples":damage_samples,"commands":command_records,"receipts":result_records,"metadata":metadata(),"completed_ticks":preview.completed_ticks,"delta_s":preview.SIM_DELTA,"tick_duration_rational":[1,30],"tick_duration_float64_hex":PackedFloat64Array([preview.SIM_DELTA]).to_byte_array().hex_encode(),"initial_source":initial_source,"initial_sink":initial_sink,"profile":preview.material_coupler.profile,"profile_sha256":preview.material_coupler.profile_sha256,"actual_local_pushes":preview.material_coupler.local_pushes,"source_signature":preview.source_signature,"scope":"Actual molded wall and trench; full original coupled solver, no waves, frozen presentation. No native/ordinary strict acceptance."},"\t"));file.close()
	var shape_tx=preview.shape_gpu.material_transaction;var legacy_tx=preview.solver.legacy_material_transaction
	await preview.shutdown()
	_check("damage_resources_released",preview.gpu_release_done and shape_tx.rd==null and legacy_tx.rd==null)
	_finish();var passed:=true
	for row in checks: passed=passed and row.pass
	quit(0 if passed else 1)

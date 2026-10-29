extends "res://tests/shape_brushes/material_edit_probe.gd"
func _run() -> void:
	root.size=Vector2i(1280,720);pair_fields=27;var records:=[]
	for mode in ["clamp","over_cfl"]:
		preview=load("res://tests/shape_brushes/water_guard_lab.tscn").instantiate();preview.brush_fixture="submerged";preview.guard_mode=mode;preview.playing=false;preview.hide_hud=true;root.add_child(preview)
		var deadline:=Time.get_ticks_msec()+90000
		while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
		_check(mode+"_ready",preview.ready_for_ticks,preview.last_error)
		if not preview.ready_for_ticks:_finish();quit(1);return
		_check(mode+"_begin",(await preview.begin_shape_stroke(5000)).is_empty())
		var command:=BrushProtocol.make_command(&"wall_v1",{"height_m":0.3,"bottom_width_m":1.0,"top_width_m":0.5},Vector2(-0.5,0),Vector2(0.5,0),preview.domain.domain_id,preview.generation,1,5000,0,0,preview.shape_baseline_token);command.speed_m_s=1.0 if mode=="clamp" else 0.0
		var before:=await snapshot(mode+"_before");var before_index:Dictionary=raw_index[-1]
		var result:=await submit(command);var after:=await snapshot(mode+"_after")
		_check(mode+"_status",result.get("status")== (1 if mode=="clamp" else 3),result)
		if mode=="clamp":
			_check("actual_limiter_triggered",result.get("clamp_count",0)>0,result)
		else:_check("cfl_rejection_atomic",exact(before,after))
		records.append({"mode":mode,"command":command,"result":result,"before":before_index,"after":raw_index[-1]})
		await preview.end_shape_stroke();await preview.shutdown();preview.queue_free();await process_frame
	var file:=FileAccess.open(output.path_join("water_guards.json"),FileAccess.WRITE);file.store_string(JSON.stringify(records,"\t"));file.close()
	_finish();var passed:=true
	for row in checks:passed=passed and row.pass
	quit(0 if passed else 1)

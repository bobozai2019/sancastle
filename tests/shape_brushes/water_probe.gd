extends "res://tests/shape_brushes/material_edit_probe.gd"

var cases:=[]
func _run() -> void:
	root.size=Vector2i(1280,720);pair_fields=27
	for entry in [{"name":"wall_shallow","fixture":"shallow_water","tool":"wall_v1","speed":0.0},{"name":"wall_submerged","fixture":"submerged","tool":"wall_v1","speed":0.0},{"name":"castle_shallow","fixture":"shallow_water","tool":"castle_v1","speed":0.0},{"name":"shovel_shallow","fixture":"shallow_water","tool":"shovel_v1","speed":0.0},{"name":"shovel_submerged","fixture":"submerged","tool":"shovel_v1","speed":0.0},{"name":"wall_velocity","fixture":"shallow_water","tool":"wall_v1","speed":0.25},{"name":"castle_velocity","fixture":"shallow_water","tool":"castle_v1","speed":0.25},{"name":"shovel_velocity","fixture":"shallow_water","tool":"shovel_v1","speed":0.25},{"name":"wall_dry","fixture":"dry_flat","tool":"wall_v1","speed":0.0},{"name":"castle_submerged","fixture":"submerged","tool":"castle_v1","speed":0.0},{"name":"wall_disconnected","fixture":"shallow_water","mode":"disconnected","tool":"wall_v1","speed":0.0},{"name":"wall_capacity","fixture":"shallow_water","mode":"capacity","tool":"wall_v1","speed":0.0},{"name":"wall_obstacle","fixture":"shallow_water","mode":"obstacle","tool":"wall_v1","speed":0.0},{"name":"wall_boundary","fixture":"shallow_water","tool":"wall_v1","speed":0.0},{"name":"wall_loaded","fixture":"shallow_water","mode":"loaded","tool":"wall_v1","speed":0.0},{"name":"water_rejected","fixture":"shallow_water","tool":"wall_v1","speed":0.0}]:
		preview=load("res://tests/shape_brushes/water_lab.tscn").instantiate();preview.brush_fixture=entry.fixture;preview.water_fixture_mode=entry.get("mode","");preview.playing=false;preview.hide_hud=true;root.add_child(preview)
		var deadline:=Time.get_ticks_msec()+90000
		while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
		_check(entry.name+"_ready",preview.ready_for_ticks,preview.last_error)
		if not preview.ready_for_ticks:await preview.shutdown();_finish();quit(1);return
		_check(entry.name+"_begin",(await preview.begin_shape_stroke(2000)).is_empty())
		var id:=StringName(entry.tool);var params:Dictionary={}
		match id:
			&"wall_v1":params={"height_m":0.3,"bottom_width_m":1.0,"top_width_m":0.5}
			&"castle_v1":params={"scale_xz":1.0,"height_m":0.7,"yaw_rad":0.0}
			&"shovel_v1":params={"trench_width_m":0.5,"depth_m":0.15,"shoulder_width_m":0.5}
		var start:=Vector2(-0.5,0);var finish:=Vector2(0.5,0)
		if id==&"castle_v1":start=Vector2.ZERO;finish=Vector2.ZERO
		if entry.name=="wall_boundary":start=Vector2(15.0,0);finish=Vector2(15.5,0)
		var value:=BrushProtocol.make_command(id,params,start,finish,preview.domain.domain_id,preview.generation,1,2000,0,preview.completed_ticks,preview.shape_baseline_token)
		value.material_profile_id=&"molded_v1" if id!=&"shovel_v1" else &"plain_sand_v1";value.speed_m_s=entry.speed
		if entry.name=="water_rejected":preview.solver.inject_water_loss_once=true
		var before:=await snapshot(entry.name+"_before");var before_index:Dictionary=raw_index[-1]
		var result:=await submit(value);var after:=await snapshot(entry.name+"_after")
		_check(entry.name+"_status",result.get("status")== (3 if entry.name in ["water_rejected","wall_obstacle"] else 1),result)
		if entry.name in ["water_rejected","wall_obstacle"]:_check(entry.name+"_full_atomic",exact(before,after))
		else:_check(entry.name+"_published",after.sand==after.published_sand and after.water==after.published_water)
		cases.append({"name":entry.name,"command":value,"start":[start.x,start.y],"end":[finish.x,finish.y],"before":before_index,"after":raw_index[-1],"result":result,"statistics":preview.shape_gpu.statistics()})
		await preview.end_shape_stroke()
		if entry.name=="shovel_shallow":
			var saved:StringName=await preview.save_gpu_checkpoint(output.path_join("wet_shovel_v4.scp"));_check("wet_v4_save",saved.is_empty(),String(saved))
		var water_helper=preview.shape_gpu.water_transaction
		await preview.shutdown();_check(entry.name+"_water_release",water_helper.rd==null and water_helper.owned.is_empty());preview.queue_free();await process_frame
	var file:=FileAccess.open(output.path_join("water_cases.json"),FileAccess.WRITE);file.store_string(JSON.stringify(cases,"\t"));file.close()
	_finish();var passed:=true
	for row in checks:passed=passed and row.pass
	quit(0 if passed else 1)

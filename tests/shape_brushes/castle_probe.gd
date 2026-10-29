extends "res://tests/shape_brushes/material_edit_probe.gd"

var cases := []
var foundation_query
var foundation_summary := PackedByteArray()
var foundation_query_done := false

func _read_foundation(params:Dictionary) -> void:
	foundation_query=preload("res://scripts/simulation/brushes/brush_preview_query.gd").new()
	if not foundation_query.initialize(preview.solver,preview.shape_gpu.images.castle_template) or not foundation_query.request(Vector2.ZERO,params,_foundation_received):
		foundation_query.release();call_deferred("_foundation_ready",PackedByteArray())

func _foundation_received(bytes:PackedByteArray) -> void:
	foundation_query.release();call_deferred("_foundation_ready",bytes)

func _foundation_ready(bytes:PackedByteArray) -> void:
	foundation_summary=bytes;foundation_query_done=true

func _run() -> void:
	root.size=Vector2i(1280,720);pair_fields=27
	for entry in [{"name":"default","scale":1.0,"height":0.7,"yaw":0.0,"fixture":"dry_flat"},{"name":"yaw45","scale":1.0,"height":0.7,"yaw":PI/4,"fixture":"dry_flat"},{"name":"max","scale":1.5,"height":1.0,"yaw":PI/2,"fixture":"dry_flat"},{"name":"min","scale":1.0,"height":0.5,"yaw":0.0,"fixture":"dry_flat"},{"name":"slope","scale":1.0,"height":0.7,"yaw":0.0,"fixture":"dry_slope"},{"name":"thin","scale":1.0,"height":0.7,"yaw":0.0,"fixture":"thin_sand"},{"name":"steep","scale":1.0,"height":0.7,"yaw":0.0,"fixture":"dry_flat"},{"name":"obstacle","scale":1.0,"height":0.7,"yaw":0.0,"fixture":"dry_flat"},{"name":"deep","scale":1.0,"height":0.7,"yaw":0.0,"fixture":"dry_flat"},{"name":"mixed","scale":1.0,"height":0.7,"yaw":0.0,"fixture":"dry_flat"},{"name":"budget","scale":1.0,"height":0.7,"yaw":0.0,"fixture":"dry_flat"}]:
		preview=load("res://tests/shape_brushes/castle_lab.tscn").instantiate();preview.brush_fixture=entry.fixture;preview.fixed_height_case=entry.name;preview.steep_foundation=entry.name=="steep";preview.foundation_obstacle=entry.name=="obstacle";preview.playing=false;preview.hide_hud=true;root.add_child(preview)
		var deadline:=Time.get_ticks_msec()+90000
		while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
		_check(entry.name+"_ready",preview.ready_for_ticks,preview.last_error)
		if not preview.ready_for_ticks:await preview.shutdown();_finish();quit(1);return
		if entry.name in ["steep","deep","mixed","obstacle"]:
			foundation_query_done=false;foundation_summary=PackedByteArray()
			RenderingServer.call_on_render_thread(_read_foundation.bind({"scale_xz":entry.scale,"height_m":entry.height,"yaw_rad":entry.yaw}))
			deadline=Time.get_ticks_msec()+30000
			while not foundation_query_done and Time.get_ticks_msec()<deadline:await process_frame
			_check(entry.name+"_preview_fixed_target",foundation_query_done and foundation_summary.size()==64 and foundation_summary.decode_float(0)==0.0 and foundation_summary.decode_u32(8)==0)
		_check(entry.name+"_baseline",(await preview.begin_shape_stroke(900)).is_empty())
		var value:=BrushProtocol.make_command(&"castle_v1",{"scale_xz":entry.scale,"height_m":entry.height,"yaw_rad":entry.yaw},Vector2.ZERO,Vector2.ZERO,preview.domain.domain_id,preview.generation,1,900,0,preview.completed_ticks,preview.shape_baseline_token)
		value.material_profile_id=&"molded_v1"
		if entry.name=="default":
			var bad:Dictionary=value.duplicate(true);bad.template_hash="0".repeat(64)
			_check("castle_hash_mismatch",BrushProtocol.command_error(bad)==&"template_mismatch")
			bad=value.duplicate(true);bad.start_xz_m=Vector2(15,15);bad.end_xz_m=bad.start_xz_m
			_check("castle_full_boundary_rejected",BrushProtocol.command_error(bad)==&"out_of_domain")
			bad=value.duplicate(true);bad.scale_xz=0.5
			_check("castle_too_small_rejected",not BrushProtocol.command_error(bad).is_empty())
		if entry.name=="budget":value.add_budget_m3=0.0
		var before:=await snapshot(entry.name+"_before");var before_index:Dictionary=raw_index[-1]
		var result:=await submit(value);var after:=await snapshot(entry.name+"_after")
		var rejected:bool=entry.name=="budget"
		_check(entry.name+"_status",result.get("status")== (3 if rejected else 1),result)
		if rejected:_check(entry.name+"_atomic",exact(before,after) and preview.domain.sand_source_m3==0.0)
		else:
			_check(entry.name+"_published",after.sand==after.published_sand)
			_check(entry.name+"_material",after.mold_support_0==after.mold_support_1 and preview.solver.mold_field_ever_used)
		cases.append({"name":entry.name,"command":value,"result":result,"before":before_index,"after":raw_index[-1],"source":preview.domain.sand_source_m3})
		if entry.name in ["default","yaw45","max"]:
			preview.player_camera.position=Vector3(-5,4,6);preview.player_camera.look_at(Vector3(0,0.3,0),Vector3.UP)
			await RenderingServer.frame_post_draw;await RenderingServer.frame_post_draw
			_check(entry.name+"_visible_capture",root.get_texture().get_image().save_png(output.path_join(entry.name+".png"))==OK)
		if entry.name=="default":
			var repeat_source:float=preview.domain.sand_source_m3
			var repeated:Dictionary=value.duplicate(true);repeated.command_id=preview.command_queue.last_command_id+1;repeated.sample_index=1
			var repeat_result:Dictionary=await submit(repeated)
			var repeat_after:=await snapshot("castle_repeat")
			_check("repeat_fixed_height_no_add",repeat_result.get("status")==2 and repeat_after.sand==after.sand and preview.domain.sand_source_m3==repeat_source,repeat_result)
			await preview.end_shape_stroke()
			_check("repeat_new_stroke_baseline",(await preview.begin_shape_stroke(901)).is_empty())
			repeated=BrushProtocol.make_command(&"castle_v1",{"scale_xz":entry.scale,"height_m":entry.height,"yaw_rad":entry.yaw},Vector2.ZERO,Vector2.ZERO,preview.domain.domain_id,preview.generation,preview.command_queue.last_command_id+1,901,0,preview.completed_ticks,preview.shape_baseline_token)
			repeated.material_profile_id=&"molded_v1"
			repeat_result=await submit(repeated);repeat_after=await snapshot("castle_repeat_new_stroke")
			_check("repeat_new_stroke_no_stack",repeat_result.get("status")==2 and repeat_after.sand==after.sand and preview.domain.sand_source_m3==repeat_source,repeat_result)
		await preview.end_shape_stroke()
		if entry.name=="default":
			var cut:Dictionary=legacy_command(preview.command_queue.last_command_id+1,&"remove_sand")
			var error:StringName=preview.input_scheduler.submit(cut);await settle()
			var damaged:=await snapshot("castle_legacy_cut")
			_check("castle_ordinary_editable",error.is_empty() and preview.input_scheduler.terminal[-1].result.get("status")==1 and damaged.sand!=after.sand and damaged.published_sand==damaged.sand)
		await preview.shutdown();preview.queue_free();await process_frame
	var file:=FileAccess.open(output.path_join("castle_cases.json"),FileAccess.WRITE);file.store_string(JSON.stringify(cases,"\t"));file.close()
	_finish();var passed:=true
	for row in checks:passed=passed and row.pass
	quit(0 if passed else 1)

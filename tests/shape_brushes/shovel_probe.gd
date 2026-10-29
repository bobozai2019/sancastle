extends "res://tests/shape_brushes/material_edit_probe.gd"

var cases := []

func shovel_command(start:Vector2,finish:Vector2) -> Dictionary:
	var value:=BrushProtocol.make_command(&"shovel_v1",{"trench_width_m":0.5,"depth_m":0.15,"shoulder_width_m":0.5},start,finish,preview.domain.domain_id,preview.generation,preview.command_queue.last_command_id+1,preview.shape_stroke_id,sample_index,preview.completed_ticks,preview.shape_baseline_token)
	sample_index+=1;return value

func _run() -> void:
	root.size=Vector2i(1280,720);pair_fields=27
	for entry in [{"name":"flat","fixture":"dry_flat"},{"name":"thin","fixture":"thin_sand"},{"name":"slope","fixture":"dry_slope"},{"name":"blocked","fixture":"dry_flat"},{"name":"zero_budget","fixture":"dry_flat"},{"name":"rejected","fixture":"dry_flat"},{"name":"molded","fixture":"dry_flat"}]:
		preview=load("res://tests/shape_brushes/shovel_lab.tscn").instantiate();preview.brush_fixture=entry.fixture;preview.block_right_shoulder=entry.name=="blocked";preview.playing=false;preview.hide_hud=true;root.add_child(preview)
		var deadline:=Time.get_ticks_msec()+90000
		while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
		_check(entry.name+"_ready",preview.ready_for_ticks,preview.last_error)
		if not preview.ready_for_ticks:await preview.shutdown();_finish();quit(1);return
		sample_index=0
		if entry.name=="molded":
			_check("molded_wall_begin",(await preview.begin_shape_stroke(800)).is_empty())
			var formed:=await submit(molded_command());_check("molded_wall_formed",formed.get("status")==1,formed)
			await preview.end_shape_stroke()
		_check(entry.name+"_baseline",(await preview.begin_shape_stroke(901)).is_empty());sample_index=0
		var start:=Vector2(-1,0);var finish:=Vector2(1,0)
		if entry.name=="molded":start=Vector2(0,-1);finish=Vector2(0,1)
		var value:=shovel_command(start,finish)
		if entry.name=="zero_budget":value.transfer_budget_m3=0.0
		if entry.name=="rejected":preview.shape_gpu.inject_candidate_failure_once=true
		var before:=await snapshot(entry.name+"_before");var before_index:Dictionary=raw_index[-1];var before_meta:=metadata()
		var result:=await submit(value);var after:=await snapshot(entry.name+"_after");var after_index:Dictionary=raw_index[-1]
		var status:=3 if entry.name=="rejected" else (2 if entry.name in ["blocked","zero_budget"] else 1)
		_check(entry.name+"_status",result.get("status")==status,result)
		_check(entry.name+"_ledger_unchanged",before_meta.source==preview.domain.sand_source_m3 and before_meta.sink==preview.domain.sand_sink_m3 and before_meta.inventory==preview.domain.tool_inventory_m3)
		if status!=1:_check(entry.name+"_all_raw_atomic",exact(before,after))
		else:
			_check(entry.name+"_published",after.sand==after.published_sand)
			_check(entry.name+"_dual_sand_material",after.sand==after.spare_sand and after.mold_support_0==after.mold_support_1)
			_check(entry.name+"_transfer_receipt",result.external_source_delta_m3==0.0 and result.external_sink_delta_m3==0.0 and absf(result.removed_m3-result.left_received_m3-result.right_received_m3)<=result.eps_transfer_m3)
		cases.append({"name":entry.name,"start":[start.x,start.y],"end":[finish.x,finish.y],"command":value,"result":result,"before":before_index,"after":after_index,"before_metadata":before_meta,"after_metadata":metadata()})
		if entry.name=="flat":
			var repeat:=await submit(shovel_command(finish,start));var repeated:=await snapshot("flat_repeated")
			_check("same_stroke_reverse_no_change",repeat.get("status")==2 and exact(after,repeated),repeat)
			preview.player_camera.position=Vector3(-3,3,4);preview.player_camera.look_at(Vector3.ZERO,Vector3.UP)
			await RenderingServer.frame_post_draw;await RenderingServer.frame_post_draw
			_check("shovel_visible_capture",root.get_texture().get_image().save_png(output.path_join("flat.png"))==OK)
		await preview.end_shape_stroke();await preview.shutdown();preview.queue_free();await process_frame
	var file:=FileAccess.open(output.path_join("shovel_cases.json"),FileAccess.WRITE);file.store_string(JSON.stringify(cases,"\t"));file.close()
	_finish();var passed:=true
	for row in checks:passed=passed and row.pass
	quit(0 if passed else 1)

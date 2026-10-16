extends "res://tests/shape_brushes/material_edit_probe.gd"

const PathStroke=preload("res://scripts/sand/brushes/stroke_controller.gd")
var path_cases:=[]
var read_path_done:=false
func read_path_fields() -> void:
	for field in ["sand","compaction","water"]:preview.solver.request_data(field,_record.bind(field))
	preview.solver.rd.texture_get_data_async(preview.solver.textures.mold_support[preview.solver.current_index],0,_record.bind("mold_support_0"))
	preview.solver.rd.texture_get_data_async(preview.shape_gpu.images.coverage,0,_record.bind("coverage"))
func path_snapshot(tag:String) -> Dictionary:
	readbacks.clear();RenderingServer.call_on_render_thread(read_path_fields)
	var deadline:=Time.get_ticks_msec()+30000
	while readbacks.size()<5 and Time.get_ticks_msec()<deadline:await process_frame
	_check(tag+"_readback",readbacks.size()==5)
	var index:={}
	for key in readbacks:
		var path:=output.path_join(tag+"_"+key+".bin");var file:=FileAccess.open(path,FileAccess.WRITE);file.store_buffer(readbacks[key]);file.close()
		index[key]={"path":path,"bytes":readbacks[key].size(),"sha256":FileAccess.get_sha256(path)}
	return {"fields":index}

func run_path(points:Array,case_name:String,phase:String,previous:Dictionary) -> Dictionary:
	var controller=PathStroke.new();var params:={"trench_width_m":0.5,"depth_m":0.15,"shoulder_width_m":0.5}
	_check(phase+"_controller_begin",controller.begin_stroke(&"shovel_v1",params,points[0],preview.shape_stroke_id,preview.generation).is_empty())
	for i in range(1,points.size()):_check(phase+"_path_sample",controller.append_path_sample(points[i]).is_empty())
	controller.end_stroke();var steps:=[];var counter:=0
	while controller.buffer_points()>0:
		controller.begin_frame(Engine.get_process_frames())
		var segment:Dictionary=controller.peek_segment()
		if segment.is_empty():await process_frame;continue
		var command:=BrushProtocol.make_command(&"shovel_v1",params,segment.start_xz_m,segment.end_xz_m,preview.domain.domain_id,preview.generation,preview.command_queue.last_command_id+1,preview.shape_stroke_id,sample_index,preview.completed_ticks,preview.shape_baseline_token)
		sample_index+=1
		var admission:StringName=preview.input_scheduler.submit(command)
		_check("path_admitted",admission.is_empty(),String(admission))
		if not admission.is_empty():break
		controller.acknowledge_admission(segment,command.command_id)
		await settle()
		var result:Dictionary=preview.input_scheduler.terminal[-1].result;controller.settle_command(command.command_id,preview.generation)
		_check(phase+"_valid_result",result.get("status") in [1,2],result)
		if phase=="repeat":_check(case_name+"_repeat_no_change",result.get("status")==2,result)
		var after:=await path_snapshot(case_name+"_"+phase+"_"+str(counter))
		steps.append({"command":command,"start":[segment.start_xz_m.x,segment.start_xz_m.y],"end":[segment.end_xz_m.x,segment.end_xz_m.y],"result":result,"before":previous,"after":after})
		previous=after;counter+=1
		if not preview.last_error.is_empty():break
	_check(phase+"_controller_settled",controller.state==&"settled" and controller.outstanding==0)
	return {"steps":steps,"last":previous}

func _run() -> void:
	root.size=Vector2i(1280,720);pair_fields=27
	for entry in [{"name":"corner90","points":[Vector2(-0.5,0),Vector2(0.5,0),Vector2(0.5,1)]},{"name":"curve_cross","points":[Vector2(-0.5,-0.5),Vector2(0.5,0.5),Vector2(-0.5,0.5),Vector2(0.5,-0.5)]},{"name":"structures","points":[Vector2(-1.75,1.25),Vector2(3.25,1.25)]}]:
		preview=load("res://tests/shape_brushes/water_lab.tscn").instantiate();preview.brush_fixture="shallow_water" if entry.name=="structures" else "dry_flat";preview.playing=false;preview.hide_hud=true;root.add_child(preview)
		var deadline:=Time.get_ticks_msec()+90000
		while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
		_check(entry.name+"_ready",preview.ready_for_ticks,preview.last_error)
		if not preview.ready_for_ticks:_finish();quit(1);return
		if entry.name=="structures":
			_check("castle_seed_begin",(await preview.begin_shape_stroke(1000)).is_empty())
			var castle:=BrushProtocol.make_command(&"castle_v1",{"scale_xz":1.0,"height_m":0.7,"yaw_rad":0.0},Vector2.ZERO,Vector2.ZERO,preview.domain.domain_id,preview.generation,preview.command_queue.last_command_id+1,1000,0,0,preview.shape_baseline_token);castle.material_profile_id=&"molded_v1"
			_check("castle_seed_applied",(await submit(castle)).get("status")==1);await preview.end_shape_stroke()
			_check("wall_seed_begin",(await preview.begin_shape_stroke(1001)).is_empty())
			var wall:=BrushProtocol.make_command(&"wall_v1",{"height_m":0.3,"bottom_width_m":1.0,"top_width_m":0.5},Vector2(3,0.75),Vector2(3,1.75),preview.domain.domain_id,preview.generation,preview.command_queue.last_command_id+1,1001,0,0,preview.shape_baseline_token);wall.material_profile_id=&"molded_v1"
			_check("wall_seed_applied",(await submit(wall)).get("status")==1);await preview.end_shape_stroke()
		_check("path_begin",(await preview.begin_shape_stroke(1002)).is_empty());sample_index=0
		var initial:=await snapshot(entry.name+"_initial");var initial_index:Dictionary=raw_index[-1];var ledger:=metadata()
		var first:=await run_path(entry.points,entry.name,"first",await path_snapshot(entry.name+"_path_initial"))
		var before_repeat:=await snapshot(entry.name+"_before_repeat")
		var reverse:Array=entry.points.duplicate();reverse.reverse()
		var repeated:=await run_path(reverse,entry.name,"repeat",first.last)
		_check(entry.name+"_repeat_all27_exact",exact(before_repeat,await snapshot(entry.name+"_after_repeat")))
		await preview.end_shape_stroke()
		_check("fresh_path_begin",(await preview.begin_shape_stroke(1003)).is_empty());sample_index=0
		var fresh_initial:=await snapshot(entry.name+"_fresh_initial");var fresh_index:Dictionary=raw_index[-1]
		var fresh:=await run_path(entry.points,entry.name,"fresh",await path_snapshot(entry.name+"_fresh_path_initial"))
		var final:=await snapshot(entry.name+"_final");var final_index:Dictionary=raw_index[-1]
		_check(entry.name+"_new_stroke_digs_again",final.sand!=fresh_initial.sand)
		_check(entry.name+"_no_external_accounting",preview.domain.sand_source_m3==ledger.source and preview.domain.sand_sink_m3==ledger.sink and preview.domain.tool_inventory_m3==ledger.inventory)
		path_cases.append({"name":entry.name,"initial":initial_index,"fresh_initial":fresh_index,"final":final_index,"phases":[first,repeated,fresh]})
		await preview.end_shape_stroke()
		preview.player_camera.position=Vector3(-4,4,6);preview.player_camera.look_at(Vector3.ZERO,Vector3.UP);await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join(entry.name+".png"))
		await preview.shutdown();preview.queue_free();await process_frame
	var file:=FileAccess.open(output.path_join("shovel_paths.json"),FileAccess.WRITE);file.store_string(JSON.stringify(path_cases,"\t"));file.close()
	_finish();var passed:=true
	for row in checks:passed=passed and row.pass
	quit(0 if passed else 1)

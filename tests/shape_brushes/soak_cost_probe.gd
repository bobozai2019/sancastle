extends "res://tests/shape_brushes/ui_probe.gd"

var frames:=[]
var samples:=[]
var actions:=[]
var measure_start:=0
var previous_frame:=0
var measuring:=false
func frame_sample() -> void:
	if not measuring:return
	var now:=Time.get_ticks_usec()
	if previous_frame>0:frames.append(float(now-previous_frame)/1000.0)
	previous_frame=now

func find_centers(state:Dictionary) -> Array:
	var rock:PackedFloat32Array=state.rock.to_float32_array();var sand:PackedFloat32Array=state.sand.to_float32_array();var obstacle:PackedByteArray=state.obstacle;var result:=[]
	for row in range(24,233,16):
		for col in range(24,233,16):
			var low:=INF;var high:=-INF;var blocked:=false
			for z in range(row-17,row+18):
				for x in range(col-17,col+18):
					var i:=z*256+x;var height:=rock[i]+sand[i];low=minf(low,height);high=maxf(high,height);blocked=blocked or obstacle[i]>0
			if blocked or high-low>0.20:continue
			var pos:=Vector3((col+0.5-128)*0.125,rock[row*256+col]+sand[row*256+col],(row+0.5-128)*0.125)
			var screen:Vector2=preview.player_camera.unproject_position(pos)
			if not root.get_visible_rect().has_point(screen):continue
			if preview.brush_panel.get_global_rect().has_point(screen) or preview.manual_edit_panel.get_global_rect().has_point(screen) or preview.get_node("Interface/PerformancePanel").get_global_rect().has_point(screen):continue
			var hit:Dictionary=preview.pick(screen)
			if hit.is_empty() or not preview._pick_current(hit):continue
			var separated:=true
			for prior in result:separated=separated and Vector2(prior.x,prior.z).distance_to(Vector2(pos.x,pos.z))>4.2
			if separated:result.append(pos)
	return result

func actual_action(tool:String,pos:Vector3) -> void:
	await select_tool(tool)
	var start:Vector2=preview.player_camera.unproject_position(pos);var finish:Vector2=preview.player_camera.unproject_position(pos+Vector3(0.4,0,0))
	var old_count:int=preview.ui_brush_events.size();var at:=Time.get_ticks_usec();var start_frame:=Engine.get_process_frames()
	await motion(start);await click(start,true)
	if tool!="Castle":await motion(finish)
	await click(start if tool=="Castle" else finish,false);await wait_ui()
	var row:Dictionary={"tool":tool,"input_us":at,"elapsed_us":Time.get_ticks_usec()-at,"input_frame":start_frame,"complete_frame":Engine.get_process_frames(),"events":preview.ui_brush_events.slice(old_count)}
	actions.append(row)
	_check("soak_action_terminal",not preview.ui_pump_running and preview.last_error.is_empty(),preview.ui_last_failure)

func resource_sample() -> Dictionary:
	return {"at_us":Time.get_ticks_usec(),"tick":preview.completed_ticks,"generation":preview.generation,"shape":preview.shape_gpu.statistics(),"query_rids":preview.preview_query.owned.size(),"pending":preview.command_queue.pending.size(),"stroke_points":preview.stroke_controller.buffer_points(),"prefix_count":preview.gpu_prefix.size(),"hud":preview.get_node("Interface/PerformancePanel").snapshot.duplicate(true),"memory_static":Performance.get_monitor(Performance.MEMORY_STATIC),"objects":Performance.get_monitor(Performance.OBJECT_COUNT),"collision_shapes":preview.collision_proxy.shapes.size(),"cache":preview.material_coupler.cache_statistics() if preview.material_coupler.has_method("cache_statistics") else {"status":"not_available"}}

func _run() -> void:
	root.size=Vector2i(1280,720);pair_fields=27;process_frame.connect(frame_sample)
	preview=load("res://scenes/main.tscn").instantiate();preview.playing=false;root.add_child(preview);current_scene=preview
	var deadline:=Time.get_ticks_msec()+90000
	while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	_check("soak_ready",preview.ready_for_ticks,preview.last_error)
	if not preview.ready_for_ticks:_finish();quit(1);return
	await physics_frame;await physics_frame
	var initial:=await snapshot("soak_initial");var centers:=find_centers(initial)
	_check("soak_actual_eligible_centers",not centers.is_empty(),centers)
	if centers.is_empty():await preview.shutdown();_finish();quit(1);return
	preview.playing=true
	var warm_end:=Time.get_ticks_msec()+10000
	while Time.get_ticks_msec()<warm_end and preview.last_error.is_empty():await process_frame
	measure_start=Time.get_ticks_usec();previous_frame=measure_start;measuring=true
	var next_action:=measure_start;var next_sample:=measure_start;var saved:=false;var sequence:=0
	var initial_tick:int=preview.completed_ticks
	while Time.get_ticks_usec()-measure_start<300000000 and preview.last_error.is_empty():
		var now:=Time.get_ticks_usec()
		if now>=next_action:
			var tool:String=["Castle","Wall","Shovel"][sequence%3];var pos:Vector3=centers[(sequence/3)%centers.size()]
			await actual_action(tool,pos);sequence+=1;next_action=Time.get_ticks_usec()+20000000
		if now>=next_sample:samples.append(resource_sample());next_sample=now+10000000;print("SOAK_COST_PROGRESS seconds=",int((now-measure_start)/1000000)," tick=",preview.completed_ticks)
		if not saved and now-measure_start>=150000000:
			preview.playing=false
			while preview.busy or preview.tick_pending:await process_frame
			var before:=await snapshot("soak_save_anchor");var path:=output.path_join("soak_v4.scp")
			var error:StringName=await preview.save_gpu_checkpoint(path);_check("soak_disk_save",error.is_empty(),String(error))
			if error.is_empty():
				error=await preview.restore_gpu_checkpoint(path);_check("soak_disk_restore",error.is_empty(),String(error));_check("soak_restore_all27",exact(before,await snapshot("soak_restored")))
			preview.playing=true;saved=true
		await process_frame
	measuring=false;preview.playing=false
	while preview.busy or preview.tick_pending:await process_frame
	samples.append(resource_sample());await snapshot("soak_final")
	_check("soak_five_minutes",Time.get_ticks_usec()-measure_start>=300000000 and preview.last_error.is_empty(),preview.last_error)
	_check("soak_ticks_progress",preview.completed_ticks>initial_tick)
	_check("soak_restore_exercised",saved)
	var success:={}
	for action in actions:
		for event in action.events:
			if event.terminal.result.get("status")==1:success[action.tool]=true
	_check("soak_all_three_actual_tools",success.has("Castle") and success.has("Wall") and success.has("Shovel"),success)
	var bounded:=true
	for sample in samples:bounded=bounded and sample.shape.rid_count==69 and sample.query_rids==4 and sample.pending<=64 and sample.stroke_points<=256 and sample.collision_shapes<=64
	_check("soak_resources_and_queues_bounded",bounded)
	var file:=FileAccess.open(output.path_join("soak_cost.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"round":1,"frames_ms":frames,"samples":samples,"actions":actions,"initial_tick":initial_tick,"final_tick":preview.completed_ticks,"duration_us":Time.get_ticks_usec()-measure_start,"window":[1280,720],"vsync":DisplayServer.window_get_vsync_mode(),"adapter":RenderingServer.get_video_adapter_name(),"api":RenderingServer.get_video_adapter_api_version(),"source_signature":preview.source_signature,"missing_metrics":["first_visible_timestamp","complete_global_RID_count"],"scope":"Real main/full workload, 300-second visible coupled window, actual GUI inputs, one ordinary disk restore; costs reported without inventing throughput gates; strict continuation FAIL separate"},"\t"));file.close()
	await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(output.path_join("soak_final.png"))
	await preview.get_node("Interface/PerformancePanel").stop_sampling();await preview.shutdown();_check("soak_release",preview.gpu_release_done and preview.preview_query==null);preview.queue_free();await process_frame
	_finish();var passed:=true
	for row in checks:passed=passed and row.pass
	quit(0 if passed else 1)

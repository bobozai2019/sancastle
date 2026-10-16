extends "res://tests/shape_brushes/final_probe.gd"

var drag_rows := []

func _run() -> void:
	root.size=Vector2i(1280,720);pair_fields=27
	for path in ["res://scenes/main.tscn","res://scenes/playable/test1_capture.tscn","res://scenes/playable/test1_backwash.tscn"]:
		preview=load(path).instantiate();preview.playing=false;root.add_child(preview);current_scene=preview
		var deadline:=Time.get_ticks_msec()+90000
		while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
		_check(path+"_drag_ready",preview.ready_for_ticks,preview.last_error)
		if not preview.ready_for_ticks:_finish();quit(1);return
		await preview.get_node("Interface/PerformancePanel").stop_sampling();await drain()
		var fields:=await snapshot(preview.scene_key+"_drag_initial")
		var centers:=find_centers(fields);fields.clear();readbacks.clear()
		_check(preview.scene_key+"_drag_centers",not centers.is_empty())
		if centers.is_empty():await preview.shutdown();_finish();quit(1);return
		var pos:Vector3=centers[0]
		if preview.scene_key!="main":
			preview.player_camera.global_position=pos+Vector3(-7,8,-10)
			preview.player_camera.look_at(pos,Vector3.UP)
			preview.player_camera.global_position-=preview.player_camera.global_basis.x*3.5
			await process_frame;await physics_frame
		for tool in ["Fill","Dig"]:
			await select_tool(tool)
			preview.brush_panel.get_node("Margin/Controls/OrdinaryParams/"+tool+"Amount").value=0.1
			root.gui_release_focus()
			var point:Vector2=preview.player_camera.unproject_position(pos)
			var count:int=preview.input_results.size()
			var source:float=preview.domain.sand_source_m3;var sink:float=preview.domain.sand_sink_m3
			await motion(point);await process_frame;await click(point,true)
			deadline=Time.get_ticks_msec()+30000
			while preview.input_running and Time.get_ticks_msec()<deadline:await process_frame
			await physics_frame;await physics_frame
			point=preview.player_camera.unproject_position(pos+Vector3(0.4,0,0))
			await motion(point);await process_frame
			while preview.input_running and Time.get_ticks_msec()<deadline:await process_frame
			await click(point,false);await drain()
			var results:Array=preview.input_results.slice(count)
			var applied:=0
			for row in results:
				if row.result.get("status")==1:applied+=1
			_check(preview.scene_key+"_"+tool+"_continuous_drag",applied>=2,results)
			_check(preview.scene_key+"_"+tool+"_drag_ledger",preview.domain.tool_inventory_m3==0.0 and (preview.domain.sand_source_m3>source and preview.domain.sand_sink_m3==sink if tool=="Fill" else preview.domain.sand_sink_m3>sink and preview.domain.sand_source_m3==source))
			drag_rows.append({"scene":preview.scene_key,"tool":tool,"results":results,"source_before":source,"sink_before":sink,"source_after":preview.domain.sand_source_m3,"sink_after":preview.domain.sand_sink_m3})
		await preview.shutdown();_check(preview.scene_key+"_drag_release",preview.gpu_release_done)
		preview.queue_free();await process_frame;await process_frame
	var file:=FileAccess.open(output.path_join("legacy_drag.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"rows":drag_rows,"scope":"Actual press, motion, release in three production entries; ordinary external_v1 ledger and queue behavior, no performance measurement"},"\t"));file.close()
	_finish();var passed:=true
	for row in checks:passed=passed and row.pass
	quit(0 if passed else 1)

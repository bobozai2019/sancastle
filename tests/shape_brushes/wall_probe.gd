extends "res://tests/shape_brushes/gpu_framework_probe.gd"

const Stroke = preload("res://scripts/sand/brushes/stroke_controller.gd")
var cases := []
var lab_records := []
var stroke_serial := 500
var evidence_fields := ["rock","sand","published_sand","baseline","coverage"]

func wall_read() -> void:
	for name in ["rock","sand"]: preview.solver.request_data(name,_record.bind(name))
	preview.solver.rd.texture_get_data_async(preview.solver.published_sand,0,_record.bind("published_sand"))
	for name in ["baseline","coverage"]: preview.solver.rd.texture_get_data_async(preview.shape_gpu.images[name],0,_record.bind(name))

func wall_snapshot(tag: String) -> Dictionary:
	readbacks.clear(); RenderingServer.call_on_render_thread(wall_read)
	var deadline := Time.get_ticks_msec()+30000
	while readbacks.size()<5 and Time.get_ticks_msec()<deadline: await process_frame
	_check(tag+"_readback",readbacks.size()==5)
	var index := {}
	for name in readbacks:
		var path := output.path_join(tag+"_"+name+".bin")
		var file := FileAccess.open(path,FileAccess.WRITE); file.store_buffer(readbacks[name]); file.close()
		index[name]={"path":path,"bytes":readbacks[name].size(),"sha256":FileAccess.get_sha256(path)}
	return index

func open_lab(fixture: String) -> bool:
	preview=load("res://tests/shape_brushes/brush_lab.tscn").instantiate()
	preview.brush_fixture=fixture; preview.playing=false; preview.visual_time_s=0.0; preview.hide_hud=true; root.add_child(preview)
	var deadline := Time.get_ticks_msec()+90000
	while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_msec()<deadline: await process_frame
	_check(fixture+"_ready",preview.ready_for_ticks,preview.last_error)
	if preview.ready_for_ticks: lab_records.append({"fixture":fixture,"source_signature":preview.source_signature,"effective_compilation":preview.effective_compilation,"profile_sha256":preview.requested_render_profile_sha256,"adapter":RenderingServer.get_video_adapter_name(),"vsync":DisplayServer.window_get_vsync_mode(),"viewport":root.size,"playing":preview.playing,"seed":101})
	return preview.ready_for_ticks

func path_commands(path: Array, density: int, params: Dictionary) -> Array:
	var controller := Stroke.new()
	_check("path_begin",controller.begin_stroke(&"wall_v1",params,path[0],stroke_serial,preview.generation).is_empty())
	for i in range(1,path.size()):
		if path[i]==null: controller.interrupt_subpath(); continue
		if path[i-1]==null:
			_check("path_reanchor",controller.append_path_sample(path[i]).is_empty()); continue
		var a: Vector2=path[i-1]; var b: Vector2=path[i]
		var accepted := true
		for j in range(1,density+1):
			accepted=controller.append_path_sample(a.lerp(b,float(j)/density)).is_empty() and accepted
		_check("path_append_all_"+str(density),accepted)
	controller.end_stroke()
	var result := []
	var frame := 0
	while controller.buffer_points()>0:
		controller.begin_frame(frame); frame+=1
		while true:
			var part: Dictionary=controller.peek_segment()
			if part.is_empty(): break
			result.append(part)
			controller.acknowledge_admission(part,result.size())
			controller.settle_command(result.size(),preview.generation)
	_check("path_drained",controller.state==&"settled" and controller.outstanding==0)
	return result

func run_case(name: String, path: Array, params: Dictionary, density: int=1, comparison: String="", heap_after_begin: bool=false, frames_between_commands: int=0) -> void:
	stroke_serial+=1; sample_index=0
	var before := await wall_snapshot(name+"_before")
	var source_before: float=preview.domain.sand_source_m3
	_check(name+"_baseline_ready",(await preview.begin_shape_stroke(stroke_serial)).is_empty())
	var baseline_source: Dictionary=before
	if heap_after_begin:
		var legacy := {"domain_id":preview.domain.domain_id,"generation":preview.generation,"sim_tick":preview.completed_ticks,"command_id":preview.command_queue.last_command_id+1,"kind":&"place_sand","shape":&"circle","transform":{"position_m":Vector3(path[0].x,0,path[0].y)},"radius_m":0.3,"strength":1.0,"amount_m3":0.3,"seed":101}
		_check("heap_legacy_admitted",preview.input_scheduler.submit(legacy).is_empty())
		await settle()
		_check("heap_legacy_applied",preview.input_scheduler.terminal[-1].result.get("status")==1)
		before=await wall_snapshot(name+"_heap_before")
		source_before=preview.domain.sand_source_m3
	var steps := path_commands(path,density,params)
	var commands := []
	var first_submit_us := Time.get_ticks_usec()
	for part in steps:
		var value := BrushProtocol.make_command(&"wall_v1",params,part.start_xz_m,part.end_xz_m,preview.domain.domain_id,preview.generation,preview.command_queue.last_command_id+1,stroke_serial,part.sample_index,preview.completed_ticks,preview.shape_baseline_token)
		var error: StringName=preview.input_scheduler.submit(value)
		_check(name+"_admitted",error.is_empty(),String(error))
		await settle()
		var result: Dictionary=preview.input_scheduler.terminal[-1].result
		_check(name+"_applied_or_no_change",result.get("status") in [1,2],result)
		commands.append({"start":[part.start_xz_m.x,part.start_xz_m.y],"end":[part.end_xz_m.x,part.end_xz_m.y],"params":params.duplicate(true),"result":result,"sample_index":part.sample_index})
		for frame in frames_between_commands: await process_frame
	var after := await wall_snapshot(name+"_after")
	_check(name+"_published_exact",after.sand.sha256==after.published_sand.sha256)
	_check(name+"_end",(await preview.end_shape_stroke()).is_empty())
	var center: Vector2=(path[0]+path[-1])*0.5
	var camera_target := Vector3(center.x,0.2,center.y)
	preview.player_camera.position=camera_target+Vector3(-2.5,2.5,3.5)
	preview.player_camera.look_at(camera_target,Vector3.UP)
	await process_frame; await process_frame
	root.get_texture().get_image().save_png(output.path_join(name+".png"))
	cases.append({"name":name,"before":before,"baseline_source":baseline_source,"after":after,"commands":commands,"params":params,"density":density,"comparison":comparison,"source_before":source_before,"source_after":preview.domain.sand_source_m3,"tick":preview.completed_ticks,"generation":preview.generation,"camera_position":preview.player_camera.position,"camera_target":camera_target,"heap_after_begin":heap_after_begin,"frames_between_commands":frames_between_commands,"first_submit_us":first_submit_us,"finished_us":Time.get_ticks_usec()})

func negatives() -> void:
	stroke_serial+=1; sample_index=0
	_check("negative_baseline",(await preview.begin_shape_stroke(stroke_serial)).is_empty())
	var before := await snapshot("invalid_before")
	var highwater: int=preview.command_queue.last_command_id
	var value := command(Vector2(15.75,0),Vector2(15.875,0))
	_check("whole_footprint_boundary_rejected",preview.input_scheduler.submit(value)==&"out_of_domain")
	value=command(Vector2.ZERO,Vector2(1,0)); value.height_m=NAN
	_check("nan_rejected",preview.input_scheduler.submit(value)==&"invalid_command")
	value=command(Vector2.ZERO,Vector2(1,0)); value.top_width_m=1.5
	_check("invalid_top_width_rejected",preview.input_scheduler.submit(value)==&"invalid_command")
	var after := await snapshot("invalid_after")
	_check("admission_negatives_27_exact",exact(before,after) and preview.command_queue.last_command_id==highwater)
	var budget := await submit(command(Vector2(3,3),Vector2(4,3),true))
	_check("wall_budget_rejected",budget.get("status")==3 and budget.get("error_code")==9,budget)
	var rejected := await snapshot("budget_after")
	_check("budget_negative_27_exact",exact(after,rejected))
	_check("negative_end",(await preview.end_shape_stroke()).is_empty())

func _run() -> void:
	root.size=Vector2i(1280,720)
	var standard := {"height_m":0.3,"bottom_width_m":1.0,"top_width_m":0.5}
	if not await open_lab("dry_flat"): _finish(); quit(1); return
	await run_case("default_line",[Vector2(-6,-6),Vector2(-4,-6)],standard)
	await run_case("minimum",[Vector2(-6,-3),Vector2(-4,-3)],{"height_m":0.15,"bottom_width_m":1.0,"top_width_m":0.5})
	await run_case("maximum",[Vector2(-6,0),Vector2(-4,0)],{"height_m":0.6,"bottom_width_m":2.0,"top_width_m":1.5})
	await run_case("equal_width",[Vector2(-6,3),Vector2(-4,3)],{"height_m":0.3,"bottom_width_m":1.0,"top_width_m":1.0})
	await run_case("short",[Vector2(-6,6),Vector2(-5.875,6)],standard)
	await run_case("stationary",[Vector2(4,-6),Vector2(4,-6)],standard,240)
	await run_case("corner90",[Vector2(1,-6),Vector2(3,-6),Vector2(3,-4)],standard)
	await run_case("corner45",[Vector2(1,-2),Vector2(3,-2),Vector2(4,-1)],standard)
	await run_case("acute",[Vector2(1,2),Vector2(3,2),Vector2(1.5,2.125)],standard)
	await run_case("crossing",[Vector2(7,-2),Vector2(9,0),Vector2(7,0),Vector2(9,-2)],standard)
	await run_case("out_and_back",[Vector2(7,3),Vector2(9,3),Vector2(7,3)],standard)
	await run_case("new_stroke",[Vector2(7,3),Vector2(9,3)],standard)
	await run_case("invalid_subpath_gap",[Vector2(-2,6),Vector2(0,6),null,Vector2(2,6),Vector2(4,6)],standard)
	await run_case("higher_current_heap",[Vector2(3,8),Vector2(5,8)],standard,1,"",true)
	await negatives()
	var retention_before := await wall_snapshot("retention_before")
	await _ticks(5)
	var retention_after := await wall_snapshot("retention_after")
	var retention := {"before":retention_before,"after":retention_after,"ticks":5,"simulation_delta_s":1.0/30.0,"scope":"unmolded wall ordinary simulation baseline for T04; not a geometry oracle"}
	await preview.shutdown(); preview.queue_free(); preview=null
	for i in 4: await process_frame
	if not await open_lab("dry_slope"): _finish(); quit(1); return
	await run_case("slope_existing_heap",[Vector2(-1,0),Vector2(1,0)],standard)
	await run_case("slope_second_stroke",[Vector2(-1,0),Vector2(1,0)],standard)
	await preview.shutdown(); preview.queue_free(); preview=null
	for i in 4: await process_frame
	for density in [30,60,240]:
		if not await open_lab("dry_flat"): _finish(); quit(1); return
		await run_case("density_"+str(density),[Vector2(-2,0),Vector2(0,0),Vector2(0,2),Vector2(2,2)],standard,density,"same_path")
		await preview.shutdown(); preview.queue_free(); preview=null
		for i in 4: await process_frame
	if not await open_lab("dry_flat"): _finish(); quit(1); return
	await run_case("density_60_slow",[Vector2(-2,0),Vector2(0,0),Vector2(0,2),Vector2(2,2)],standard,60,"same_path",false,6)
	await preview.shutdown(); preview.queue_free(); preview=null
	for i in 4: await process_frame
	var file := FileAccess.open(output.path_join("wall_evidence.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"cases":cases,"labs":lab_records,"retention_observation":retention,"raw_index":raw_index,"cell_size_m":0.125,"grid_size":256,"seed":101,"scope":"paused wall geometry and source; full wet and molded retention are later gates"},"\t")); file.close()
	_finish(); var ok := true
	for row in checks: ok=ok and row.pass
	quit(0 if ok else 1)

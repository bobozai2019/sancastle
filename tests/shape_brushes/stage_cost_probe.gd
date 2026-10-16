extends "res://tests/shape_brushes/soak_cost_probe.gd"

var memory_phases := []

func actual_action(tool:String,pos:Vector3) -> void:
	preview.observe_gpu_wait_phases=true
	preview.gpu_wait_phases.clear()
	await super.actual_action(tool,pos)
	actions[-1].wait_phases=preview.gpu_wait_phases.duplicate(true)
	actions[-1].gpu_events=preview.gpu_events.duplicate(true)
	# A frame drawn after completion is observable; it does not prove changed pixels.
	await RenderingServer.frame_post_draw
	actions[-1].post_complete_draw_us=Time.get_ticks_usec()

func mark_memory(phase:String) -> void:
	memory_phases.append({"phase":phase,"at_us":Time.get_ticks_usec(),"memory_static":Performance.get_monitor(Performance.MEMORY_STATIC),"objects":Performance.get_monitor(Performance.OBJECT_COUNT),"generation":preview.generation,"shape":preview.shape_gpu.statistics(),"query_rids":preview.preview_query.owned.size(),"readback_bytes":retained_bytes(readbacks)})

func retained_bytes(state:Dictionary) -> int:
	var total:=0
	for value in state.values():
		if value is PackedByteArray:total+=value.size()
	return total

func restore_cycle(index:int) -> void:
	preview.playing=false
	while preview.busy or preview.tick_pending:await process_frame
	mark_memory("before_capture_%d" % index)
	var anchor:=await snapshot("stage_anchor_%d" % index)
	mark_memory("after_capture_%d" % index)
	var path:=output.path_join("stage_cycle_%d.scp" % index)
	var error:StringName=await preview.save_gpu_checkpoint(path)
	_check("stage_save_%d" % index,error.is_empty(),String(error))
	mark_memory("after_save_%d" % index)
	if error.is_empty():
		error=await preview.restore_gpu_checkpoint(path)
		_check("stage_restore_%d" % index,error.is_empty(),String(error))
		mark_memory("after_restore_%d" % index)
		var restored:=await snapshot("stage_restored_%d" % index)
		_check("stage_restore_exact_%d" % index,exact(anchor,restored))
		restored.clear()
	anchor.clear();readbacks.clear()
	for frame in 10:await process_frame
	mark_memory("after_clear_%d" % index)
	preview.playing=true

func _run() -> void:
	root.size=Vector2i(1280,720);pair_fields=27;process_frame.connect(frame_sample)
	preview=load("res://scenes/main.tscn").instantiate();preview.playing=false;root.add_child(preview);current_scene=preview
	var deadline:=Time.get_ticks_msec()+90000
	while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	_check("stage_ready",preview.ready_for_ticks,preview.last_error)
	if not preview.ready_for_ticks:_finish();quit(1);return
	await physics_frame;await physics_frame
	var initial:=await snapshot("stage_initial");var centers:=find_centers(initial)
	_check("stage_eligible_centers",not centers.is_empty())
	initial.clear();readbacks.clear()
	if centers.is_empty():await preview.shutdown();_finish();quit(1);return
	mark_memory("initial_cleared")
	preview.playing=true
	var warm_end:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<warm_end:await process_frame
	measure_start=Time.get_ticks_usec();previous_frame=measure_start;measuring=true
	var initial_tick:int=preview.completed_ticks;var sequence:=0;var next_action:=measure_start;var next_sample:=measure_start;var cycles:=0
	while Time.get_ticks_usec()-measure_start<90000000 and preview.last_error.is_empty():
		var now:=Time.get_ticks_usec()
		if now>=next_action:
			await actual_action(["Castle","Wall","Shovel"][sequence%3],centers[(sequence/3)%centers.size()])
			sequence+=1;next_action=Time.get_ticks_usec()+8000000
		if now>=next_sample:samples.append(resource_sample());next_sample=now+500000
		if cycles<3 and now-measure_start>20000000*(cycles+1):
			await restore_cycle(cycles);cycles+=1
		await process_frame
	measuring=false;preview.playing=false
	while preview.busy or preview.tick_pending:await process_frame
	samples.append(resource_sample());mark_memory("final")
	_check("stage_three_restore_cycles",cycles==3)
	_check("stage_no_runtime_error",preview.last_error.is_empty(),preview.last_error)
	var observed:={};var success:={}
	for sample in samples:
		for key in sample.hud.get("stage_details",{}):observed[key]=true
	for action in actions:
		for event in action.events:
			if event.terminal.result.get("status")==1:success[action.tool]=true
	_check("stage_actual_tools",success.has("Castle") and success.has("Wall") and success.has("Shovel"),success)
	_check("stage_material_timestamp",observed.has("sandcastle_material"),observed.keys())
	var own_material:=false;var own_water:=false
	for key in observed:
		own_material=own_material or key.begins_with("edit_shape_material_")
		own_water=own_water or key.begins_with("edit_shape_water_")
	_check("stage_shape_material_water_timestamps",own_material and own_water)
	var file:=FileAccess.open(output.path_join("stage_cost.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"round":2,"frames_ms":frames,"samples":samples,"actions":actions,"memory_phases":memory_phases,"initial_tick":initial_tick,"final_tick":preview.completed_ticks,"duration_us":Time.get_ticks_usec()-measure_start,"window":[1280,720],"vsync":DisplayServer.window_get_vsync_mode(),"adapter":RenderingServer.get_video_adapter_name(),"api":RenderingServer.get_video_adapter_api_version(),"source_signature":preview.source_signature,"missing_metrics":["first_changed_pixel_timestamp","complete_global_RID_count"],"scope":"Representative full workload stage attribution and three restore cycles; drawn frame timestamp does not establish first visible pixels; original 5-minute soak not repeated"},"\t"));file.close()
	await preview.get_node("Interface/PerformancePanel").stop_sampling();await preview.shutdown();_check("stage_release",preview.gpu_release_done and preview.preview_query==null)
	preview.queue_free();await process_frame;_finish()
	var passed:=true
	for row in checks:passed=passed and row.pass
	quit(0 if passed else 1)

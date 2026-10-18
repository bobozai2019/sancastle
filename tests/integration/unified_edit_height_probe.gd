extends "res://tests/integration/unified_edit_suspended_probe.gd"

var surface
var height_event_stream: Array[Dictionary]=[]
var height_event_seen: Dictionary={}

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument=="--case=height_long":pipeline=preload("res://tests/integration/unified_edit_timed_pipeline.gd").new()
	super._initialize()

func _process(delta: float) -> bool:
	super._process(delta)
	if probe_case=="height_long":
		for event in pipeline.heights.events:
			var key:=JSON.stringify(event).sha256_text()
			if height_event_seen.has(key):continue
			height_event_seen[key]=true
			var row: Dictionary=event.duplicate(true);row.observed_us=Time.get_ticks_usec();height_event_stream.append(row)
	return false

func _additional_sources() -> PackedStringArray:
	return PackedStringArray(["res://scripts/simulation/unified_edit/height_surface.gd","res://scenes/unified_edit_height_surface.tscn","res://tests/integration/unified_edit_timed_pipeline.gd"])

func _configure_domain() -> void:
	domain.water.fill(0.15);domain.obstacle.fill(0.0)

func _extra_buffer_fields() -> Dictionary:return {"height_dirty":[pipeline.heights.dirty,1040],"publication_stamp":[pipeline.state.published_stamp,32]}

func _extra_image_fields() -> Dictionary:
	var images:=super._extra_image_fields();images.published_water=pipeline.state.published_water;return images

func settle_heights() -> void:
	var deadline:=Time.get_ticks_msec()+15000
	while Time.get_ticks_msec()<deadline:
		if pipeline.heights.active_count()==0 and not pipeline.heights.hinted:break
		await process_frame
	check("height_settled_"+str(checks.size()),pipeline.heights.active_count()==0 and not pipeline.heights.hinted)
	await physics_frame;await physics_frame

func bed_request(id: int, amount: float=0.01) -> Dictionary:
	var command:=request(id,&"fill_v1",Vector2(0.0625,0.0625),amount)
	command.parameters.radius_m=0.01
	return command

func capture_surface(label: String) -> Dictionary:
	var heights:=PackedFloat32Array()
	for chunk in 64:
		var shape: HeightMapShape3D=surface.shapes[chunk].shape
		if shape==null:check("all_shapes_ready_"+label,false);return {}
		heights.append_array(shape.map_data)
	var path: String=output.get_base_dir()+"/"+label+"_surface.bin"
	FileAccess.open(path,FileAccess.WRITE).store_buffer(heights.to_byte_array())
	return {"path":path,"bytes":heights.size()*4,"sha256":FileAccess.get_sha256(path),"versions":pipeline.heights.applied_state_seq.duplicate(),"ticks":pipeline.heights.applied_tick.duplicate(),"revisions":pipeline.heights.applied_revision.duplicate(),"shape_updates":surface.shape_updates,"unchanged_skips":surface.unchanged_skips}

func ray_height() -> float:
	return ray_at(Vector2(0.0625,0.0625))

func ray_at(point: Vector2) -> float:
	var query:=PhysicsRayQueryParameters3D.create(Vector3(point.x,10,point.y),Vector3(point.x,-10,point.y),1)
	var hit: Dictionary=surface.get_world_3d().direct_space_state.intersect_ray(query)
	check("ray_hit_"+str(checks.size()),not hit.is_empty())
	return -100.0 if hit.is_empty() else hit.position.y

func suspended() -> void:
	surface=load("res://scenes/unified_edit_height_surface.tscn").instantiate();root.add_child(surface)
	surface.consumer=pipeline.heights;pipeline.heights.proxy=surface;pipeline.heights.notify_complete()
	await settle_heights()
	check("fixed_64_shape_nodes",surface.shapes.size()==64 and surface.shape_allocations==64)
	observations.initial={"physical":await snapshot("initial"),"surface":capture_surface("initial"),"ray":ray_height()}
	var first_event:=pipeline.heights.events.size()
	pipeline.heights.hold_readbacks=true
	expect("corner_first",await perform("corner_first",bed_request(1)),L.Outcome.APPLIED)
	var deadline:=Time.get_ticks_msec()+10000
	while pipeline.heights.held.size()<2 and Time.get_ticks_msec()<deadline:await process_frame
	check("two_height_slots_saturated",pipeline.heights.active_count()==2 and pipeline.heights.held.size()==2)
	var stale_ray:=ray_height()
	expect("corner_newer",await perform("corner_newer",bed_request(2,0.02)),L.Outcome.APPLIED)
	check("work_drains_without_height_ack",pipeline.active_count()==0 and pipeline.completed_state_seq==2 and pipeline.heights.active_count()==2)
	check("held_physics_is_stale",absf(stale_ray-observations.initial.ray)<0.00001 and absf(ray_height()-stale_ray)<0.00001)
	observations.held={"physical":await snapshot("held"),"ray":stale_ray,"height_slots":pipeline.heights.slots.duplicate(true)}
	pipeline.heights.deliver_held(true)
	await settle_heights()
	observations.corner={"physical":await snapshot("corner"),"surface":capture_surface("corner"),"ray":ray_height(),"events":pipeline.heights.events.slice(first_event)}
	for chunk in [27,28,35,36]:check("newer_corner_version_"+str(chunk),pipeline.heights.applied_state_seq[chunk]==2)
	var rebuilt:=[]
	for chunk in 64:
		if pipeline.heights.applied_state_seq[chunk]>0:rebuilt.append(chunk)
	check("only_4_chunks_rebuilt",rebuilt==[27,28,35,36])
	check("new_height_reaches_ray",observations.corner.ray>observations.initial.ray+1.0)
	var compact:=request(3,&"compact_v1",Vector2(5,5));compact.parameters={"radius_m":0.5,"strength":0.5}
	expect("material",await perform("material",compact),L.Outcome.APPLIED)
	var zero:=bed_request(4);zero.parameters.strength=0.0
	expect("zero",await perform("zero",zero),L.Outcome.NO_CHANGE)
	var rejected:=bed_request(5);rejected.authorization={"available_m3":0.0}
	expect("reject",await perform("reject",rejected),L.Outcome.REJECTED,L.ErrorCode.BUDGET_EXCEEDED)
	await settle_heights()
	check("material_nochange_reject_do_not_rebuild_height",surface.shape_updates==observations.corner.surface.shape_updates)
	observations.no_bed={"physical":await snapshot("no_bed"),"surface":capture_surface("no_bed")}
	if probe_case=="height_faults":await faults()
	if probe_case=="height_erosion":await erosion()
	if probe_case=="height_flow":await flow()
	if probe_case=="height_batch":await batch_boundaries()
	if probe_case=="height_coverage":await cumulative_coverage()
	if probe_case=="height_long":await long_stroke()
	await _consumer_extension()
	observations.final_events=pipeline.heights.events.duplicate(true)
	pipeline.heights.close();surface.consumer=null;pipeline.heights.proxy=null
	surface.queue_free();await process_frame

func _consumer_extension() -> void:pass

func cumulative_coverage() -> void:
	serial=pipeline._highwater
	expect("coverage_begin",await perform("coverage_begin",control_identity(),"begin"),L.Outcome.NO_CHANGE)
	expect("coverage_old",await perform("coverage_old",shape_request(&"wall_v1",Vector2(-10,0),Vector2(-8,0),1)),L.Outcome.APPLIED)
	await settle_heights()

	var point:=Vector2(-8.9375,0.0625)
	var old:={"physical":await snapshot("coverage_old_settled"),"surface":capture_surface("coverage_old"),"ray":ray_at(point)}
	serial+=1
	var dig:=request(serial,&"dig_v1",point,0.04);dig.parameters.radius_m=0.4
	expect("coverage_dig",await perform("coverage_dig",dig),L.Outcome.APPLIED)
	await settle_heights()
	var dug:={"physical":await snapshot("coverage_dug_settled"),"surface":capture_surface("coverage_dug"),"ray":ray_at(point)}
	check("coverage_old_bed_really_lowered",dug.ray<old.ray-0.01)
	expect("coverage_stationary",await perform("coverage_stationary",shape_request(&"wall_v1",Vector2(4,0),Vector2(4,0),2)),L.Outcome.NO_CHANGE)
	pipeline.heights.hold_readbacks=true
	expect("coverage_far_restores",await perform("coverage_far_restores",shape_request(&"wall_v1",Vector2(4,0),Vector2(6,0),3)),L.Outcome.APPLIED)
	var deadline:=Time.get_ticks_msec()+10000
	while pipeline.heights.held.size()<2 and Time.get_ticks_msec()<deadline:await process_frame
	check("coverage_heights_borrowed",pipeline.heights.held.size()==2)
	var late:={"physical":await snapshot("coverage_late"),"ray":ray_at(point),"slots":pipeline.heights.slots.duplicate(true)}
	check("coverage_collision_waits_for_real_consumer",absf(late.ray-dug.ray)<0.00001)
	pipeline.heights.deliver_held(true);await settle_heights()
	var restored:={"physical":await snapshot("coverage_restored"),"surface":capture_surface("coverage_restored"),"ray":ray_at(point)}
	check("coverage_old_collision_restored",absf(restored.ray-old.ray)<0.00001)
	observations.coverage={"old":old,"dug":dug,"late":late,"restored":restored,"state_seq":pipeline.completed_state_seq,"events":pipeline.heights.events.duplicate(true),"point_cell":Vector2i(56,128)}
	expect("coverage_repeat",await perform("coverage_repeat",shape_request(&"wall_v1",Vector2(4,0),Vector2(6,0),4)),L.Outcome.NO_CHANGE)
	expect("coverage_end",await perform("coverage_end",control_identity(),"end"),L.Outcome.NO_CHANGE)
	await settle_heights()


func long_stroke() -> void:
	for id in range(1,6):pipeline.take_result(id)
	serial=pipeline._highwater
	expect("long_begin",await perform("long_begin",control_identity(),"begin"),L.Outcome.NO_CHANGE)
	pipeline.take_result(serial)
	var before:=await snapshot("long_before")
	var windows:=[];var results:=[];var commands:=[]
	var sample:=0;var pending_peak:=0;var work_peak:=0;var height_peak:=0
	var open_start:=Time.get_ticks_usec()
	for window in 12:
		pipeline.heights.hold_physics=window<3
		var tick_before:=pipeline.completed_tick
		var ids:=[];var queued_start:=Time.get_ticks_usec()
		for offset in 25:
			if offset==12:check("long_tick_admitted_"+str(window),pipeline.request_tick(0.004).is_empty())
			sample+=1
			var t0:=float(sample-1)*TAU/300.0;var t1:=float(sample)*TAU/300.0
			var a:=Vector2(6.0*cos(t0),4.0+6.0*sin(t0));var b:=Vector2(6.0*cos(t1),4.0+6.0*sin(t1))
			var command:=shape_request(&"wall_v1",a,b,sample)
			command.features.water_policy=3
			command.sim_tick=tick_before+(1 if offset>=12 else 0)
			check("long_segment_admitted_"+str(sample),pipeline.submit_intent(command).accepted)
			ids.append(command.command_id);commands.append(command.duplicate(true))
		pending_peak=maxi(pending_peak,pipeline.pending_count())
		pipeline.pump();work_peak=maxi(work_peak,pipeline.active_count());height_peak=maxi(height_peak,pipeline.heights.active_count())
		await await_idle()
		for id in ids:
			var value:=pipeline.take_result(id);results.append(value)
			check("long_segment_terminal_"+str(id),not value.is_empty() and value.error_code==0 and value.outcome in [L.Outcome.APPLIED,L.Outcome.NO_CHANGE])
		var clock:={"window":window,"tick_before":tick_before,"tick_after":pipeline.completed_tick,"state_seq":pipeline.completed_state_seq,"actual_time_s":pipeline.advanced_time_s,"queued_start_us":queued_start,"observed_complete_us":Time.get_ticks_usec(),"height_slots":pipeline.heights.active_count(),"pending":pipeline.pending_count(),"stroke_still_open":true}
		windows.append(clock)
		check("long_water_advances_before_end_"+str(window),clock.tick_after==tick_before+1 and clock.actual_time_s>0.0)
		if window<3:check("long_worker_backpressure_keeps_water_running_"+str(window),pipeline.heights.active_count()==2)
		await process_frame
	var before_end:=await snapshot("long_before_end")
	var end:=control_identity();end.sim_tick=pipeline.completed_tick
	expect("long_end",await perform("long_end",end,"end"),L.Outcome.NO_CHANGE);pipeline.take_result(serial)
	pipeline.heights.hold_physics=false;await settle_heights()
	observations.long={"before":before,"before_end":before_end,"after":await snapshot("long_after"),"surface":capture_surface("long"),"commands":commands,"results":results,"windows":windows,"open_start_us":open_start,"open_end_us":Time.get_ticks_usec(),"queue_peak":pending_peak,"work_slots_peak":work_peak,"height_slots_peak":height_peak,"state_seq":pipeline.completed_state_seq,"tick":pipeline.completed_tick,"revision":pipeline.completed_revision,"sample_count":sample,"queued_us":pipeline.queued_us.duplicate(),"recorded":pipeline.recorded.duplicate(true),"consumed":pipeline.consumed.duplicate(true),"height_events":height_event_stream.duplicate(true),"final_reservations":pipeline.result_reservations()}
	check("long_300_samples_12_ticks",sample==300 and pipeline.completed_tick==12 and pipeline.result_reservations()==0)

func faults() -> void:
	var deadline:=Time.get_ticks_msec()+10000
	pipeline.heights.inject_readback_failure_once=true
	expect("unknown",await perform("unknown",bed_request(6)),L.Outcome.APPLIED)
	while not _has_unknown() and Time.get_ticks_msec()<deadline:await process_frame
	check("unknown_retains_real_height_lease",_has_unknown() and pipeline.heights.active_count()>0)
	observations.unknown={"slots":pipeline.heights.slots.duplicate(true),"events":pipeline.heights.events.duplicate(true)}
	pipeline.heights.retry_readbacks();await settle_heights()
	for pair in [[7,"nan"],[8,"identity"],[9,"truncate"]]:
		var before:=pipeline.heights.invalid_results
		pipeline.heights.inject_packet_fault_once=pair[1]
		expect("bad_"+pair[1],await perform("bad_"+pair[1],bed_request(pair[0])),L.Outcome.APPLIED)
		await settle_heights()
		check("bad_packet_requeued_"+pair[1],pipeline.heights.invalid_results==before+1)
	observations.recovered={"physical":await snapshot("recovered"),"surface":capture_surface("recovered"),"ray":ray_height(),"invalid_results":pipeline.heights.invalid_results}

func _has_unknown() -> bool:
	for slot in pipeline.heights.slots:
		if slot.phase in [&"read_unknown",&"ack_unknown"]:return true
	return false

func erosion() -> void:
	var before:=await snapshot("erosion_before")
	check("coupled_tick_admitted",pipeline.request_tick(0.001).is_empty());await await_idle();await settle_heights()
	var after:=await snapshot("erosion_after")
	check("real_tick_changes_bed",before.sand0.sha256!=after.sand0.sha256)
	observations.erosion={"before":before,"after":after,"surface":capture_surface("erosion"),"state_seq":pipeline.completed_state_seq,"tick":pipeline.completed_tick,"revision":pipeline.completed_revision,"events":pipeline.heights.events.duplicate(true)}

func flow() -> void:
	for id in range(1,6):check("take_initial_"+str(id),not pipeline.take_result(id).is_empty())
	check("result_reservations_empty",pipeline.result_reservations()==0)
	for id in range(6,518):
		check("reserve_cancel_"+str(id),pipeline.submit_intent(bed_request(id)).accepted and pipeline.cancel_pending(id))
	check("bounded_512_terminal_results",pipeline.result_reservations()==512 and pipeline._results.size()==512)
	var blocked:=pipeline.submit_intent(bed_request(518))
	check("terminal_backpressure_preserves_history",not blocked.accepted and blocked.error==&"results_backpressure" and not pipeline.result(6).is_empty())
	check("take_detaches_terminal",pipeline.take_result(6).cancelled and pipeline.take_result(6).is_empty() and pipeline.result_reservations()==511)
	check("admission_resumes_after_consumption",pipeline.submit_intent(bed_request(518)).accepted and pipeline.cancel_pending(518))
	for id in range(7,519):check("take_cancel_"+str(id),pipeline.take_result(id).cancelled)
	check("all_terminal_capacity_recovered",pipeline.result_reservations()==0 and pipeline._results.is_empty())
	observations.result_history={"capacity":Pipeline.MAX_RESULTS,"cancelled_and_consumed":513,"pending":pipeline.pending_count(),"reservations":pipeline.result_reservations()}
	pipeline.heights.hold_readbacks=true
	expect("flow_seed",await perform("flow_seed",bed_request(519)),L.Outcome.APPLIED)
	var deadline:=Time.get_ticks_msec()+10000
	while pipeline.heights.held.size()<2 and Time.get_ticks_msec()<deadline:await process_frame
	check("flow_height_slots_held",pipeline.heights.held.size()==2)
	var before:=await snapshot("flow_before")
	var first_seq:=pipeline.completed_state_seq
	var publications_before: int=pipeline.state.publication_count
	pipeline.hold_completions=true
	var ids:=[]
	for index in 63:
		if index==32:check("flow_real_tick",pipeline.request_tick(0.001).is_empty())
		var id:=520+index;ids.append(id)
		var command:=bed_request(id)
		command.start_xz_m=Vector2((float(16+index*3)+0.5-128.0)*0.125,0.0625)
		command.sim_tick=0 if index<32 else 1
		check("flow_admit_"+str(id),pipeline.submit_intent(command).accepted)
	check("flow_queue_exact_bound",pipeline.pending_count()==64)
	pipeline.pump()
	check("flow_three_work_units_record_ahead",pipeline.active_count()==3 and pipeline.pending_count()==0)
	deadline=Time.get_ticks_msec()+15000
	while Time.get_ticks_msec()<deadline:
		var done:=0
		for index in L.WORK_SLOTS:
			if pipeline.slots.slot_snapshot(index).state==Pipeline.Slots.State.GPU_COMPLETE:done+=1
		if done==3:break
		await process_frame
	check("flow_cpu_has_not_authorized_successors",pipeline.completed_state_seq==first_seq and pipeline.completed_tick==0)
	var gpu_completed:=await snapshot("flow_gpu_completed")
	var publications_after: int=pipeline.state.publication_count
	check("flow_one_publication_per_work",publications_after-publications_before==3)
	pipeline.hold_completions=false;await await_idle()
	check("flow_tick_advances_with_both_height_slots_held",pipeline.completed_tick==1 and pipeline.completed_state_seq==first_seq+3 and pipeline.heights.active_count()==2)
	var results:=[]
	for id in ids:
		var value:=pipeline.take_result(id);results.append(value)
		check("flow_independent_result_"+str(id),not value.is_empty() and value.outcome==L.Outcome.APPLIED)
	check("flow_seed_result_consumed",not pipeline.take_result(519).is_empty())
	pipeline.heights.deliver_held(true);await settle_heights()
	observations.flow={"before":before,"gpu_completed":gpu_completed,"after":await snapshot("flow_after"),"surface":capture_surface("flow"),"state_seq":pipeline.completed_state_seq,"tick":pipeline.completed_tick,"revision":pipeline.completed_revision,"first_state_seq":first_seq,"results":results,"queue_peak":64,"work_slots_peak":3,"height_slots_peak":2,"events":pipeline.heights.events.duplicate(true),"final_reservations":pipeline.result_reservations(),"publications_before":publications_before,"publications_after":publications_after}
	check("flow_all_results_consumed",pipeline.result_reservations()==0)

func _near_revision_end_render() -> void:
	pipeline.transport.rd.buffer_update(pipeline.transport.control,40,8,PackedInt64Array([L.INT64_MAX-1]).to_byte_array())
	call_deferred("_snapshot_armed")

func batch_boundaries() -> void:
	var before:=await snapshot("batch_reject_before")
	var first_seq:=pipeline.completed_state_seq
	var publications: int=pipeline.state.publication_count
	var rejected:=bed_request(6);rejected.authorization={"available_m3":0.0}
	var successor:=bed_request(7);successor.start_xz_m=Vector2(4.0625,0.0625)
	pipeline.hold_completions=true
	check("batch_reject_admission",pipeline.submit_intent(rejected).accepted)
	check("batch_successor_admission",pipeline.submit_intent(successor).accepted)
	pipeline.pump()
	check("batch_reject_single_work",pipeline.active_count()==1 and pipeline.pending_count()==0)
	var deadline:=Time.get_ticks_msec()+10000
	while Time.get_ticks_msec()<deadline:
		var done:=false
		for index in L.WORK_SLOTS:done=done or pipeline.slots.slot_snapshot(index).state==Pipeline.Slots.State.GPU_COMPLETE
		if done:break
		await process_frame
	check("batch_reject_no_cpu_authorization",pipeline.completed_state_seq==first_seq and pipeline.result(6).is_empty() and pipeline.result(7).is_empty())
	var after:=await snapshot("batch_reject_after")
	pipeline.hold_completions=false;await await_idle();await settle_heights()
	expect("batch_first_business_reject",pipeline.result(6),L.Outcome.REJECTED,L.ErrorCode.BUDGET_EXCEEDED)
	expect("batch_successor_applies",pipeline.result(7),L.Outcome.APPLIED)
	check("batch_only_one_publication",pipeline.state.publication_count-publications==1)
	observations.batch_reject={"before":before,"after":after,"results":[pipeline.result(6),pipeline.result(7)],"first_state_seq":first_seq,"publications":pipeline.state.publication_count-publications,"surface":capture_surface("batch_reject")}
	pipeline.heights.close()
	armed_snapshot=false;RenderingServer.call_on_render_thread(_near_revision_end_render)
	while not armed_snapshot:await process_frame
	before=await snapshot("batch_fatal_before")
	for index in 3:
		var command:=bed_request(8+index)
		command.start_xz_m=Vector2((float([192,64,80][index])+0.5-128.0)*0.125,0.0625)
		check("batch_fatal_admission_"+str(index),pipeline.submit_intent(command).accepted)
	pipeline.pump()
	deadline=Time.get_ticks_msec()+10000
	while pipeline.fault_reason().is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	check("mid_batch_revision_fatal",not pipeline.fault_reason().is_empty())
	after=await snapshot("batch_fatal_after")
	check("fatal_no_fabricated_completions",pipeline.result(8).is_empty() and pipeline.result(9).is_empty() and pipeline.result(10).is_empty())
	check("fatal_after_last_valid_command",FileAccess.get_file_as_bytes(after.sand0.path).decode_float((128*256+192)*4)>FileAccess.get_file_as_bytes(before.sand0.path).decode_float((128*256+192)*4))
	check("fatal_preserves_last_complete_publication",before.published.sha256==after.published.sha256 and before.published_water.sha256==after.published_water.sha256 and before.publication_stamp.sha256==after.publication_stamp.sha256)
	observations.batch_fatal={"before":before,"after":after,"fault":String(pipeline.fault_reason()),"completed_state_seq":pipeline.completed_state_seq,"recorded_commands":pipeline.executor.recorded_commands}
	pipeline.cleanup_fault()
	deadline=Time.get_ticks_msec()+10000
	while pipeline.active_count()>0 and Time.get_ticks_msec()<deadline:await process_frame
	check("batch_fatal_real_terminal_reclaimed",pipeline.active_count()==0 and not pipeline.transport.has_owned())

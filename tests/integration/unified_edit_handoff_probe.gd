extends "res://tests/integration/unified_edit_restore_probe.gd"

const Runtime=preload("res://scripts/simulation/unified_edit/domain_runtime.gd")
var runtime
var viewport
var transition: Dictionary={}
var saved: Dictionary={}
var preview: Dictionary={}
var owners: Array=[]
var baseline_pixel: Color
var visual_viewport
const POINT=Vector2(8.0625,0.0625)

func _process(_delta: float) -> bool:return false

func _run() -> void:
	started=Time.get_ticks_msec();DisplayServer.window_set_size(Vector2i(1280,720));DisplayServer.window_set_title("Unified domain consumer handoff")
	var created: Dictionary=load("res://assets/unified_edit/default_catalog.tres").instantiate_registry();registry=created.registry;check("registry",created.error.is_empty())
	var extra:=PackedStringArray(Pipeline.SOURCE_PATHS+Pipeline.ADAPTER_SOURCES+Runtime.SOURCES)
	extra.append_array(PackedStringArray([get_script().resource_path,"res://tests/integration/unified_edit_restore_probe.gd","res://tests/fixtures/unified_edit/view_consumer.tscn","res://tests/fixtures/unified_edit/view_consumer.gdshader","res://tests/fixtures/unified_edit/visual_consumer.tscn","res://tests/fixtures/unified_edit/visual_consumer.gdshader"]))
	var enabled_visuals:=probe_case in ["handoff_visuals","handoff_boundary"]
	var enabled_boundary:=probe_case=="handoff_boundary"
	var environment:={"engine":Engine.get_version_info().string,"probe":probe_case}
	if enabled_boundary:environment.boundary=Pipeline.Boundary.for_scene("main_beach")
	var frozen:=Config.freeze(registry,"main_beach",{"enable_erosion":enabled_boundary,"enable_brush_water":true,"unrestricted_sand_tools":true,"enable_structures":false,"local_front_history":enabled_visuals,"rise_front_history":false,"contact_history":false},{"foam_enabled":enabled_visuals,"gravel_enabled":enabled_visuals},{},environment,extra)
	check("configuration",frozen.error.is_empty());configuration=frozen.value;source_hashes=configuration.sources.duplicate(true)
	runtime=load("res://scenes/unified_edit_runtime.tscn").instantiate();root.add_child(runtime)
	viewport=load("res://tests/fixtures/unified_edit/view_consumer.tscn").instantiate();root.add_child(viewport)
	var plan: Array=[]
	for name in ["Bed","Water","Preview"]:plan.append({"material":viewport.get_node(name).material,"parameters":{"sand_state":"sand","water_state":"water","compaction_state":"compaction","wetness_state":"wetness","sediment_state":"sediment","qx_state":"momentum_x","rock_state":"rock","stroke_baseline":"baseline","async_clock":"clock"}})
	if enabled_visuals:
		visual_viewport=load("res://tests/fixtures/unified_edit/visual_consumer.tscn").instantiate();root.add_child(visual_viewport)
		for name in ["Foam","Front","Gravel"]:plan.append({"material":visual_viewport.get_node(name).material,"parameters":{"foam_state":"foam","front_state":"local_front","gravel_state":"gravel"}})
	domain=Domain.new(256,0.125);domain.domain_id=&"main_beach";domain.generation=9007199254740993
	domain.rock.fill(0.05);domain.sand.fill(0.25);domain.water.fill(0.1);domain.wetness.fill(0.1);domain.compaction.fill(0.3)
	check("boot_admitted",runtime.boot(registry,configuration,domain,plan,_transition).is_empty());await wait_transition()
	check("boot_ready",transition.get("error",&"missing")==&"" and runtime.ready_for_input())
	if runtime.current==null:await close_runtime();finish();return
	pipeline=runtime.current;owners.append(pipeline)
	await physics_frame;await physics_frame
	check("boot_ray",absf(ray_height()-0.3)<0.00001)
	baseline_pixel=await pixel("initial")
	if enabled_visuals:observations.visual_initial=await visual_pixels("initial")
	var selection:={"policy":0,"speed":0.0,"brush":{"tool":&"place_sand","parameters":{},"dig_amount_m3":0.05,"fill_amount_m3":0.05}}
	var path:=output.get_base_dir()+"/baseline.sandue"
	check("save_admitted",runtime.save_checkpoint(path,selection,func(value: Dictionary):saved=value).accepted)
	var begin:=Time.get_ticks_msec()
	while saved.is_empty() and Time.get_ticks_msec()-begin<15000:await process_frame
	check("save_complete",saved.get("error",&"missing")==&"")
	var loaded:=Codec.load(path,configuration);check("load_checkpoint",loaded.error.is_empty())
	if not loaded.error.is_empty():await close_runtime();finish();return
	var checkpoint: Dictionary=loaded.checkpoint
	observations.container={"path":path,"sha256":FileAccess.get_sha256(path)}
	for id in range(1,7):
		var edit:=request(id,&"fill_v1",POINT,0.02);check("edit_"+str(id),runtime.submit_intent(edit).accepted);await await_idle()
	if enabled_boundary:
		check("runtime_wave_admitted",runtime.request_wave({"domain_id":"main_beach","generation":runtime.generation(),"request_id":1,"start_tick":1,"profile_id":&"small_packet","amplitude_m":0.05,"duration_s":0.5,"seed":73}).accepted)
	if enabled_visuals:check("visual_tick",runtime.request_tick(0.001).is_empty());await await_idle()
	await settle_physics()
	var old_height:=ray_height();var old_pixel:=await pixel("edited")
	check("old_visible_and_physics_changed",old_height>0.30001 and old_pixel.r>baseline_pixel.r)
	if enabled_visuals:observations.visual_edited=await visual_pixels("edited")
	var old=pipeline;var old_epoch: int=runtime.generation()
	if probe_case=="handoff_capacity":
		for id in range(7,513):check("retained_cancel_"+str(id),runtime.submit_intent(request(id,&"fill_v1",POINT)).accepted and old.cancel_pending(id))
	if probe_case in ["handoff_unknown","handoff_upload"]:
		RenderingServer.call_on_render_thread(_inject_old_failure.bind(old,probe_case=="handoff_unknown"))
		await process_frame;await process_frame
		check("old_failed_work_admitted",runtime.submit_intent(request(7,&"fill_v1",Vector2(-4,-3))).accepted)
		begin=Time.get_ticks_msec()
		while old.fault_reason().is_empty() and Time.get_ticks_msec()-begin<10000:await process_frame
		check("old_recording_fault_observed",not old.fault_reason().is_empty())
	if probe_case=="handoff_preview":
		old.views.hold_delivery=true
		check("preview_accepted",runtime.request_preview(request(100,&"fill_v1",POINT),func(value: Dictionary):preview=value).accepted)
		begin=Time.get_ticks_msec()
		while old.views.held.is_empty() and Time.get_ticks_msec()-begin<10000:await process_frame
		check("preview_actually_held",not old.views.held.is_empty())
	if probe_case=="handoff_detach":old.views.inject_detach_failure_once=true
	if probe_case=="handoff_preflight":runtime.inject_commit_validation_failure=true
	if probe_case=="handoff_initialize":runtime.inject_candidate_initialization_after=&"views"
	transition={};check("restore_admitted",runtime.restore_checkpoint(checkpoint,_transition).is_empty())
	check("transition_gates_input",runtime.submit_intent(request(101,&"fill_v1",POINT)).error==&"transition_busy")
	if probe_case=="handoff_cancel":check("cancel_admitted",runtime.cancel_restore())
	var staged=runtime.candidate;owners.append(staged)
	var old_unchanged:=true;begin=Time.get_ticks_msec()
	while transition.is_empty() and Time.get_ticks_msec()-begin<25000:
		if runtime.current==old:old_unchanged=old_unchanged and absf(ray_height()-old_height)<0.00001 and not runtime.surfaces[1-runtime.current_index].collision_enabled
		await process_frame
	check("old_ray_preserved_before_commit",old_unchanged)
	if probe_case in ["handoff_preflight","handoff_initialize","handoff_cancel"]:
		check("failure_reported",not transition.is_empty() and not transition.error.is_empty())
		check("old_domain_preserved",runtime.current==old and runtime.generation()==old_epoch and absf(ray_height()-old_height)<0.00001 and runtime.ready_for_input())
		check("failed_candidate_released",staged.released)
		check("old_pixel_preserved",(await pixel("failure")).is_equal_approx(old_pixel))
	else:
		check("restore_committed",transition.get("error",&"missing")==&"" and runtime.current==staged and runtime.generation()==old_epoch+1 and runtime.current.completed_state_seq==checkpoint.state_seq)
		pipeline=runtime.current;await physics_frame;await physics_frame
		check("new_ray_restored",absf(ray_height()-0.3)<0.00001)
		check("new_pixel_restored",(await pixel("restored")).is_equal_approx(baseline_pixel))
		if enabled_visuals:
			observations.visual_restored=await visual_pixels("restored")
			check("enabled_effects_actual_materials_restored",observations.visual_initial.pixel==observations.visual_restored.pixel and observations.visual_edited.pixel!=observations.visual_initial.pixel)
		if enabled_boundary:check("restored_runtime_boundary_and_wave_registry",runtime.current.water.boundary_enabled and runtime.current.boundary.highwater==0 and runtime.current.boundary.requests.is_empty())
		await verify_maps(checkpoint)
		if probe_case=="handoff_preview":
			check("old_preview_keeps_owner",not old.released and old.views.pending and runtime.retired.size()==1)
			check("second_restore_blocked_until_retired",runtime.restore_checkpoint(checkpoint,_transition)==&"transition_busy")
			old.views.deliver_held()
			await process_frame;await process_frame
			check("late_preview_rejected",preview.get("error")==&"stale_generation")
		if probe_case=="handoff_detach":
			for frame in 12:await process_frame
			check("unknown_detach_retains_owner",not old.released and not old.views.detached_confirmed and runtime.retired.size()==1)
			runtime.retry_retirement()
		await wait_retired()
		var expected_count:=512 if probe_case=="handoff_capacity" else (7 if probe_case in ["handoff_unknown","handoff_upload"] else 6)
		check("old_results_survive_rid_release",old.released and runtime.result_reservations()==expected_count)
		if probe_case=="handoff_capacity":
			var blocked:=request(1,&"fill_v1",POINT);blocked.generation=runtime.generation()
			check("cross_generation_capacity_512",runtime.submit_intent(blocked).error==&"results_backpressure" and pipeline.result_reservations()==0)
		for id in range(1,7):check("old_result_"+str(id),runtime.take_result(old_epoch,id).get("outcome")==L.Outcome.APPLIED)
		if probe_case=="handoff_capacity":
			for id in range(7,513):check("old_cancel_"+str(id),runtime.take_result(old_epoch,id).get("cancelled",false))
		if probe_case in ["handoff_unknown","handoff_upload"]:
			var terminal: Dictionary=runtime.take_result(old_epoch,7);observations.fault_terminal=terminal
			check("honest_old_terminal_without_gpu_outcome",not terminal.has("outcome") and terminal.get("submitted",false)==(probe_case=="handoff_unknown") and terminal.error==(&"recorded_result_unknown" if probe_case=="handoff_unknown" else &"aborted_before_recording"))
		check("old_result_capacity_returned",runtime.result_reservations()==0)
		var loops:=10 if probe_case=="handoff_repeat" else 1
		for iteration in loops:
			var edit:=request(1,&"fill_v1",POINT,0.02);edit.generation=runtime.generation()
			check("continuation_"+str(iteration),runtime.submit_intent(edit).accepted);await await_idle();await settle_physics()
			transition={};check("reused_slot_restore_"+str(iteration),runtime.restore_checkpoint(checkpoint,_transition).is_empty());owners.append(runtime.candidate)
			await wait_transition();pipeline=runtime.current;await physics_frame;await physics_frame
			check("reused_slot_old_lower_seq_"+str(iteration),transition.get("error",&"missing")==&"" and pipeline.completed_state_seq==0 and absf(ray_height()-0.3)<0.00001)
			await wait_retired()
	observations.events=runtime.events.duplicate(true);observations.archived_results=runtime.terminal_archive.duplicate(true)
	await close_runtime();finish()

func _transition(value: Dictionary) -> void:transition=value

func _inject_old_failure(subject, recorded: bool) -> void:
	if recorded:subject.transport.inject_readback_failure_once=true
	else:subject.transport.inject_upload_failure_once=true

func wait_transition() -> void:
	var begin:=Time.get_ticks_msec()
	while transition.is_empty() and Time.get_ticks_msec()-begin<25000:await process_frame
	check("transition_terminal_"+str(checks.size()),not transition.is_empty())

func wait_retired() -> void:
	var begin:=Time.get_ticks_msec()
	while not runtime.retired.is_empty() and Time.get_ticks_msec()-begin<12000:await process_frame
	check("retirement_terminal_"+str(checks.size()),runtime.retired.is_empty())

func settle_physics() -> void:
	var begin:=Time.get_ticks_msec()
	while (pipeline.heights.active_count()!=0 or pipeline.heights.hinted) and Time.get_ticks_msec()-begin<15000:await process_frame
	check("physics_settled_"+str(checks.size()),pipeline.heights.active_count()==0 and not pipeline.heights.hinted)

func ray_height() -> float:
	var query:=PhysicsRayQueryParameters3D.create(Vector3(POINT.x,5,POINT.y),Vector3(POINT.x,-5,POINT.y),1)
	var hit: Dictionary=runtime.get_world_3d().direct_space_state.intersect_ray(query)
	return -999.0 if hit.is_empty() else hit.position.y

func pixel(label: String) -> Color:
	await RenderingServer.frame_post_draw;await RenderingServer.frame_post_draw
	var image: Image=viewport.get_texture().get_image();var path:=output.get_base_dir()+"/"+label+".png"
	check("png_"+label,image.save_png(path)==OK)
	observations[label]={"path":path,"sha256":FileAccess.get_sha256(path),"bed":image.get_pixel(8,8)}
	return image.get_pixel(8,8)

func verify_maps(checkpoint: Dictionary) -> void:
	var maps:=PackedByteArray();var valid:=true
	var rock: PackedFloat32Array=checkpoint.native.fields.rock.to_float32_array();var sand: PackedFloat32Array=checkpoint.native.fields.sand.to_float32_array()
	var active=runtime.surfaces[runtime.current_index]
	for chunk in 64:
		var heights: PackedFloat32Array=active.shapes[chunk].shape.map_data;maps.append_array(heights.to_byte_array())
		valid=valid and active.applied_revisions.get(chunk)==checkpoint.state_seq and active.generation==runtime.generation()
		for z in 33:
			for x in 33:
				var at: int=mini(255,(chunk/8)*32+z)*256+mini(255,(chunk%8)*32+x)
				valid=valid and heights[z*33+x]==PackedFloat32Array([rock[at]+sand[at]])[0]
	check("all_64_maps_match_saved_generation",valid)
	observations.physics=save_fields({"maps":maps},"restored")

func close_runtime() -> void:
	runtime.shutdown();var begin:=Time.get_ticks_msec()
	while not runtime.closed and Time.get_ticks_msec()-begin<15000:await process_frame
	check("runtime_closed",runtime.closed)
	observations.final_ownership=[]
	for owner in owners:
		observations.final_ownership.append(owner.ownership_counts());check("all_nested_owners_released_"+str(checks.size()),owner.released)
	viewport.queue_free();runtime.queue_free();await process_frame
	if visual_viewport!=null:visual_viewport.queue_free();await process_frame

func visual_pixels(label: String) -> Dictionary:
	await RenderingServer.frame_post_draw;await RenderingServer.frame_post_draw
	var image: Image=visual_viewport.get_texture().get_image();var path:=output.get_base_dir()+"/visual_"+label+".png"
	check("visual_png_"+label,image.save_png(path)==OK)
	return {"path":path,"sha256":FileAccess.get_sha256(path),"pixel":image.get_pixel(8,8)}

func finish() -> void:
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"pass":not failed,"case":probe_case,"checks":checks,"observations":observations,"source_hashes":source_hashes,"engine":Engine.get_version_info(),"scope":"Two fixed consumer slots; real GPU materials, 64 physics maps, ray queries and native checkpoint handoff. Disabled effects only; no formal entry/cost claim."},"\t"));quit(1 if failed else 0)

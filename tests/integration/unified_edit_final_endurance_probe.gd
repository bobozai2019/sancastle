extends "res://tests/integration/unified_edit_playable_probe.gd"

const Routes=preload("res://scripts/beach/unified_scene_routes.gd")
const Presentation=preload("res://scripts/simulation/unified_edit/presentation.gd")
var all_results: Array=[]
var interactions: Array=[]
var resource_samples: Array=[]

func _entry_path(key: String) -> String:return Routes.FORMAL[key]

func _run() -> void:
	orphan_baseline=int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	DisplayServer.window_set_size(Vector2i(1280,720));DisplayServer.window_set_title("Unified final mixed interaction and lifecycle")
	scene=load(_entry_path("main")).instantiate();scene.playing=false;scene.generation=1001;root.add_child(scene)
	var start:=Time.get_ticks_msec()
	while not scene.ready_for_ticks and scene.last_error.is_empty() and Time.get_ticks_msec()-start<180000:await process_frame
	check("formal_main_ready",scene.ready_for_ticks and scene.last_error.is_empty())
	if not scene.ready_for_ticks:await _close();return
	observations.sources=scene.configuration.sources.duplicate(true)
	observations.initial_configuration=scene.configuration.duplicate(true)
	var data:=Presentation.read(scene.presentation_manifest);var seed:=Presentation.initial_domain(data.metadata,1001)
	var wet:=Vector2.ZERO;var depth:=-1.0
	for z in range(32,224):
		for x in range(32,224):
			if seed.domain.water[z*256+x]>depth:depth=seed.domain.water[z*256+x];wet=Vector2((x+.5)*.125-16,(z+.5)*.125-16)
	observations.wet_point={"x":wet.x,"z":wet.y,"initial_depth":depth}
	var tools: Array[StringName]=[&"place_sand",&"remove_sand",&"wall_v1",&"shovel_v1",&"castle_v1",&"smooth_v1",&"compact_v1",&"suspended_sand",&"gravel_drop"]
	var mixed_start:=Time.get_ticks_msec();var next_input:=mixed_start;var next_sample:=mixed_start;var ordinal:=0
	var tick_before: int=scene.runtime.current.completed_tick
	while Time.get_ticks_msec()-mixed_start<181000 or interactions.is_empty() or interactions.back().elapsed_ms<180000:
		var now:=Time.get_ticks_msec()
		# Alternating real-time and frozen editing exercise the same clock owner.
		scene.playing=(int((now-mixed_start)/15000)%2)==0
		if now>=next_input:
			var tool: StringName=tools[ordinal%tools.size()]
			var point:=wet if tool==&"suspended_sand" else Vector2(3.0+float((ordinal/9)%3)*0.5,float((ordinal/27)%3)*0.5)
			var parameters: Dictionary={}
			if tool in [&"wall_v1",&"shovel_v1",&"castle_v1",&"smooth_v1",&"compact_v1"]:parameters=scene.registry.profile(tool).defaults.duplicate(true)
			if tool==&"wall_v1":parameters.height_m=0.2;parameters.bottom_width_m=1.0;parameters.top_width_m=0.5
			if tool==&"shovel_v1":parameters.depth_m=0.05;parameters.trench_width_m=0.5;parameters.shoulder_width_m=0.5
			if tool==&"gravel_drop":parameters={"count":2}
			var before: int=scene.runtime.highwater()
			var admitted: Dictionary=scene.input.begin(tool,point,parameters,0.015,3,0.0)
			var moved: Dictionary={"accepted":true,"skipped":true}
			if admitted.accepted and tool!=&"castle_v1":moved=scene.input.move(point+Vector2(0.25,0.1))
			var ended: Dictionary=scene.input.finish()
			interactions.append({"ordinal":ordinal,"elapsed_ms":now-mixed_start,"tool":tool,"point":point,"begin":admitted,"move":moved,"end":ended,"generation":scene.generation,"first_id":before+1,"last_id":scene.runtime.highwater(),"completed_tick":scene.runtime.current.completed_tick,"advanced_time_s":scene.runtime.current.advanced_time_s,"playing":scene.playing})
			check("mixed_admission_"+str(ordinal),admitted.accepted and moved.accepted and ended.accepted)
			ordinal+=1;next_input=now+500
		_drain_results()
		if now>=next_sample:
			var owner=scene.runtime.current
			resource_samples.append({"elapsed_ms":now-mixed_start,"ownership":owner.ownership_counts(),"pending":owner.pending_count(),"active":owner.active_count(),"height_active":owner.heights.active_count(),"results_reserved":scene.runtime.result_reservations(),"memory_bytes":Performance.get_monitor(Performance.MEMORY_STATIC),"render_objects":Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)})
			next_sample=now+5000
		if not scene.runtime.current.fault_reason().is_empty():check("no_fatal_during_mixed",false);break
		await process_frame
	scene.playing=false;await _idle();_drain_results()
	observations.interaction_elapsed_ms=Time.get_ticks_msec()-mixed_start
	check("three_minutes_actual_mixed_window",observations.interaction_elapsed_ms>=180000 and interactions.size()>=300 and interactions.back().elapsed_ms>=180000)
	check("actual_water_ticks_during_interaction",scene.runtime.current.completed_tick>tick_before+10)
	check("all_mixed_commands_have_real_terminal",all_results.size()==scene.runtime.highwater())
	var legal:=true;var applied:=0
	for row in all_results:
		legal=legal and row.has("outcome") and row.outcome in [L.Outcome.APPLIED,L.Outcome.NO_CHANGE,L.Outcome.REJECTED] and row.get("invalid_flags",0)==0
		if row.get("outcome")==L.Outcome.APPLIED:applied+=1
	check("honest_mixed_results_without_invalid_or_unknown",legal and applied>100)
	observations.interactions=interactions;observations.mixed_results=all_results;observations.resource_samples=resource_samples
	observations.rounds=[]
	var service=root.get_node("BeachScenes");service.session_directory=output+"/sessions";DirAccess.make_dir_recursive_absolute(service.session_directory)
	for iteration in 10:
		var owner=scene.runtime.current;var epoch: int=scene.generation
		check("round_open_stroke_"+str(iteration),scene.input.begin(&"wall_v1",Vector2(3,2),{"height_m":0.2,"bottom_width_m":1.0,"top_width_m":0.5},0.015,3,0.0).accepted)
		var path:=output+"/round_"+str(iteration)+".sandue"
		check("round_save_"+str(iteration),(await scene.save_gpu_checkpoint(path)).is_empty() and scene.input.gesture.is_empty())
		var loaded:=Codec.load(path,scene.configuration);check("round_valid_container_"+str(iteration),loaded.error.is_empty())
		if not loaded.error.is_empty():break
		var saved_seq: int=loaded.checkpoint.state_seq
		check("round_edit_after_save_"+str(iteration),scene.input.begin(&"place_sand",Vector2(3,0),{},0.015,3,0.0).accepted);scene.input.finish();await _idle()
		check("round_restore_"+str(iteration),(await scene.restore_gpu_checkpoint(path)).is_empty())
		start=Time.get_ticks_msec()
		while not scene.runtime.retired.is_empty() and Time.get_ticks_msec()-start<30000:await process_frame
		check("round_new_epoch_and_retirement_"+str(iteration),scene.generation==epoch+1 and scene.runtime.current.completed_state_seq==saved_seq and owner.released)
		var profile: Dictionary=scene.registry.profile(&"fill_v1")
		var stale:={"domain_id":scene._domain_id(),"generation":epoch,"command_id":scene.runtime.highwater()+1,"sim_tick":scene.runtime.current.completed_tick,"profile_id":&"fill_v1","profile_version":profile.version,"profile_hash":profile.profile_hash,"start_xz_m":Vector2(3,0),"parameters":profile.defaults.duplicate(true),"features":{"water_policy":3},"seed":101}
		check("round_stale_epoch_rejected_"+str(iteration),not scene.runtime.submit_intent(stale).accepted)
		var leaving=scene.runtime.current
		var target: String="test1_capture" if scene.scene_key=="main" else "main"
		check("round_switch_"+str(iteration),service.request_switch(target))
		start=Time.get_ticks_msec()
		while service.busy and Time.get_ticks_msec()-start<180000:await process_frame
		scene=service.active_scene
		check("round_switch_ready_"+str(iteration),not service.busy and service.last_error.is_empty() and scene!=null and scene.scene_file_path==_entry_path(target))
		check("round_closed_previous_backend_"+str(iteration),leaving.released and leaving.ownership_counts().values().all(func(value):return value==0))
		for source in scene.configuration.sources:observations.sources[source]=scene.configuration.sources[source]
		observations.rounds.append({"iteration":iteration,"path":path,"sha256":FileAccess.get_sha256(path),"saved_state_seq":saved_seq,"old_generation":epoch,"restored_generation":epoch+1,"target":target,"restored_owner_zero":owner.ownership_counts(),"switched_owner_zero":leaving.ownership_counts(),"current_ownership":scene.runtime.current.ownership_counts(),"configuration_hash":scene.configuration.configuration_hash})
	check("ten_full_lifecycle_rounds",observations.rounds.size()==10 and service.release_records.size()>=10)
	observations.release_records=service.release_records.duplicate(true)
	await RenderingServer.frame_post_draw
	check("final_visible_frame",root.get_texture().get_image().save_png(output+"/final.png")==OK)
	await _close()

func _drain_results() -> void:
	all_results.append_array(scene.input.terminal.duplicate(true));scene.input.terminal.clear()

func finish() -> void:
	FileAccess.open(output+"/probe.json",FileAccess.WRITE).store_string(JSON.stringify({"pass":not failed,"checks":checks,"observations":observations,"scope":"Formal visible main, timed real mixed inputs and water clock, then ten save/restore/switch/close rounds; lifecycle duration excluded from interaction duration. No cost acceptance."},"\t"));quit(1 if failed else 0)

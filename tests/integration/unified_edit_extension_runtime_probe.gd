extends "res://tests/integration/unified_edit_handoff_probe.gd"

func _run() -> void:
	started=Time.get_ticks_msec();DisplayServer.window_set_size(Vector2i(1280,720))
	var created: Dictionary=load("res://assets/unified_edit/extensions/extension_catalog.tres").instantiate_registry()
	check("extension_registry",created.error.is_empty());registry=created.registry
	var extra:=PackedStringArray(Pipeline.SOURCE_PATHS+Pipeline.ADAPTER_SOURCES+Runtime.SOURCES)
	extra.append_array(PackedStringArray([get_script().resource_path,"res://tests/integration/unified_edit_handoff_probe.gd","res://tests/integration/unified_edit_restore_probe.gd","res://tests/fixtures/unified_edit/view_consumer.tscn","res://tests/fixtures/unified_edit/view_consumer.gdshader"]))
	var frozen:=Config.freeze(registry,"main_beach",{"enable_erosion":false,"enable_brush_water":true,"unrestricted_sand_tools":true,"enable_structures":false,"local_front_history":false,"rise_front_history":false,"contact_history":false},{"foam_enabled":false,"gravel_enabled":false},{},{"engine":Engine.get_version_info().string,"fixture":"g7_extension_runtime"},extra)
	check("configuration",frozen.error.is_empty());configuration=frozen.value;source_hashes=configuration.sources.duplicate(true)
	runtime=load("res://scenes/unified_edit_runtime.tscn").instantiate();root.add_child(runtime)
	viewport=load("res://tests/fixtures/unified_edit/view_consumer.tscn").instantiate();root.add_child(viewport)
	var plan: Array=[]
	for name in ["Bed","Water","Preview"]:plan.append({"material":viewport.get_node(name).material,"parameters":{"sand_state":"sand","water_state":"water","compaction_state":"compaction","wetness_state":"wetness","sediment_state":"sediment","qx_state":"momentum_x","rock_state":"rock","stroke_baseline":"baseline","async_clock":"clock"}})
	domain=Domain.new(256,0.125);domain.domain_id=&"main_beach";domain.generation=9007199254740993
	domain.rock.fill(0.05);domain.sand.fill(0.25);domain.water.fill(0.1);domain.wetness.fill(0.2);domain.compaction.fill(0.4)
	check("common_boot",runtime.boot(registry,configuration,domain,plan,_transition).is_empty());await wait_transition()
	check("boot_ready",transition.get("error",&"missing")==&"" and runtime.ready_for_input())
	if runtime.current==null:await close_runtime();finish();return
	pipeline=runtime.current;owners.append(pipeline);await physics_frame;await physics_frame
	var initial_ray:=ray_height();check("initial_collision",absf(initial_ray-0.3)<0.00001)
	observations.results=[];observations.commands=[]
	pipeline.heights.hold_physics=true
	var id:=1
	for profile_id in [&"wide_fill_v1",&"stepped_mound_tool_v1",&"wide_transfer_v1"]:
		var profile: Dictionary=registry.profile(profile_id)
		var stroke: bool=profile.stroke_policy!=0
		if stroke:check("begin_"+String(profile_id),runtime.submit_control("begin",_control(id)).accepted);id+=1
		var value:=_extension_command(id,profile)
		check("admitted_"+String(profile_id),runtime.submit_intent(value).accepted)
		var sample_id:=id;id+=1
		if stroke:check("end_"+String(profile_id),runtime.submit_control("end",_control(id)).accepted);id+=1
		await await_idle()
		var result:=pipeline.result(sample_id)
		check("applied_before_collision_"+String(profile_id),result.get("outcome")==L.Outcome.APPLIED and absf(ray_height()-initial_ray)<0.00001)
		observations.results.append(result);observations.commands.append(value)
	observations.trace=pipeline.executor.traces.duplicate(true)
	pipeline.heights.hold_physics=false;await settle_physics();await physics_frame;await physics_frame
	var edited_ray:=ray_height();check("collision_converged_to_extensions",edited_ray>initial_ray+0.05)
	observations.rays={"initial":initial_ray,"edited":edited_ray}
	var selection:={"policy":0,"speed":0.0,"brush":{"tool":&"place_sand","parameters":{},"dig_amount_m3":0.05,"fill_amount_m3":0.05}}
	var path:=output.get_base_dir()+"/extensions.sandue"
	check("save_admitted",runtime.save_checkpoint(path,selection,func(value: Dictionary):saved=value).accepted)
	var begin:=Time.get_ticks_msec()
	while saved.is_empty() and Time.get_ticks_msec()-begin<20000:await process_frame
	check("saved_common_container",saved.get("error",&"missing")==&"")
	var loaded:=Codec.load(path,configuration);check("native_load",loaded.error.is_empty())
	if not loaded.error.is_empty():await close_runtime();finish();return
	var checkpoint: Dictionary=loaded.checkpoint
	observations.container={"path":path,"sha256":FileAccess.get_sha256(path),"configuration_hash":configuration.configuration_hash,"state_seq":checkpoint.state_seq}
	# Unchanged live chunks legitimately retain an older completed version;
	# restore rebuilds all 64 chunks at the checkpoint's complete version.
	check("live_collision_versions_not_future",runtime.surfaces[runtime.current_index].applied_revisions.values().all(func(version):return version<=checkpoint.state_seq))
	var old=pipeline;var old_epoch: int=runtime.generation()
	transition={};check("restore_admitted",runtime.restore_checkpoint(checkpoint,_transition).is_empty());owners.append(runtime.candidate)
	await wait_transition();pipeline=runtime.current;await physics_frame;await physics_frame
	check("common_restore_new_epoch",transition.get("error",&"missing")==&"" and runtime.generation()==old_epoch+1 and pipeline.completed_state_seq==checkpoint.state_seq)
	check("collision_restored_exact",absf(ray_height()-edited_ray)<0.00001)
	await verify_maps(checkpoint);await wait_retired()
	check("old_owner_released",old.released)
	var continuation_id: int=pipeline.command_highwater()+1
	var continuation:=_extension_command(continuation_id,registry.profile(&"wide_fill_v1"));continuation.generation=runtime.generation()
	check("new_config_continues_after_restore",runtime.submit_intent(continuation).accepted);await await_idle();await settle_physics()
	check("continued_applied",pipeline.result(continuation_id).get("outcome")==L.Outcome.APPLIED)
	observations.events=runtime.events.duplicate(true);observations.restored_generation=runtime.generation()
	await close_runtime();finish()

func _control(id: int) -> Dictionary:return {"domain_id":"main_beach","generation":runtime.generation(),"command_id":id,"sim_tick":0,"stroke_id":101,"baseline_token":101}

func _extension_command(id: int, profile: Dictionary) -> Dictionary:
	var value:={"domain_id":"main_beach","generation":runtime.generation(),"command_id":id,"sim_tick":0,"profile_id":profile.profile_id,"profile_version":profile.version,"profile_hash":profile.profile_hash,"start_xz_m":Vector2.ZERO,"end_xz_m":Vector2.ZERO,"parameters":profile.defaults.duplicate(true),"features":{"water_policy":3},"seed":73}
	if profile.shape==L.Profile.Shape.SWEPT_CAPSULE:value.start_xz_m=Vector2(-0.75,0);value.end_xz_m=Vector2(0.75,0)
	if profile.stroke_policy!=0:value.merge({"stroke_id":101,"baseline_token":101,"sample_index":0})
	return value

func ray_height() -> float:
	var query:=PhysicsRayQueryParameters3D.create(Vector3(0.0625,5,0.0625),Vector3(0.0625,-5,0.0625),1)
	var hit: Dictionary=runtime.get_world_3d().direct_space_state.intersect_ray(query)
	return -999.0 if hit.is_empty() else hit.position.y

extends "res://tests/integration/unified_edit_playable_probe.gd"

var props

func _wait_paused() -> void:
	var deadline:=Time.get_ticks_msec()+20000
	while Time.get_ticks_msec()<deadline:
		if props.holds.has(&"user") and not props.busy and props.expected_steps.is_empty():break
		await process_frame
	check("common_user_hold_"+str(checks.size()),props.holds.has(&"user") and not props.busy and props.expected_steps.is_empty() and props.last_error.is_empty())

func _run_for(seconds: float) -> void:
	var target: float=scene.runtime.current.advanced_time_s+seconds;var deadline:=Time.get_ticks_msec()+20000
	scene.playing=true
	while scene.runtime.current.advanced_time_s<target and props.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	scene.playing=false;await _wait_paused()
	check("real_main_water_and_props_"+str(checks.size()),scene.runtime.current.advanced_time_s>=target and props.last_error.is_empty() and props.admitted_time_s>0)

func _poses() -> Dictionary:
	var result:={}
	for row in props.registry:result[row.body_id]={"transform":row.body.global_transform,"saved":props.saved[row.body_id].duplicate(true)}
	return result

func _run() -> void:
	orphan_baseline=int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT));DisplayServer.window_set_size(Vector2i(1280,720))
	scene=load("res://scenes/main.tscn").instantiate();scene.playing=false;root.add_child(scene);props=scene.get_node("FloatingProps/Service")
	var deadline:=Time.get_ticks_msec()+90000
	while (scene._booting or not scene.ready_for_ticks) and scene.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	check("formal_main_and_static_three_ready",not scene._booting and scene.ready_for_ticks and props.registry.size()==3 and props.last_error.is_empty())
	if scene._booting or not props.active:await _close();return
	observations.sources=scene.configuration.sources.duplicate(true);observations.engine=Engine.get_version_info();observations.initial_layout=props.layout.duplicate(true)
	await _wait_paused()
	for row in props.registry:
		check("prop_collision_layers_"+str(row.body_id),row.body.collision_layer==2 and row.body.collision_mask==3)
		var screen: Vector2=scene.get_viewport().get_camera_3d().unproject_position(row.body.global_position)
		var hit: Dictionary=scene.pick(screen)
		check("brush_picks_terrain_through_prop_"+str(row.body_id),hit.get("collider")==scene.runtime.surfaces[scene.runtime.current_index].get_node("Terrain"))
	await _run_for(2.0)
	var checkpoint_path:=output.get_base_dir()+"/current.sandue"
	var error: StringName=await scene.save_gpu_checkpoint(checkpoint_path);observations.save_error=error
	check("paused_save_succeeds",error.is_empty())
	check("save_releases_only_own_hold",props.holds.has(&"user") and not props.holds.has(&"save"))
	var loaded:=Codec.load(checkpoint_path,scene.configuration)
	check("native_checkpoint_has_no_prop_extension",loaded.error.is_empty() and loaded.checkpoint.visual_extensions.keys()==["gravel_v1"])
	check("existing_file_save_fails",not (await scene.save_gpu_checkpoint(checkpoint_path)).is_empty())
	check("failed_save_keeps_user_hold",props.holds.has(&"user") and not props.holds.has(&"save"))
	var before:=_poses();var old_owner: int=props.owner_token;var old_generation: int=props.generation
	scene.runtime.inject_commit_validation_failure=true
	error=await scene.restore_gpu_checkpoint(checkpoint_path);observations.failed_restore_error=error
	check("candidate_failure_reported",not error.is_empty())
	check("failed_restore_preserves_pose_velocity_sleep",_poses()==before and props.owner_token==old_owner and props.generation==old_generation)
	check("failed_restore_releases_only_own_hold",props.holds.has(&"user") and not props.holds.has(&"restore"))
	scene.runtime.inject_commit_validation_failure=false
	deadline=Time.get_ticks_msec()+20000
	while (scene.runtime.candidate!=null or not scene.runtime.retired.is_empty()) and Time.get_ticks_msec()<deadline:await process_frame
	await _run_for(0.5)
	props.registry[0].body.position.x+=0.25
	error=await scene.restore_gpu_checkpoint(checkpoint_path);observations.restore_error=error
	check("successful_restore",error.is_empty())
	check("new_generation_owner_and_zero_budget",props.generation>old_generation and props.generation==scene.runtime.generation() and props.owner_token==old_owner+1 and props.admitted_time_s==0.0 and props.actual_time.values().all(func(v):return v==0.0))
	for row in props.registry:
		var original: Transform3D=props.layout[row.body_id]
		check("restored_authored_xz_and_velocity_"+str(row.body_id),Vector2(row.body.global_position.x,row.body.global_position.z).distance_to(Vector2(original.origin.x,original.origin.z))<1e-6 and props.saved[row.body_id].linear==Vector3.ZERO and props.saved[row.body_id].angular==Vector3.ZERO)
	check("restored_user_pause_preserved",props.holds.has(&"user") and not props.holds.has(&"restore"))
	await _run_for(0.5)
	await RenderingServer.frame_post_draw
	check("formal_main_three_visible_capture",root.get_texture().get_image().save_png(output.get_base_dir()+"/main.png")==OK)
	observations.props={"generation":props.generation,"owner":props.owner_token,"origin_time_s":props.origin_time_s,"actual":props.actual_time.duplicate(),"admitted":props.admitted_time_s,"poses":_poses(),"events":props.events.duplicate(true)}
	props.set_physics_process(false)
	while props.pending:await process_frame
	var current=scene.runtime.current;current.views.probe.inject_readback_failure_once=true;props._request_sample()
	deadline=Time.get_ticks_msec()+15000
	while not current.views.probe.unknown and Time.get_ticks_msec()<deadline:await process_frame
	check("closing_with_registered_unknown_prop_reader",props.pending and current.views.probe.unknown)
	scene.shutdown();await scene.shutdown()
	check("concurrent_close_reclaims_native_owners",scene.unified_release_complete() and props.closed and not props.pending and current.released and current.ownership_counts().values().all(func(v):return v==0))
	await _close()

func finish() -> void:
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"pass":not failed,"checks":checks,"observations":observations,"scope":"G5 formal main static props, terrain picking, holds, save, failed/successful restore, unknown-reader and concurrent close. No old-source migration or performance acceptance."},"\t"));quit(1 if failed else 0)

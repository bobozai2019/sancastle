extends "res://tests/floating_props/lifecycle_probe.gd"

var ui

func _run() -> void:
	orphan_baseline=int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT));DisplayServer.window_set_size(Vector2i(1280,720))
	scene=load("res://scenes/main.tscn").instantiate();scene.playing=false;root.add_child(scene)
	props=scene.get_node("FloatingProps/Service");ui=scene.get_node("Interface/FloatingPropsPanel")
	props.trace_enabled=true
	var deadline:=Time.get_ticks_msec()+90000
	while (scene._booting or not scene.ready_for_ticks) and scene.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	check("formal_ui_ready",scene.ready_for_ticks and props.active and props.last_error.is_empty())
	if not scene.ready_for_ticks:await _close();return
	await _wait_paused()
	var path:=output.get_base_dir()+"/before.sandue"
	check("before_checkpoint",(await scene.save_gpu_checkpoint(path)).is_empty())
	var before:=Codec.load(path,scene.configuration)
	await process_frame;await process_frame
	props.set_physics_process(false)
	deadline=Time.get_ticks_msec()+10000
	while props.pending and Time.get_ticks_msec()<deadline:await process_frame
	scene.runtime.current.views.probe.inject_readback_failure_once=true;props._request_sample()
	deadline=Time.get_ticks_msec()+10000
	while not scene.runtime.current.views.probe.unknown and Time.get_ticks_msec()<deadline:await process_frame
	check("unknown_reader_retains_placement_lease",props.pending and scene.runtime.current.views.probe.unknown)
	var terminal_before: int=scene.runtime.current.views.probe.completed_count
	var unknown_owner: int=props.owner_token
	props.set_physics_process(true)
	ui.get_node("Margin/Rows/Slots/Slot1").pressed.emit()
	check("static_slot_signal_selects_bottle",ui.selected_body_id==1 and not ui.pickup_mode and scene.input.gesture.is_empty())
	ui.get_node("Margin/Rows/Actions/Pickup").pressed.emit()
	var bottle=props.body_for_id(1)
	var screen: Vector2=scene.get_viewport().get_camera_3d().unproject_position(bottle.global_position)
	check("prop_only_ray_finds_bottle",ui.pick_prop(screen)==1)
	var click:=InputEventMouseButton.new();click.position=screen;click.button_index=MOUSE_BUTTON_LEFT;click.pressed=true
	scene.get_viewport().push_input(click,true)
	deadline=Time.get_ticks_msec()+15000
	while ui.working and Time.get_ticks_msec()<deadline:await process_frame
	check("pickup_click_returns_bottle_to_slot",bottle.in_inventory and not bottle.visible and bottle.collision_layer==0 and bottle.freeze and props.last_error.is_empty())
	check("pickup_waits_for_unknown_reader_terminal",scene.runtime.current.views.probe.completed_count>terminal_before and props.owner_token==unknown_owner+1 and not scene.runtime.current.views.probe.unknown and (not scene.runtime.current.views.probe.pending or scene.runtime.current.views.probe.query.request.owner_token==props.owner_token))
	for id in [2,3]:
		var result: Dictionary=await ui.perform_action(id,Vector2.ZERO,true)
		check("pickup_all_"+str(id),result.error.is_empty() and props.body_for_id(id).in_inventory)
	var duplicate: Dictionary=await ui.perform_action(1,Vector2.ZERO,true)
	check("duplicate_pickup_is_rejected",duplicate.error==&"already_picked_up")
	var request: int=props.request_id;var water: float=scene.runtime.current.advanced_time_s
	scene.playing=true
	deadline=Time.get_ticks_msec()+15000
	while scene.runtime.current.advanced_time_s<water+0.5 and Time.get_ticks_msec()<deadline:await process_frame
	check("empty_world_keeps_water_running",scene.runtime.current.advanced_time_s>water and props.request_id==request and props.last_error.is_empty())
	scene.playing=false;await _wait_paused()
	var isolation_path:=output.get_base_dir()+"/placement_before.sandue"
	check("isolation_boundary_saved",(await scene.save_gpu_checkpoint(isolation_path)).is_empty())
	before=Codec.load(isolation_path,scene.configuration)
	await process_frame;await process_frame
	for id in [1,2,3]:
		ui.get_node("Margin/Rows/Slots/Slot%d"%id).pressed.emit()
		ui.yaw_rad=deg_to_rad(30.0)
		var point:=Vector2(4.5-float(id)*2.0,-4.0)
		var result: Dictionary
		if id==1:
			var camera: Camera3D=scene.get_viewport().get_camera_3d()
			var target_screen:=camera.unproject_position(Vector3(point.x,1.2,point.y))
			var aim: Dictionary=ui.aim_at(target_screen)
			check("world_drop_pointer_has_valid_aim",not aim.is_empty() and aim.error.is_empty())
			if not aim.is_empty():point=Vector2(aim.position.x,aim.position.z)
			var drop_click:=InputEventMouseButton.new();drop_click.position=target_screen;drop_click.button_index=MOUSE_BUTTON_LEFT;drop_click.pressed=true
			scene.get_viewport().push_input(drop_click,true)
			deadline=Time.get_ticks_msec()+15000
			while ui.working and Time.get_ticks_msec()<deadline:await process_frame
			result=ui.last_result
		else:result=await ui.perform_action(id,point,false)
		var body=props.body_for_id(id)
		check("drop_"+str(id),result.error.is_empty() and not body.in_inventory and body.visible and body.collision_layer==2 and body.collision_mask==3)
		check("paused_drop_at_requested_xz_"+str(id),Vector2(body.global_position.x,body.global_position.z).distance_to(point)<0.0001 and body.freeze)
		check("pause_reason_preserved_"+str(id),props.holds.has(&"user") and not props.holds.has(&"interaction"))
	var position_before: Transform3D=bottle.global_transform
	var invalid: Dictionary=await ui.perform_action(1,Vector2(99,0),false)
	check("out_of_domain_no_mutation",invalid.error==&"out_of_domain" and bottle.global_transform==position_before)
	var other: Vector3=props.body_for_id(2).global_position
	invalid=await ui.perform_action(1,Vector2(other.x,other.z),false)
	check("occupied_no_mutation",invalid.error==&"occupied" and bottle.global_transform==position_before)
	check("invalid_body_no_mutation",(await props.manipulate_body(999,Vector2.ZERO)).error==&"invalid_body")
	ui.cancel_mode()
	check("cancel_restores_brush_mode",not ui.has_world_mode())
	ui.select_body(2);scene._on_tool_changed(&"remove_sand")
	check("sand_tool_cancels_placement",not ui.has_world_mode())
	ui.select_body(1)
	var right:=InputEventMouseButton.new();right.button_index=MOUSE_BUTTON_RIGHT;right.pressed=true
	scene.get_viewport().push_input(right,true);await process_frame;await process_frame
	observations.right_cancel={"selected":ui.selected_body_id,"pickup":ui.pickup_mode,"camera_capture":scene.player_camera.look_active,"mouse_mode":Input.mouse_mode}
	check("right_click_cancels_without_camera_capture",not ui.has_world_mode() and not scene.player_camera.look_active and Input.mouse_mode==Input.MOUSE_MODE_VISIBLE)
	var right_release:=InputEventMouseButton.new();right_release.button_index=MOUSE_BUTTON_RIGHT;right_release.pressed=false;scene.get_viewport().push_input(right_release,true)
	ui.select_body(1)
	var rotate:=InputEventKey.new();rotate.keycode=KEY_BRACKETRIGHT;rotate.pressed=true
	scene._unhandled_input(rotate)
	check("rotation_key_belongs_to_prop_mode",is_equal_approx(ui.yaw_rad,deg_to_rad(15)))
	ui.cancel_mode()
	var after_path:=output.get_base_dir()+"/after.sandue"
	check("after_checkpoint",(await scene.save_gpu_checkpoint(after_path)).is_empty())
	var after:=Codec.load(after_path,scene.configuration)
	check("placement_does_not_write_authority",before.error.is_empty() and after.error.is_empty() and before.checkpoint.native==after.checkpoint.native and before.checkpoint.ledger==after.checkpoint.ledger)
	await _run_for(2.0)
	check("placed_props_resume_without_clock_fault",props.last_error.is_empty() and props.world_registry().size()==3 and props.actual_time.values().all(func(value):return value>0))
	await process_frame;await process_frame
	scene.playing=true
	for frame in 12:await process_frame
	check("running_pickup",(await ui.perform_action(1,Vector2.ZERO,true)).error.is_empty() and bottle.in_inventory and scene.playing)
	check("running_drop",(await ui.perform_action(1,Vector2(4.5,-4),false)).error.is_empty() and not bottle.in_inventory and scene.playing)
	await _run_for(0.5)
	for row in props.world_registry():check("body_epoch_clock_"+str(row.body_id),absf(props.actual_time[row.body_id]+props.body_time_origins[row.body_id]-props.admitted_time_s)<0.00001)
	await process_frame;await process_frame
	await ui.perform_action(3,Vector2.ZERO,true)
	var held_pose: Transform3D=bottle.global_transform
	scene.runtime.inject_commit_validation_failure=true
	var failed_restore: StringName=await scene.restore_gpu_checkpoint(after_path)
	check("failed_restore_preserves_inventory_and_pose",not failed_restore.is_empty() and props.body_for_id(3).in_inventory and bottle.global_transform==held_pose)
	scene.runtime.inject_commit_validation_failure=false
	deadline=Time.get_ticks_msec()+20000
	while (scene.runtime.candidate!=null or not scene.runtime.retired.is_empty()) and Time.get_ticks_msec()<deadline:await process_frame
	check("restore_resets_authored_three",(await scene.restore_gpu_checkpoint(after_path)).is_empty() and props.world_registry().size()==3)
	for row in props.registry:
		var pose: Transform3D=props.layout[row.body_id]
		check("restored_slot_"+str(row.body_id),not row.body.in_inventory and Vector2(row.body.global_position.x,row.body.global_position.z).distance_to(Vector2(pose.origin.x,pose.origin.z))<0.0001)
	ui.select_body(1)
	Input.warp_mouse(Vector2(830,300))
	for frame in 12:await process_frame
	await RenderingServer.frame_post_draw
	check("ui_screenshot",root.get_texture().get_image().save_png(output.get_base_dir()+"/placement_ui.png")==OK)
	observations.events=props.events.duplicate(true)
	observations.final_error=props.last_error
	observations.panel_rect=ui.get_global_rect()
	await _close()

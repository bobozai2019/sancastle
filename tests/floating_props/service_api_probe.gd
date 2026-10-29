extends "res://tests/floating_props/contact_probe.gd"

func _scenario_extension() -> Dictionary:
	check("api_user_hold",(await service.set_paused(true,&"user")).error.is_empty())
	check("api_save_hold",(await service.set_paused(true,&"save")).error.is_empty())
	check("api_restore_hold",(await service.set_paused(true,&"restore")).error.is_empty())
	var before: float=service.admitted_time_s;var poses:={}
	for row in service.registry:poses[row.body_id]=row.body.global_transform
	check("api_release_user_only",(await service.set_paused(false,&"user")).error.is_empty() and service.holds.has(&"save") and service.holds.has(&"restore"))
	check("api_water_does_not_wait_on_holds",runtime.request_tick(1.0/30.0).is_empty());await _idle()
	for frame in 8:await physics_frame
	check("api_other_holds_prevent_integration",service.admitted_time_s==before and service.registry.all(func(row):return row.body.freeze and row.body.global_transform==poses[row.body_id]))
	check("api_release_save_only",(await service.set_paused(false,&"save")).error.is_empty() and service.holds.has(&"restore"))
	check("api_reestablish_user",(await service.set_paused(true,&"user")).error.is_empty())
	check("api_restore_release_keeps_user",(await service.set_paused(false,&"restore")).error.is_empty() and service.holds.has(&"user"))
	var operation: int=service.operation_id
	check("api_invalid_reason_rejected",(await service.set_paused(false,&"invalid")).error==&"invalid_registry" and service.operation_id==operation)
	var invalid_layout: Dictionary=service.layout.duplicate(true);invalid_layout.erase(1)
	check("api_invalid_layout_rejected",service._validate(service.registry,invalid_layout)==&"invalid_registry")
	var duplicate: Array=service.registry.duplicate();duplicate.append(service.registry[0])
	check("api_duplicate_registry_rejected",service._validate(duplicate,service.layout)==&"invalid_registry")
	check("api_double_attach_rejected",(await service.attach(runtime,service.registry,service.layout)).error==&"busy")
	var prop: RigidBody3D=service.registry[0].body;var data: Dictionary=service.profiles[1]
	var original: Transform3D=prop.global_transform;var linear:=prop.linear_velocity;var angular:=prop.angular_velocity
	var cloud_poses: Dictionary=service.sample_poses.duplicate(true);cloud_poses[1]=original
	prop.angular_velocity=original.basis.x*12.0;prop.linear_velocity=Vector3.ZERO
	check("api_bounded_axial_roll_allowed",service._motion_within_budget(prop,data))
	prop.angular_velocity=original.basis.z*9.0
	check("api_transverse_spin_still_rejected",not service._motion_within_budget(prop,data))
	prop.angular_velocity=Vector3.ZERO;prop.linear_velocity=Vector3(4.1,0,0)
	check("api_linear_speed_still_rejected",not service._motion_within_budget(prop,data))
	prop.linear_velocity=Vector3.ZERO;prop.global_basis=original.basis*Basis(Vector3.RIGHT,1.0)
	check("api_sample_cloud_ignores_invariant_twist",service._candidate_usable(service.sample,cloud_poses))
	prop.global_basis=original.basis*Basis(Vector3.FORWARD,0.4)
	check("api_observed_direction_angle_still_rejected",not service._candidate_usable(service.sample,cloud_poses))
	prop.global_transform=original;prop.linear_velocity=linear;prop.angular_velocity=angular
	service.set_physics_process(false)
	while service.pending:await process_frame
	var old_request: int=service.request_id
	service.request_id=9223372036854775807;service._request_sample()
	check("api_request_overflow_rejected_without_wrap",service.request_id==9223372036854775807 and service.last_error==&"identity_exhausted")
	service.request_id=old_request;service.last_error=&""
	service.set_physics_process(true)
	service.operation_id=9223372036854775806
	check("api_final_identity_reserved_for_shutdown",(await service.set_paused(false,&"user")).error==&"identity_exhausted" and service.operation_id==9223372036854775806 and service.holds.has(&"user"))
	# Restore test-owned counters so the inherited pause/resume checks remain
	# ordinary operations. The terminal identity itself is checked at close.
	service.operation_id=operation
	check("api_resume_final_budget_before_common_pause",(await service.set_paused(false,&"user")).error.is_empty())
	return {}

func _close() -> void:
	if service.active:
		service.operation_id=9223372036854775806
		var result: Dictionary=await service.shutdown()
		check("api_shutdown_uses_reserved_positive_int64",result.error.is_empty() and result.operation_id==9223372036854775807 and service.closed)
	await super._close()

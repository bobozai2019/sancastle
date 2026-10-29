extends "res://tests/floating_props/contact_probe.gd"

func _target_time() -> float:return 0.0

func _configure_domain(domain) -> void:
	if probe_case=="stack_fill":domain.water.fill(0.0)
	for name in ["Bottle","WoodPlank","WoodStick"]:fixture.get_node(name).rotation=Vector3.ZERO

func _after_attach() -> void:
	var low:=1.3;var high:=1.6
	if probe_case=="stack_fill":low=0.491;high=0.623
	fixture.get_node("Bottle").position=Vector3(0,low,0)
	fixture.get_node("WoodPlank").position=Vector3(0,high,0)
	fixture.get_node("WoodStick").position=Vector3(2,0.436 if probe_case=="stack_fill" else 1.3,0)
	service.sample={};service.sample_history.clear()

func _fill(amount: float) -> void:
	var profile: Dictionary=runtime.registry.profile(&"fill_v1");var id: int=runtime.highwater()+1
	var command:={"domain_id":"main_beach","generation":runtime.generation(),"command_id":id,"sim_tick":runtime.current.completed_tick,"profile_id":&"fill_v1","profile_version":1,"profile_hash":profile.profile_hash,"start_xz_m":Vector2.ZERO,"parameters":{"amount_m3":amount,"radius_m":0.75},"features":{"water_policy":0}}
	var admitted: Dictionary=runtime.submit_intent(command)
	if not observations.has("edit_admissions"):observations.edit_admissions=[]
	observations.edit_admissions.append({"request":command,"result":admitted})
	check("stack_edit_admitted_"+str(id),admitted.accepted);await _idle()
	var sequence: int=runtime.current.completed_state_seq;var deadline:=Time.get_ticks_msec()+15000
	while Time.get_ticks_msec()<deadline:
		if not service.latest_sample.is_empty() and service.latest_sample.captured_state_seq>=sequence and service.pending_support.is_empty() and runtime.current.heights.footprint_ready(service.latest_sample.footprint_versions,service.generation).ready:break
		await process_frame
	check("stack_actual_edit_and_support_"+str(id),runtime.current.result(id).get("outcome")==1 and service.last_error.is_empty() and service.pending_support.is_empty() and service.latest_sample.captured_state_seq>=sequence)

func _scenario_extension() -> Dictionary:
	check("stack_common_pause",(await service.set_paused(true,&"user")).error.is_empty())
	var before:={};var time: float=service.admitted_time_s
	for row in service.registry:before[row.body_id]=row.body.global_transform
	if probe_case=="stack_fill":
		await _fill(0.3)
		var lower: float=service.registry[0].body.global_position.y-before[1].origin.y
		var upper: float=service.registry[1].body.global_position.y-before[2].origin.y
		check("real_terrain_fill_lifts_lower",lower>0.05 and lower<=2.0)
		check("real_upward_obstruction_carries_stack",upper>=lower-0.005 and upper<=2.0)
		_collect_events()
		check("stack_push_has_explicit_cause",full_events.any(func(event):return event.kind==&"edit_recovery" and event.data.query.reason==&"stack_push"))
		for row in service.registry:before[row.body_id]=row.body.global_transform
	var bound_before: Dictionary=service.latest_sample.get("footprint_change_bounds",{}).duplicate()
	var minimum: float=runtime.registry.profile(&"fill_v1").ranges.amount_m3[0]
	for index in 5:await _fill(minimum)
	var temporal_bound:=0.0
	for chunk in bound_before:temporal_bound=maxf(temporal_bound,float(service.latest_sample.footprint_change_bounds[chunk])-float(bound_before[chunk]))
	for row in service.registry:
		var displacement: Vector3=row.body.global_position-before[row.body_id].origin
		check("no_neighbour_leapfrog_"+str(row.body_id),absf(displacement.x)+absf(displacement.z)<1e-6 and displacement.y>=-1e-6 and displacement.y<=temporal_bound+0.005+1e-6)
		if probe_case=="hover_edit":check("hover_above_bed_is_not_recovered_"+str(row.body_id),displacement.length()<1e-6)
	check("all_stack_edits_are_not_physics_time",service.admitted_time_s==time)
	observations.stack={"case":probe_case,"before_small_edits":before,"maximum_real_bed_change_bound_m":temporal_bound,"after":service.registry.map(func(row):return {"body_id":row.body_id,"transform":row.body.global_transform})}
	check("stack_end_resume_for_inherited_clock_check",(await service.set_paused(false,&"user")).error.is_empty())
	return {}

extends "res://tests/floating_props/three_props_probe.gd"

var full_events: Array=[]
var last_event_id:=0
var event_gap:=false
var initial_positions: Dictionary={}

func _process(delta: float) -> bool:
	super._process(delta);_collect_events();return false

func _collect_events() -> void:
	if service==null or not is_instance_valid(service):return
	var fresh: Array=[]
	for index in range(service.events.size()-1,-1,-1):
		var row: Dictionary=service.events[index]
		if row.event_id<=last_event_id:break
		fresh.append(row)
	fresh.reverse()
	for row in fresh:
		if row.event_id!=last_event_id+1:event_gap=true
		full_events.append(row);last_event_id=row.event_id

func _capture_events() -> Array:
	_collect_events();observations.event_capture={"last_id":last_event_id,"gap":event_gap,"ring_evicted":service.events_evicted};return full_events.duplicate()

func _configure_domain(domain) -> void:
	super._configure_domain(domain)
	if probe_case in ["dry_sleep","bed_dig","bed_fill","collision_pair","cross_chunk"]:domain.water.fill(0.0)
	if probe_case=="collision_pair":fixture.get_node("Bottle").position.x=-1.3
	if probe_case=="cross_chunk":
		for pair in [["Bottle",-1.2],["WoodPlank",0.0],["WoodStick",1.2]]:
			var prop=fixture.get_node(pair[0]);prop.position=Vector3(-0.25,0,pair[1]);prop.rotation=Vector3.ZERO
	if probe_case=="erosion_continuous":
		var q:=PackedFloat32Array();q.resize(65536);q.fill(0.24);domain.set_meta("edit_validation_initial_qx",q)

func _configure_flags(flags: Dictionary) -> Dictionary:
	if probe_case=="erosion_continuous":flags.enable_erosion=true
	return flags

func _after_attach() -> void:
	for row in service.registry:initial_positions[row.body_id]=row.body.global_position
	if probe_case=="collision_pair":service.saved[1].linear=Vector3(2.5,0,0)
	if probe_case=="cross_chunk":
		for row in service.registry:
			var prop: RigidBody3D=row.body
			var bounds: Dictionary=service.Contact.bounds(prop)
			var offset: float=prop.global_position.y-bounds.aabb.position.y
			var position:=prop.global_position;position.y=0.4+offset+0.003;prop.global_position=position
			service.saved[row.body_id].linear=Vector3(2.5,0,0)
		service.sample={}

func _scenario_extension() -> Dictionary:
	if probe_case=="erosion_continuous":
		var gap: float=runtime.current.advanced_time_s-service.origin_time_s-service.admitted_time_s
		observations.live_erosion_budget_gap_s=gap
		observations.live_erosion_support={"priority":runtime.current.heights.priority_mask,"applied":runtime.current.heights.applied_state_seq.duplicate(),"applied_frames":runtime.current.heights.applied_physics_frame.duplicate(),"height_events":runtime.current.heights.events.duplicate(true),"history":service.sample_history.map(func(packet):return {"time":packet.value.captured_time_s,"seq":packet.value.captured_state_seq,"required":packet.value.footprint_versions}),"selected":service.sample.get("captured_time_s",-1.0),"physics_frame":Engine.get_physics_frames()}
		FileAccess.open(output.get_base_dir()+"/live_support.json",FileAccess.WRITE).store_string(JSON.stringify(observations.live_erosion_support,"\t"))
		print("EROSION_LIVE_GAP ",gap)
		check("continuous_bed_changes_do_not_starve_props",gap<0.25)
	if probe_case not in ["bed_dig","bed_fill"]:return {}
	check("edit_common_pause",(await service.set_paused(true,&"user")).error.is_empty())
	var poses:={};var before_time: float=service.admitted_time_s
	for row in service.registry:
		poses[row.body_id]=row.body.global_position
		check("sleep_before_edit_"+str(row.body_id),service.saved[row.body_id].sleeping)
	var selected: StringName=&"fill_v1" if probe_case=="bed_fill" else &"dig_v1"
	var profile: Dictionary=runtime.registry.profile(selected)
	var ids: Array=[]
	for row in service.registry:
		var id: int=runtime.highwater()+1;ids.append(id)
		var position: Vector3=row.body.global_position
		var command:={"domain_id":String(runtime.configuration.domain_id),"generation":runtime.generation(),"command_id":id,"sim_tick":runtime.current.completed_tick,"profile_id":selected,"profile_version":1,"profile_hash":profile.profile_hash,"start_xz_m":Vector2(position.x,position.z),"parameters":{"amount_m3":0.3,"radius_m":1.0},"features":{"water_policy":0}}
		check("edit_admitted_"+str(id),runtime.submit_intent(command).accepted)
	await _idle()
	for id in ids:check("edit_applied_"+str(id),runtime.current.result(id).get("outcome")==1)
	var sequence: int=runtime.current.completed_state_seq
	var deadline:=Time.get_ticks_msec()+15000;var settled:=false
	while not settled and service.last_error.is_empty() and Time.get_ticks_msec()<deadline:
		settled=not service.sample.is_empty() and service.sample.captured_state_seq>=sequence and service.pending_support.is_empty()
		if settled:settled=runtime.current.heights.footprint_ready(service.sample.footprint_versions,service.generation).ready
		if not settled:await process_frame
	check("edit_support_and_recovery_settled",settled and service.last_error.is_empty())
	check("paused_edit_is_not_physics_time",service.admitted_time_s==before_time)
	for row in service.registry:
		var delta: Vector3=row.body.global_position-poses[row.body_id]
		if probe_case=="bed_fill":check("bounded_fill_recovery_"+str(row.body_id),delta.y>0.05 and delta.y<=service.Contact.MAX_EDIT_CORRECTION_M and absf(delta.x)+absf(delta.z)<1e-6)
		else:check("dig_keeps_paused_pose_"+str(row.body_id),delta.length()<1e-6)
		check("support_change_arms_wake_"+str(row.body_id),not service.saved[row.body_id].sleeping)
	check("edit_resume",(await service.set_paused(false,&"user")).error.is_empty())
	var target: float=runtime.current.advanced_time_s+1.5;producing=true;deadline=Time.get_ticks_msec()+20000
	while runtime.current.advanced_time_s<target and service.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	producing=false;accumulator=0;await _idle()
	check("edit_followup_real_water_time",runtime.current.advanced_time_s>=target and service.last_error.is_empty())
	if probe_case=="bed_dig":
		for row in service.registry:check("support_loss_falls_"+str(row.body_id),row.body.global_position.y<poses[row.body_id].y-0.05)
	observations.edit={"before_poses":poses,"state_seq":sequence,"profile":selected}
	return {}

func _extra_final_checks() -> void:
	super._extra_final_checks();_collect_events()
	check("complete_event_capture",not event_gap)
	var terrain=runtime.surfaces[runtime.current_index].get_node("Terrain")
	var terrain_id: int=terrain.get_instance_id();observations.terrain_instance_id=terrain_id
	if probe_case in ["dry_sleep","bed_dig","bed_fill","cross_chunk"]:
		observations.contact_projections={}
		for row in service.registry:
			var has_contact:=false;var quiet_count:=0
			for event in full_events:
				if event.kind==&"physics" and event.data.body_id==row.body_id:
					for contact in event.data.contacts:has_contact=has_contact or contact.collider_id==terrain_id
				if event.kind==&"sleep_step" and event.data.body_id==row.body_id:quiet_count+=1
			check("actual_terrain_contact_"+str(row.body_id),has_contact)
			check("real_Jolt_sleep_"+str(row.body_id),service.saved[row.body_id].sleeping and quiet_count>0)
			var projection: Dictionary=service.Contact.project_above_support(row.body,service.registry,runtime.current.heights,service.sample.footprint_versions,service.generation)
			observations.contact_projections[row.body_id]=projection
			check("contact_tolerance_"+str(row.body_id),projection.error.is_empty() and projection.get("needed_delta_m",INF)<=0.005)
			if probe_case=="cross_chunk":check("grounded_chunk_crossing_"+str(row.body_id),initial_positions[row.body_id].x<0 and row.body.global_position.x>0.0625)
	if probe_case=="collision_pair":
		var ids:={}
		for row in service.registry:ids[row.body_id]=row.body.get_instance_id()
		observations.prop_instance_ids=ids
		var pair_contact:=false
		for event in full_events:
			if event.kind!=&"physics" or event.data.body_id!=1:continue
			for contact in event.data.contacts:pair_contact=pair_contact or contact.collider_id==ids[2]
		check("actual_prop_to_prop_contact",pair_contact)

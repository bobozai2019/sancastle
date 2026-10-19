extends Node3D

# Local Jolt consumer of the common domain; never owns RD, water work or fields.
const Profile=preload("res://scripts/props/floating_prop_profile.gd")
const Body=preload("res://scripts/props/floating_prop.gd")
const ProbeCodec=preload("res://scripts/simulation/unified_edit/probe_codec.gd")
const Contact=preload("res://scripts/props/floating_prop_contact.gd")
const Identity=preload("res://scripts/simulation/unified_edit/intent.gd")
const SOURCES=["res://scripts/props/floating_props_service.gd","res://scripts/props/floating_prop.gd","res://scripts/props/floating_prop_profile.gd","res://scripts/props/floating_prop_contact.gd"]
@export var body_paths: Array[NodePath]=[]
@export var trace_enabled:=false
@export var predict_query_pose:=true
var runtime
var registry: Array=[]
var profiles: Dictionary={}
var layout: Dictionary={}
var generation:=0
var domain_id: StringName
var owner_token:=1
var pose_seq:=0
var request_id:=0
var operation_id:=0
var busy:=false
var active:=false
var closing:=false
var closed:=false
var pending:=false
var last_error: StringName
var sample: Dictionary={}
var sample_history: Array=[]
var latest_sample: Dictionary={}
var sample_poses: Dictionary={}
var query_poses: Dictionary={}
var saved: Dictionary={}
var holds: Dictionary={}
var actual_time: Dictionary={}
var expected_steps: Dictionary={}
var expected_frames: Dictionary={}
var expected_resting: Dictionary={}
var last_observed_step_s:=0.0
var query_chunks_by_body: Dictionary={}
var sample_chunks_by_body: Dictionary={}
var support_versions: Dictionary={}
var pending_support: Dictionary={}
var origin_time_s:=0.0
var admitted_time_s:=0.0
var last_sample_time_s:=0.0
var events: Array=[]
var event_id:=0
var events_evicted:=0
var _initialize_height:=false
var _initialized_pose:=false
var _hold_reason: StringName
var candidate_rejections: Array=[]
var read_latency_s:=0.0
var query_frame:=0
var physics_delta_s:=0.0
var held_since_frame:=-1
var body_time_origins: Dictionary={}
var _manipulating:=false
var _placement_ids: Dictionary={}

func world_registry() -> Array:
	return registry.filter(func(row):return not row.body.in_inventory)

func body_for_id(id: int):
	for row in registry:
		if row.body_id==id:return row.body
	return null

func placement_error(id: int, point: Vector2) -> StringName:
	var body=body_for_id(id)
	if body==null:return &"invalid_body"
	if not point.is_finite():return &"invalid_position"
	var margin: float=body.footprint_radius_m+0.2
	if absf(point.x)>16.0-margin or absf(point.y)>16.0-margin:return &"out_of_domain"
	for row in world_registry():
		if row.body_id==id:continue
		var other: Vector2=Vector2(row.body.global_position.x,row.body.global_position.z)
		if point.distance_to(other)<body.footprint_radius_m+row.body.footprint_radius_m+0.05:return &"occupied"
	return &""

func manipulate_body(id: int, point: Vector2, yaw_rad: float=0.0, pickup: bool=false) -> Dictionary:
	if closing:return _result(0,&"closing")
	if not active or runtime.current==null:return _result(0,&"backend_failed")
	if runtime.generation()!=generation:return _result(0,&"stale_generation")
	if busy or holds.has(&"save") or holds.has(&"restore"):return _result(0,&"busy")
	var body=body_for_id(id)
	if body==null:return _result(0,&"invalid_body")
	if not last_error.is_empty():return _result(0,last_error)
	if pickup and body.in_inventory:return _result(0,&"already_picked_up")
	var error: StringName=&"" if pickup else placement_error(id,point)
	if not is_finite(yaw_rad):error=&"invalid_position"
	if not error.is_empty():return _result(0,error)
	if owner_token==9223372036854775807:return _result(0,&"identity_exhausted")
	var op:=_next_operation()
	if op==0:return _result(0,&"identity_exhausted")
	busy=true;holds[&"interaction"]=true;_manipulating=true
	# Keep this generation's accepted read alive until its real terminal callback.
	# A body or pose is never removed while a previous physics grant is in flight.
	await get_tree().physics_frame
	_finalize_resting_steps();_hold_all()
	var retry_at:=Time.get_ticks_msec()
	while pending and not closing:
		if Time.get_ticks_msec()-retry_at>=500:runtime.retry_retirement();retry_at=Time.get_ticks_msec()
		await get_tree().physics_frame
	if closing:
		_manipulating=false;busy=false;holds.erase(&"interaction");return _result(op,&"closing")
	if runtime.current==null or runtime.generation()!=generation:
		_manipulating=false;busy=false;holds.erase(&"interaction");return _result(op,&"stale_generation")
	if not expected_steps.is_empty() or not last_error.is_empty():
		_manipulating=false;busy=false;holds.erase(&"interaction")
		return _result(op,last_error if not last_error.is_empty() else &"busy")
	# Another body may have moved before the common boundary was held.
	if not pickup:error=placement_error(id,point)
	if not error.is_empty():
		_manipulating=false;busy=false;holds.erase(&"interaction");return _result(op,error)
	owner_token+=1;sample={};latest_sample={};sample_history.clear();sample_poses={}
	query_poses={};support_versions.clear();pending_support.clear()
	if pickup:
		body.set_in_inventory(true)
		saved[id]={"linear":Vector3.ZERO,"angular":Vector3.ZERO,"sleeping":false}
	else:
		body.set_in_inventory(false);body.freeze=true
		var pose: Transform3D=layout[id]
		pose.basis=Basis(Vector3.UP,yaw_rad)*pose.basis;pose.origin=Vector3(point.x,0.0,point.y)
		body.global_transform=pose;body.linear_velocity=Vector3.ZERO;body.angular_velocity=Vector3.ZERO
		saved[id]={"linear":Vector3.ZERO,"angular":Vector3.ZERO,"sleeping":false}
		body_time_origins[id]=admitted_time_s;actual_time[id]=0.0
		_placement_ids={id:true};_initialize_height=true;_initialized_pose=false
	_manipulating=false
	if not pickup:error=await _wait_initial_sample()
	if closing:
		busy=false;holds.erase(&"interaction");return _result(op,&"closing")
	# Hand manipulation starts a new consumer observation epoch. It neither
	# advances authority nor creates physics catch-up debt for time spent held.
	origin_time_s=runtime.current.advanced_time_s-admitted_time_s
	last_sample_time_s=runtime.current.advanced_time_s
	if not error.is_empty():last_error=error;holds[&"fault"]=true
	_event(&"pickup" if pickup else &"place",{"body_id":id,"position":body.global_position,"owner_token":owner_token,"origin_time_s":origin_time_s,"body_time_origin_s":body_time_origins.get(id,0.0),"error":error})
	holds.erase(&"interaction");busy=false
	return _result(op,error)

func authored_registry() -> Array:
	var result: Array=[]
	for path in body_paths:
		var body=get_node_or_null(path)
		if body==null:return []
		result.append({"body_id":body.body_id,"body":body,"profile":body.profile})
	return result

func authored_layout() -> Dictionary:
	var result:={}
	for row in authored_registry():result[row.body_id]=row.body.global_transform
	return result

func _event(kind: StringName, data: Dictionary={}) -> void:
	if not trace_enabled:return
	event_id+=1
	events.append({"event_id":event_id,"kind":kind,"frame":Engine.get_physics_frames(),"generation":generation,"admitted_time_s":admitted_time_s,"captured_time_s":last_sample_time_s,"data":data})
	if events.size()>8192:events.pop_front();events_evicted+=1

func _result(id: int, error: StringName) -> Dictionary:
	return {"operation_id":id,"error":error,"domain_id":domain_id,"generation":generation}

func _next_operation(final_shutdown: bool=false) -> int:
	# Keep the final positive int64 identity available for mandatory retirement.
	if not final_shutdown and operation_id>=9223372036854775806:return 0
	var next:=Identity.next_identity(operation_id)
	if not next.error.is_empty():return 0
	operation_id=next.value;return operation_id

func has_operation_room(count: int, renew_owner: bool=false) -> bool:
	return count>=0 and not closing and operation_id<=9223372036854775806-count and (not renew_owner or owner_token<9223372036854775807)

func is_held_at_boundary(reason: StringName) -> bool:
	return active and holds.has(reason) and held_since_frame>=0 and Engine.get_physics_frames()>held_since_frame and expected_steps.is_empty() and registry.all(func(row):return row.body.freeze) and (reason!=&"restore" or not pending)

func _activate_origin() -> void:
	# Activation has no physical history. Do not accumulate an initialization
	# catch-up debt while water progresses independently of this consumer.
	origin_time_s=runtime.current.advanced_time_s
	_event(&"activation_origin",{"origin_time_s":origin_time_s})

func _validate(rows: Array, positions: Dictionary) -> StringName:
	if rows.is_empty() or rows.size()>3:return &"invalid_registry"
	var ids:={};var points:=0
	for row in rows:
		if not row is Dictionary or not row.get("body") is RigidBody3D or row.body.get_script()!=Body or typeof(row.get("body_id"))!=TYPE_INT or row.body_id<1 or ids.has(row.body_id):return &"invalid_registry"
		if row.body.body_id!=row.body_id or row.body.custom_integrator or row.body.gravity_scale!=1.0:return &"invalid_registry"
		if not row.get("profile") is Resource or row.profile.get_script()!=Profile or not row.profile.validate().is_empty():return &"invalid_registry"
		if row.body.physics_material_override==null or absf(row.body.physics_material_override.friction-row.profile.friction)>1e-6:return &"invalid_registry"
		if not positions.get(row.body_id) is Transform3D or not positions[row.body_id].is_finite() or positions[row.body_id].basis.get_scale().distance_to(Vector3.ONE)>1e-5:return &"invalid_registry"
		if not is_finite(row.body.footprint_radius_m) or row.body.footprint_radius_m<=0:return &"invalid_registry"
		var envelope: Dictionary=Contact.enclosing_radius(row.body)
		if not envelope.error.is_empty() or envelope.radius_m>row.body.footprint_radius_m+1e-5:return &"invalid_registry"
		for point in row.profile.point_positions_m:
			if point.length()>row.body.footprint_radius_m:return &"invalid_registry"
		ids[row.body_id]=true;points+=row.profile.point_positions_m.size()
	return &"" if points<=32 else &"invalid_registry"

func attach(owner, rows: Array, positions: Dictionary) -> Dictionary:
	if closing:return _result(0,&"closing")
	if busy or active:return _result(0,&"busy")
	var error:=_validate(rows,positions)
	if not error.is_empty():return _result(0,error)
	if owner==null or not owner.ready_for_input():return _result(0,&"backend_failed")
	var id:=_next_operation()
	if id==0:return _result(0,&"identity_exhausted")
	busy=true
	runtime=owner;registry=rows.duplicate();layout=positions.duplicate(true)
	generation=runtime.generation();domain_id=StringName(runtime.configuration.domain_id)
	for row in registry:
		var body: RigidBody3D=row.body;var data: Dictionary=row.profile.snapshot()
		profiles[row.body_id]=data;body.service=self;body.mass=data.mass_kg
		body.center_of_mass_mode=RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM;body.center_of_mass=data.center_of_mass_m
		body.angular_damp_mode=RigidBody3D.DAMP_MODE_REPLACE;body.angular_damp=data.angular_damping
		body.linear_damp_mode=RigidBody3D.DAMP_MODE_REPLACE;body.linear_damp=0
		actual_time[row.body_id]=0.0
	active=true;holds[&"attach"]=true
	_start_layout(positions)
	error=await _wait_initial_sample()
	if error.is_empty():_activate_origin()
	holds.erase(&"attach");busy=false
	if not error.is_empty():last_error=error;holds[&"fault"]=true
	return _result(id,error)

func _start_layout(positions: Dictionary) -> void:
	_hold_all();sample={};sample_poses={};_initialized_pose=false;_initialize_height=true
	_placement_ids.clear()
	sample_history.clear();latest_sample={}
	expected_steps.clear();expected_frames.clear();expected_resting.clear();support_versions.clear();pending_support.clear();last_observed_step_s=0.0
	read_latency_s=0.0;query_frame=0
	origin_time_s=runtime.current.advanced_time_s;last_sample_time_s=origin_time_s;admitted_time_s=0
	for row in registry:
		var body=row.body;body.set_in_inventory(false);body.global_transform=positions[row.body_id]
		body.linear_velocity=Vector3.ZERO;body.angular_velocity=Vector3.ZERO
		saved[row.body_id]={"linear":Vector3.ZERO,"angular":Vector3.ZERO,"sleeping":false}
		actual_time[row.body_id]=0.0
		body_time_origins[row.body_id]=0.0
	_event(&"layout_reset",{"origin_time_s":origin_time_s})

func _wait_initial_sample() -> StringName:
	var deadline:=Time.get_ticks_msec()+15000
	while not closing and not _initialized_pose and last_error.is_empty() and Time.get_ticks_msec()<deadline:await get_tree().physics_frame
	if closing:return &"closing"
	if not last_error.is_empty():return last_error
	return &"" if _initialized_pose else &"backend_failed"

func _orientation_error(data: Dictionary, first: Basis, second: Basis) -> float:
	if data.sampling_rank==1:return (first*data.sampling_axis).angle_to(second*data.sampling_axis)
	return first.get_rotation_quaternion().angle_to(second.get_rotation_quaternion())

func _query_pose(body: RigidBody3D, data: Dictionary) -> Dictionary:
	var current:=body.global_transform
	if not predict_query_pose or body.freeze or not _initialized_pose or not body.linear_velocity.is_finite() or not body.angular_velocity.is_finite():return {"pose":current,"lead_s":0.0}
	# Forecast only a query location. Neither simulated time nor a body transform
	# changes here. Every delivered sample still passes the original age/point/
	# direction limits. Keep half those spatial limits as forecast reserve.
	var lead:=minf(read_latency_s,data.max_sample_age_s*0.5)
	var center: Vector3=current*data.center_of_mass_m;var angular: Vector3=body.angular_velocity
	for attempt in 6:
		var rotation:=Basis.IDENTITY
		if angular.length_squared()>1e-12:rotation=Basis(angular.normalized(),angular.length()*lead)
		var basis: Basis=rotation*current.basis
		var predicted:=Transform3D(basis,center+body.linear_velocity*lead-basis*data.center_of_mass_m)
		var within: bool=predicted.origin.distance_to(current.origin)<=data.max_pose_distance_m*0.5
		within=within and _orientation_error(data,basis,current.basis)<=data.max_pose_angle_rad*0.5
		for point in data.points:
			var local: Vector3=point.local_position_m;var position: Vector3=predicted*local
			within=within and position.distance_to(current*local)<=data.max_pose_distance_m*0.5
			within=within and position.x>=ProbeCodec.DOMAIN_MIN and position.z>=ProbeCodec.DOMAIN_MIN and position.x<ProbeCodec.DOMAIN_MAX and position.z<ProbeCodec.DOMAIN_MAX
		if within:return {"pose":predicted,"lead_s":lead}
		lead*=0.5
	return {"pose":current,"lead_s":0.0}

func _request_sample() -> void:
	if pending or closing or _manipulating or world_registry().is_empty():return
	if holds.has(&"restore") and _initialized_pose:return
	if request_id==9223372036854775807 or pose_seq==9223372036854775807:last_error=&"identity_exhausted";return
	var points: Array=[];var footprints: Array=[];var leads:={};query_poses={}
	query_chunks_by_body={}
	var world:=world_registry()
	for row in world:
		var body: RigidBody3D=row.body;var data: Dictionary=profiles[row.body_id]
		var forecast:=_query_pose(body,data);var pose: Transform3D=forecast.pose
		query_poses[row.body_id]=pose;leads[row.body_id]=forecast.lead_s
		for index in data.points.size():points.append({"body_id":row.body_id,"point_id":index+1,"position":pose*data.points[index].local_position_m})
		var radius: float=body.footprint_radius_m+data.max_pose_distance_m+data.max_speed_m_s/float(Engine.physics_ticks_per_second)
		var rect:=Rect2(Vector2(pose.origin.x,pose.origin.z)-Vector2.ONE*radius,Vector2.ONE*2.0*radius)
		footprints.append(rect);query_chunks_by_body[row.body_id]=ProbeCodec.chunks({"footprints":[rect]})
	# Keep the bounded history's chunk identities observable while an older
	# packet can still be selected. This avoids mistaking a moving footprint's
	# disappearing edge chunk for an unbounded terrain change.
	var expanded: Array=[]
	for index in world.size():
		var rect: Rect2=footprints[index];var id: int=world[index].body_id
		for packet in sample_history:
			for chunk in packet.chunks.get(id,[]):rect=rect.expand(Vector2(-14.0+float(chunk%8)*4.0,-14.0+float(chunk/8)*4.0))
		expanded.append(rect)
	if ProbeCodec.chunks({"footprints":expanded}).size()<=12:footprints=expanded
	var priority: Array[int]=[]
	for chunks in query_chunks_by_body.values():
		for chunk in chunks:
			if not priority.has(chunk):priority.append(chunk)
	priority.sort()
	var priority_error: StringName=runtime.current.heights.set_footprint_priority(priority,generation,owner_token)
	if not priority_error.is_empty():last_error=priority_error;return
	request_id+=1;pose_seq+=1
	var request:={"request_id":request_id,"owner_token":owner_token,"generation":generation,"pose_seq":pose_seq,"domain_id":String(domain_id),"minimum_state_seq":0,"points":points,"footprints":footprints}
	var admitted: Dictionary=runtime.request_probe(request,_received)
	if admitted.accepted:
		pending=true;query_frame=Engine.get_physics_frames()
		if trace_enabled:_event(&"query_prediction",{"request_id":request_id,"lead_s":leads,"measured_read_latency_s":read_latency_s})
	elif admitted.error not in [&"probe_busy",&"busy"]:last_error=admitted.error;_event(&"probe_rejected",{"error":last_error})

func _received(value: Dictionary) -> void:
	pending=false
	if closing or value.get("generation")!=generation or value.get("owner_token")!=owner_token:return
	if not value.error.is_empty():last_error=value.error;_event(&"probe_error",{"error":last_error});return
	var measured: float=float(Engine.get_physics_frames()-query_frame)*physics_delta_s
	if measured>=0.0:read_latency_s=measured if read_latency_s==0.0 else 0.5*(read_latency_s+measured)
	sample=value;latest_sample=value;sample_poses=query_poses.duplicate(true);last_sample_time_s=maxf(last_sample_time_s,value.captured_time_s)
	sample_chunks_by_body=query_chunks_by_body.duplicate(true)
	if trace_enabled:_event(&"sample",{"state_seq":value.captured_state_seq,"tick":value.captured_tick,"revision":value.captured_revision,"pose_seq":value.pose_seq,"points":value.points.duplicate(true)})
	if _initialize_height:
		if not runtime.current.heights.footprint_ready(value.footprint_versions,generation).ready:return
		for row in world_registry():
			if not _placement_ids.is_empty() and not _placement_ids.has(row.body_id):continue
			var body: RigidBody3D=row.body;var highest:=-1e10;var highest_water:=-1e10
			for point in value.points:
				if point.body_id==row.body_id:highest_water=maxf(highest_water,point.eta+0.05)
			var bounds: Dictionary=Contact.bounds(body)
			if not bounds.error.is_empty():last_error=bounds.error;return
			var bed: Dictionary=runtime.current.heights.maximum_bed(Contact.rect(bounds.aabb),value.footprint_versions,generation)
			if not bed.error.is_empty():last_error=bed.error;return
			var bottom: float=body.global_position.y-bounds.aabb.position.y
			highest=maxf(highest_water,bed.maximum_m+bottom+0.01)
			var position:=body.global_position;position.y=highest;body.global_position=position
		_initialize_height=false;_placement_ids.clear();sample={};sample_poses={}
	else:
		_initialized_pose=true
		sample_history.append({"value":value,"poses":sample_poses.duplicate(true),"chunks":sample_chunks_by_body.duplicate(true)})
		if sample_history.size()>8:sample_history.pop_front()
		_observe_environment()

func _has_wet_sample(id: int) -> bool:
	for point in sample.get("points",[]):
		if point.body_id==id and point.h>ProbeCodec.DRY_DEPTH_M:return true
	return false

func _wake(row: Dictionary, reason: StringName) -> void:
	var body: RigidBody3D=row.body
	var was_sleeping: bool=saved.get(row.body_id,{}).get("sleeping",false) if body.freeze else body.sleeping
	if saved.has(row.body_id):saved[row.body_id].sleeping=false
	if not body.freeze:body.sleeping=false
	if was_sleeping:_event(&"wake",{"body_id":row.body_id,"reason":reason,"held":body.freeze})

func _observe_environment() -> void:
	for row in world_registry():
		var versions:={};var previous: Dictionary=support_versions.get(row.body_id,{})
		for chunk in sample_chunks_by_body[row.body_id]:versions[chunk]=sample.footprint_versions[chunk]
		var changed:=false
		if not previous.is_empty():
			for chunk in versions:
				if versions[chunk]!=previous.get(chunk,-1):changed=true
		support_versions[row.body_id]=versions
		if changed:pending_support[row.body_id]=versions.duplicate();_wake(row,&"bed_changed")
		elif _has_wet_sample(row.body_id):_wake(row,&"water_covered")

func _hold_all() -> void:
	var changed:=false
	for row in registry:
		var body: RigidBody3D=row.body
		if not body.freeze:
			saved[row.body_id]={"linear":body.linear_velocity,"angular":body.angular_velocity,"sleeping":body.sleeping};body.freeze=true;changed=true
	if changed or held_since_frame<0:held_since_frame=Engine.get_physics_frames()

func _release_all() -> void:
	for row in world_registry():
		var body: RigidBody3D=row.body
		if body.freeze:
			body.freeze=false;body.linear_velocity=saved[row.body_id].linear;body.angular_velocity=saved[row.body_id].angular;body.sleeping=saved[row.body_id].sleeping
	held_since_frame=-1

func _reject_sample(reason: StringName, value: Dictionary, detail: Dictionary={}) -> bool:
	if trace_enabled:
		candidate_rejections.append({"reason":reason,"seq":value.get("captured_state_seq",-1),"time_s":value.get("captured_time_s",-1.0),"detail":detail})
		if candidate_rejections.size()>8:candidate_rejections.pop_front()
	return false

func _candidate_usable(value: Dictionary, poses: Dictionary) -> bool:
	if value.is_empty() or not _initialized_pose:return false
	for row in world_registry():
		if not poses.has(row.body_id):return false
		var data: Dictionary=profiles[row.body_id];var body: RigidBody3D=row.body
		if maxf(runtime.current.advanced_time_s,last_sample_time_s)-value.captured_time_s>data.max_sample_age_s:return _reject_sample(&"age",value,{"body_id":row.body_id})
		var pose: Transform3D=poses[row.body_id]
		if body.global_position.distance_to(pose.origin)>data.max_pose_distance_m:return _reject_sample(&"root_distance",value,{"body_id":row.body_id})
		if _orientation_error(data,body.global_basis,pose.basis)>data.max_pose_angle_rad:return _reject_sample(&"cloud_angle",value,{"body_id":row.body_id})
		# Query data observes the sampling cloud, not invisible axial twist of a
		# collinear cloud. Point displacement also bounds translation+rotation
		# together. Current COM/point velocities are recomputed before every force.
		for point in data.points:
			var local: Vector3=point.local_position_m
			if body.to_global(local).distance_to(pose*local)>data.max_pose_distance_m:return _reject_sample(&"point_distance",value,{"body_id":row.body_id})
	var compatible: Dictionary=runtime.current.heights.footprint_compatible(value.footprint_versions,value.footprint_change_bounds,generation,Contact.CONTACT_TOLERANCE_M)
	if not compatible.ready:return _reject_sample(&"collision_support",value)
	for chunk in value.footprint_versions:
		if int(runtime.current.heights.applied_state_seq.get(chunk,-1))<=int(latest_sample.get("captured_state_seq",-1)):continue
		var before: float=value.footprint_change_bounds[chunk];var after: float=runtime.current.heights.applied_change_bounds.get(chunk,-1.0)
		if before<0.0 or after<before or after-before>Contact.CONTACT_TOLERANCE_M:return _reject_sample(&"geometry_change_bound",value,{"chunk":chunk,"before_m":before,"after_m":after})
	# Compare true temporal change over complete work boundaries. Point bed
	# differences also contain spatial slope when a prop moves, so cannot prove
	# a temporal edit. ABI3 carries an outward-rounded full-chunk change bound.
	if not latest_sample.is_empty() and value.captured_state_seq<latest_sample.captured_state_seq and value.footprint_versions!=latest_sample.footprint_versions:
		for chunk in value.footprint_versions:
			if not latest_sample.footprint_versions.has(chunk):return _reject_sample(&"footprint_changed",value)
			if value.footprint_versions[chunk]==latest_sample.footprint_versions[chunk]:continue
			var before: float=value.footprint_change_bounds[chunk];var after: float=latest_sample.footprint_change_bounds[chunk]
			var older_shape_difference: float=compatible.older_shape_differences_m.get(chunk,0.0)
			if before<0.0 or after<before or after-before+older_shape_difference>Contact.CONTACT_TOLERANCE_M:return _reject_sample(&"bed_change_bound",value,{"chunk":chunk,"before_m":before,"after_m":after,"older_shape_difference_m":older_shape_difference})
	return true

func _sample_usable() -> bool:return _candidate_usable(sample,sample_poses)

func _motion_within_budget(body: RigidBody3D, data: Dictionary) -> bool:
	if not body.linear_velocity.is_finite() or not body.angular_velocity.is_finite():return false
	if body.linear_velocity.length()>data.max_speed_m_s or body.angular_velocity.length()>data.max_angular_speed_rad_s:return false
	var observed_angular: float=body.angular_velocity.cross(body.global_basis*data.sampling_axis).length() if data.sampling_rank==1 else body.angular_velocity.length()
	if observed_angular>data.max_sample_direction_speed_rad_s:return false
	var center: Vector3=body.to_global(data.center_of_mass_m)
	for point in data.points:
		var local: Vector3=point.local_position_m
		var velocity: Vector3=body.linear_velocity+body.angular_velocity.cross(body.to_global(local)-center)
		if velocity.length()>data.max_speed_m_s:return false
	return true

func _select_sample() -> bool:
	candidate_rejections.clear()
	for index in range(sample_history.size()-1,-1,-1):
		var packet: Dictionary=sample_history[index]
		if not _candidate_usable(packet.value,packet.poses):continue
		sample=packet.value;sample_poses=packet.poses;sample_chunks_by_body=packet.chunks;return true
	return false

func _physics_process(delta: float) -> void:
	if not active:return
	physics_delta_s=delta
	_finalize_resting_steps()
	if closing:
		if not _has_current_grant():_hold_all()
		return
	if runtime.current==null or runtime.generation()!=generation:last_error=&"stale_generation";_hold_all();return
	if _manipulating:_hold_all();return
	if world_registry().is_empty():
		origin_time_s=runtime.current.advanced_time_s-admitted_time_s;_hold_all();return
	_request_sample()
	var usable:=last_error.is_empty() and _select_sample()
	if usable and not pending_support.is_empty():
		var eligible:={}
		for row in world_registry():
			if not pending_support.has(row.body_id):continue
			if not runtime.current.heights.footprint_ready(pending_support[row.body_id],generation).ready:continue
			eligible[row.body_id]=true
		var corrected:=false
		if not eligible.is_empty():
			_hold_all()
			# Eligible roots have their pending bed version installed. Query the
			# actual assigned collision snapshot, not a newer force-compatible water
			# packet whose unrelated edge chunks may still be in flight.
			var assigned: Dictionary=runtime.current.heights.applied_state_seq.duplicate()
			var result: Dictionary=Contact.recovery_plan(world_registry(),eligible,runtime.current.heights,assigned,generation)
			if result.error==&"support_not_ready":return
			if not result.error.is_empty():last_error=result.error;_event(&"edit_recovery_failed",{"result":result});return
			for row in registry:
				if not result.corrections.has(row.body_id):continue
				var correction: Dictionary=result.corrections[row.body_id]
				var position: Vector3=row.body.global_position;var from:=position;position.y+=correction.delta_y;row.body.global_position=position
				saved[row.body_id].linear.y=maxf(0.0,saved[row.body_id].linear.y);saved[row.body_id].sleeping=false
				_event(&"edit_recovery",{"body_id":row.body_id,"from":from,"to":position,"query":correction,"state_seq":sample.captured_state_seq});corrected=true
			for id in result.completed:pending_support.erase(id)
		if corrected:held_since_frame=Engine.get_physics_frames();sample={};sample_poses={};sample_history.clear();return
	var budget:=last_sample_time_s-origin_time_s-admitted_time_s
	if not holds.is_empty() or not usable or budget+1e-7<delta:
		var reason: StringName=&"intent" if not holds.is_empty() else (&"sample_or_support" if not usable else &"budget")
		if reason!=_hold_reason:
			_hold_reason=reason
			var readiness: Dictionary={} if sample.is_empty() else runtime.current.heights.footprint_ready(sample.footprint_versions,generation)
			_event(&"hold",{"reason":reason,"budget_s":budget,"support":readiness,"sample_time_s":sample.get("captured_time_s",-1.0),"candidate_rejections":candidate_rejections.duplicate(true) if trace_enabled else []})
		_hold_all();return
	_hold_reason=&""
	for row in world_registry():
		var body: RigidBody3D=row.body;var data: Dictionary=profiles[row.body_id]
		if not _motion_within_budget(body,data):
			last_error=&"speed_limit";_event(&"protection",{"body_id":row.body_id,"error":last_error,"linear_velocity":body.linear_velocity,"angular_velocity":body.angular_velocity});_hold_all();return
	_release_all()
	for row in world_registry():
		var body: RigidBody3D=row.body;var data: Dictionary=profiles[row.body_id]
		if body.sleeping and _has_wet_sample(row.body_id):_wake(row,&"water_covered")
		var resting:=body.sleeping
		if not resting:_apply_forces(body,data)
		expected_steps[row.body_id]=delta
		expected_frames[row.body_id]=Engine.get_physics_frames();expected_resting[row.body_id]=resting
	admitted_time_s+=delta
	_event(&"admit",{"delta":delta,"budget_before":budget,"sample_state_seq":sample.captured_state_seq,"force_sample_time_s":sample.captured_time_s,"force_age_s":maxf(runtime.current.advanced_time_s,last_sample_time_s)-sample.captured_time_s})

func _apply_forces(body: RigidBody3D, data: Dictionary) -> void:
	var gravity: float=ProjectSettings.get_setting("physics/3d/default_gravity",9.8)
	var center: Vector3=body.to_global(data.center_of_mass_m)
	for point in sample.points:
		if point.body_id!=body.body_id:continue
		var config: Dictionary=data.points[point.point_id-1];var position:=body.to_global(config.local_position_m)
		var half: float=config.half_height_m
		var wet: bool=point.h>ProbeCodec.DRY_DEPTH_M
		var fraction:=clampf((minf(position.y+half,point.eta)-maxf(position.y-half,point.bed))/(2.0*half),0,1) if wet else 0.0
		var velocity:=body.linear_velocity+body.angular_velocity.cross(position-center)
		var relative:=Vector3(point.u_xz.x,0,point.u_xz.y)-velocity
		var force:=Vector3(0,1000.0*gravity*config.effective_volume_m3*fraction,0)
		force+=data.mass_kg*config.mass_weight*fraction*Vector3(relative.x/data.drag_time_horizontal_s,relative.y/data.drag_time_vertical_s,relative.z/data.drag_time_horizontal_s)
		body.apply_force(force,position-body.global_position)
		if trace_enabled:_event(&"point_force",{"body_id":body.body_id,"point_id":point.point_id,"position":position,"fraction":fraction,"force":force,"point_velocity":velocity,"sample_position":point.sample_position,"sample_h":point.h,"sample_eta":point.eta,"sample_bed":point.bed,"sample_u":point.u_xz,"position_m":[position.x,position.y,position.z],"force_n":[force.x,force.y,force.z],"point_velocity_m_s":[velocity.x,velocity.y,velocity.z],"sample_u_m_s":[point.u_xz.x,point.u_xz.y],"sample_abi":sample.schema,"wet":wet})

func observe_step(body: RigidBody3D, state: PhysicsDirectBodyState3D) -> void:
	last_observed_step_s=state.step
	actual_time[body.body_id]=float(actual_time.get(body.body_id,0.0))+state.step
	var expected: float=expected_steps.get(body.body_id,0.0);expected_steps.erase(body.body_id)
	expected_frames.erase(body.body_id);expected_resting.erase(body.body_id)
	if absf(state.step-expected)>1e-7:last_error=&"unexpected_physics_step"
	if trace_enabled:
		var contacts: Array=[]
		for index in state.get_contact_count():contacts.append({"collider_id":state.get_contact_collider_id(index),"local_position":state.get_contact_local_position(index),"local_normal":state.get_contact_local_normal(index),"impulse":state.get_contact_impulse(index)})
		_event(&"physics",{"body_id":body.body_id,"state_step":state.step,"expected_step":expected,"actual_time_s":actual_time[body.body_id],"position":state.transform.origin,"linear_velocity":state.linear_velocity,"angular_velocity":state.angular_velocity,"contacts":contacts,"error":last_error})

func _has_current_grant() -> bool:
	return expected_frames.values().has(Engine.get_physics_frames())

func _finalize_resting_steps() -> void:
	var frame:=Engine.get_physics_frames()
	for row in registry:
		var id: int=row.body_id
		if not expected_steps.has(id) or frame<=int(expected_frames[id]):continue
		var gap: int=frame-int(expected_frames[id]);var expected: float=expected_steps[id]
		var was_resting: bool=expected_resting[id];var now_resting: bool=row.body.sleeping
		if gap!=1 or last_observed_step_s<=0.0 or absf(expected-last_observed_step_s)>1e-7 or not (was_resting or now_resting):
			last_error=&"missing_physics_step";_hold_all();return
		# Sleeping Jolt bodies omit force callbacks. The world still advanced one
		# granted quantum. Label this derived world step separately from state.step.
		actual_time[id]=float(actual_time[id])+last_observed_step_s
		_event(&"sleep_step",{"body_id":id,"effective_step_s":last_observed_step_s,"last_observed_state_step_s":last_observed_step_s,"expected_step":expected,"grant_frame":expected_frames[id],"world_frame_delta":gap,"was_sleeping":was_resting,"now_sleeping":now_resting,"actual_time_s":actual_time[id],"position":row.body.global_position,"error":&""})
		expected_steps.erase(id);expected_frames.erase(id);expected_resting.erase(id)

func set_paused(paused: bool, reason: StringName=&"user") -> Dictionary:
	if closing:return _result(0,&"closing")
	if busy:return _result(0,&"busy")
	if reason not in [&"user",&"save",&"restore"]:return _result(0,&"invalid_registry")
	var id:=_next_operation()
	if id==0:return _result(0,&"identity_exhausted")
	busy=true
	if paused:
		# Caller stops producing before requesting a common pause boundary. Drain
		# the already-published local budget; water/edit admission never waits here.
		var deadline:=Time.get_ticks_msec()+15000
		while holds.is_empty() and not closing and last_error.is_empty() and Time.get_ticks_msec()<deadline:
			_finalize_resting_steps()
			var remaining: float=runtime.current.advanced_time_s-origin_time_s-admitted_time_s
			if remaining+1e-7<1.0/float(Engine.physics_ticks_per_second) and expected_steps.is_empty() and runtime.current.active_count()==0 and runtime.current.pending_count()==0:break
			await get_tree().physics_frame
		if closing:busy=false;return _result(id,&"closing")
		if holds.is_empty() and not closing and last_error.is_empty():
			var remainder: float=runtime.current.advanced_time_s-origin_time_s-admitted_time_s
			if remainder+1e-7>=1.0/float(Engine.physics_ticks_per_second) or not expected_steps.is_empty():last_error=&"pause_boundary_timeout"
		holds[reason]=true;_hold_all()
		# Restore closes this generation's requests before the candidate swap.
		# A registered unknown read retains its lease until the public retry proves
		# completion. Save/user holds continue observing same-generation edits.
		if reason==&"restore":
			var retry_at:=Time.get_ticks_msec()
			while pending and not closing:
				if Time.get_ticks_msec()-retry_at>=500:runtime.retry_retirement();retry_at=Time.get_ticks_msec()
				await get_tree().physics_frame
	else:holds.erase(reason)
	busy=false;_event(&"pause",{"paused":paused,"reason":reason,"holds":holds.duplicate()})
	return _result(id,&"closing" if closing else last_error)

func reset(positions: Dictionary, domain: StringName, epoch: int) -> Dictionary:
	if closing:return _result(0,&"closing")
	if busy or pending:return _result(0,&"busy")
	if runtime.current==null or runtime.generation()!=epoch or String(runtime.configuration.domain_id)!=String(domain):return _result(0,&"stale_generation")
	_finalize_resting_steps()
	if not expected_steps.is_empty():return _result(0,&"busy")
	var error:=_validate(registry,positions)
	if not error.is_empty():return _result(0,error)
	if owner_token==9223372036854775807:return _result(0,&"identity_exhausted")
	var id:=_next_operation()
	if id==0:return _result(0,&"identity_exhausted")
	busy=true
	generation=epoch;domain_id=domain;owner_token+=1;request_id=0;pose_seq=0;last_error=&"";holds.erase(&"fault")
	layout=positions.duplicate(true);holds[&"attach"]=true;_start_layout(positions)
	error=await _wait_initial_sample()
	if error.is_empty():_activate_origin()
	else:last_error=error;holds[&"fault"]=true
	holds.erase(&"attach");busy=false
	return _result(id,error)

func shutdown() -> Dictionary:
	if closed:return _result(operation_id,&"")
	if closing:
		while not closed:await get_tree().physics_frame
		return _result(operation_id,&"")
	# Shutdown must still retire leases when the diagnostic operation counter is
	# exhausted. Reuse its final identity instead of overflowing signed int64.
	closing=true;var id:=_next_operation(true)
	if id==0:id=operation_id
	if not _has_current_grant():_hold_all()
	await get_tree().physics_frame
	_finalize_resting_steps();_hold_all()
	var retry_at:=Time.get_ticks_msec()
	while pending:
		if Time.get_ticks_msec()-retry_at>=500:runtime.retry_retirement();retry_at=Time.get_ticks_msec()
		await get_tree().physics_frame
	if runtime.current!=null and runtime.generation()==generation:
		var empty: Array[int]=[]
		runtime.current.heights.set_footprint_priority(empty,generation,owner_token)
	for row in registry:row.body.service=null
	active=false;closed=true;_event(&"closed")
	return _result(id,&"")

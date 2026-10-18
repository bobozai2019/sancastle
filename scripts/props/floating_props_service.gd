extends Node3D

# Local Jolt consumer of the common domain; never owns RD, water work or fields.
const Profile=preload("res://scripts/props/floating_prop_profile.gd")
const Body=preload("res://scripts/props/floating_prop.gd")
const ProbeCodec=preload("res://scripts/simulation/unified_edit/probe_codec.gd")
const Contact=preload("res://scripts/props/floating_prop_contact.gd")
@export var body_paths: Array[NodePath]=[]
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
var _initialize_height:=false
var _initialized_pose:=false

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
	events.append({"kind":kind,"frame":Engine.get_physics_frames(),"generation":generation,"admitted_time_s":admitted_time_s,"captured_time_s":last_sample_time_s,"data":data})
	if events.size()>8192:events.pop_front()

func _result(id: int, error: StringName) -> Dictionary:
	return {"operation_id":id,"error":error,"domain_id":domain_id,"generation":generation}

func _validate(rows: Array, positions: Dictionary) -> StringName:
	if rows.is_empty() or rows.size()>3:return &"invalid_registry"
	var ids:={};var points:=0
	for row in rows:
		if not row is Dictionary or not row.get("body") is RigidBody3D or row.body.get_script()!=Body or typeof(row.get("body_id"))!=TYPE_INT or row.body_id<1 or ids.has(row.body_id):return &"invalid_registry"
		if row.body.body_id!=row.body_id or row.body.custom_integrator or row.body.gravity_scale!=1.0:return &"invalid_registry"
		if not row.get("profile") is Resource or row.profile.get_script()!=Profile or not row.profile.validate().is_empty():return &"invalid_registry"
		if not positions.get(row.body_id) is Transform3D or not positions[row.body_id].is_finite() or positions[row.body_id].basis.get_scale().distance_to(Vector3.ONE)>1e-5:return &"invalid_registry"
		if not is_finite(row.body.footprint_radius_m) or row.body.footprint_radius_m<=0:return &"invalid_registry"
		ids[row.body_id]=true;points+=row.profile.point_positions_m.size()
	return &"" if points<=32 else &"invalid_registry"

func attach(owner, rows: Array, positions: Dictionary) -> Dictionary:
	if closing:return _result(0,&"closing")
	if busy or active:return _result(0,&"busy")
	var error:=_validate(rows,positions)
	if not error.is_empty():return _result(0,error)
	if owner==null or not owner.ready_for_input():return _result(0,&"backend_failed")
	operation_id+=1;var id:=operation_id;busy=true
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
	holds.erase(&"attach");busy=false
	if not error.is_empty():last_error=error;holds[&"fault"]=true
	return _result(id,error)

func _start_layout(positions: Dictionary) -> void:
	_hold_all();sample={};sample_poses={};_initialized_pose=false;_initialize_height=true
	expected_steps.clear();expected_frames.clear();expected_resting.clear();support_versions.clear();pending_support.clear();last_observed_step_s=0.0
	origin_time_s=runtime.current.advanced_time_s;last_sample_time_s=origin_time_s;admitted_time_s=0
	for row in registry:
		var body: RigidBody3D=row.body;body.global_transform=positions[row.body_id]
		body.linear_velocity=Vector3.ZERO;body.angular_velocity=Vector3.ZERO
		saved[row.body_id]={"linear":Vector3.ZERO,"angular":Vector3.ZERO,"sleeping":false}
		actual_time[row.body_id]=0.0
	_event(&"layout_reset",{"origin_time_s":origin_time_s})

func _wait_initial_sample() -> StringName:
	var deadline:=Time.get_ticks_msec()+15000
	while not closing and not _initialized_pose and last_error.is_empty() and Time.get_ticks_msec()<deadline:await get_tree().physics_frame
	if closing:return &"closing"
	if not last_error.is_empty():return last_error
	return &"" if _initialized_pose else &"backend_failed"

func _request_sample() -> void:
	if pending or closing:return
	var points: Array=[];var footprints: Array=[];query_poses={}
	query_chunks_by_body={}
	for row in registry:
		var body: RigidBody3D=row.body;var data: Dictionary=profiles[row.body_id]
		query_poses[row.body_id]=body.global_transform
		for index in data.points.size():points.append({"body_id":row.body_id,"point_id":index+1,"position":body.to_global(data.points[index].local_position_m)})
		var radius: float=body.footprint_radius_m+data.max_speed_m_s/60.0
		var rect:=Rect2(Vector2(body.global_position.x,body.global_position.z)-Vector2.ONE*radius,Vector2.ONE*2.0*radius)
		footprints.append(rect);query_chunks_by_body[row.body_id]=ProbeCodec.chunks({"footprints":[rect]})
	request_id+=1;pose_seq+=1
	var request:={"request_id":request_id,"owner_token":owner_token,"generation":generation,"pose_seq":pose_seq,"domain_id":String(domain_id),"minimum_state_seq":0,"points":points,"footprints":footprints}
	var admitted: Dictionary=runtime.request_probe(request,_received)
	if admitted.accepted:pending=true
	elif admitted.error not in [&"probe_busy",&"busy"]:last_error=admitted.error;_event(&"probe_rejected",{"error":last_error})

func _received(value: Dictionary) -> void:
	pending=false
	if closing or value.get("generation")!=generation or value.get("owner_token")!=owner_token:return
	if not value.error.is_empty():last_error=value.error;_event(&"probe_error",{"error":last_error});return
	sample=value;sample_poses=query_poses.duplicate(true);last_sample_time_s=value.captured_time_s
	sample_chunks_by_body=query_chunks_by_body.duplicate(true)
	_event(&"sample",{"state_seq":value.captured_state_seq,"tick":value.captured_tick,"revision":value.captured_revision,"pose_seq":value.pose_seq,"points":value.points.duplicate(true)})
	if _initialize_height:
		if not runtime.current.heights.footprint_ready(value.footprint_versions,generation).ready:return
		for row in registry:
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
		_initialize_height=false;sample={};sample_poses={}
	else:_initialized_pose=true;_observe_environment()

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
	for row in registry:
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
	for row in registry:
		var body: RigidBody3D=row.body
		if not body.freeze:
			saved[row.body_id]={"linear":body.linear_velocity,"angular":body.angular_velocity,"sleeping":body.sleeping};body.freeze=true

func _release_all() -> void:
	for row in registry:
		var body: RigidBody3D=row.body
		if body.freeze:
			body.freeze=false;body.linear_velocity=saved[row.body_id].linear;body.angular_velocity=saved[row.body_id].angular;body.sleeping=saved[row.body_id].sleeping

func _sample_usable() -> bool:
	if sample.is_empty() or not _initialized_pose:return false
	for row in registry:
		var data: Dictionary=profiles[row.body_id];var body: RigidBody3D=row.body
		if runtime.current.advanced_time_s-sample.captured_time_s>data.max_sample_age_s:return false
		var pose: Transform3D=sample_poses[row.body_id]
		if body.global_position.distance_to(pose.origin)>data.max_pose_distance_m:return false
		if body.global_basis.get_rotation_quaternion().angle_to(pose.basis.get_rotation_quaternion())>data.max_pose_angle_rad:return false
	if not runtime.current.heights.footprint_ready(sample.footprint_versions,generation).ready:return false
	return true

func _physics_process(delta: float) -> void:
	if not active:return
	_finalize_resting_steps()
	if closing:
		if not _has_current_grant():_hold_all()
		return
	if runtime.current==null or runtime.generation()!=generation:last_error=&"stale_generation";_hold_all();return
	_request_sample()
	var usable:=last_error.is_empty() and _sample_usable()
	if usable and not pending_support.is_empty():
		_hold_all()
		var corrected:=false
		for row in registry:
			if not pending_support.has(row.body_id):continue
			var result: Dictionary=Contact.project_above_support(row.body,registry,runtime.current.heights,sample.footprint_versions,generation)
			if not result.error.is_empty():last_error=result.error;_event(&"edit_recovery_failed",{"body_id":row.body_id,"result":result});return
			if result.delta_y>0.0:
				var position: Vector3=row.body.global_position;var from:=position;position.y=result.target_y;row.body.global_position=position
				saved[row.body_id].linear.y=maxf(0.0,saved[row.body_id].linear.y);saved[row.body_id].sleeping=false
				_event(&"edit_recovery",{"body_id":row.body_id,"from":from,"to":position,"query":result,"state_seq":sample.captured_state_seq});corrected=true
			pending_support.erase(row.body_id)
		if corrected:sample={};sample_poses={};return
	var budget:=last_sample_time_s-origin_time_s-admitted_time_s
	if not holds.is_empty() or not usable or budget+1e-7<delta:_hold_all();return
	for row in registry:
		var body: RigidBody3D=row.body;var data: Dictionary=profiles[row.body_id]
		if body.linear_velocity.length()>data.max_speed_m_s or body.angular_velocity.length()>data.max_angular_speed_rad_s:
			last_error=&"speed_limit";_event(&"protection",{"body_id":row.body_id,"error":last_error});_hold_all();return
	_release_all()
	for row in registry:
		var body: RigidBody3D=row.body;var data: Dictionary=profiles[row.body_id]
		if body.sleeping and _has_wet_sample(row.body_id):_wake(row,&"water_covered")
		var resting:=body.sleeping
		if not resting:_apply_forces(body,data)
		expected_steps[row.body_id]=delta
		expected_frames[row.body_id]=Engine.get_physics_frames();expected_resting[row.body_id]=resting
	admitted_time_s+=delta
	_event(&"admit",{"delta":delta,"budget_before":budget,"sample_state_seq":sample.captured_state_seq})

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
		_event(&"point_force",{"body_id":body.body_id,"point_id":point.point_id,"position":position,"fraction":fraction,"force":force,"point_velocity":velocity,"sample_position":point.sample_position,"sample_h":point.h,"sample_eta":point.eta,"sample_bed":point.bed,"sample_u":point.u_xz,"position_m":[position.x,position.y,position.z],"force_n":[force.x,force.y,force.z],"point_velocity_m_s":[velocity.x,velocity.y,velocity.z],"sample_u_m_s":[point.u_xz.x,point.u_xz.y],"sample_abi":sample.schema,"wet":wet})

func observe_step(body: RigidBody3D, state: PhysicsDirectBodyState3D) -> void:
	last_observed_step_s=state.step
	actual_time[body.body_id]=float(actual_time.get(body.body_id,0.0))+state.step
	var expected: float=expected_steps.get(body.body_id,0.0);expected_steps.erase(body.body_id)
	expected_frames.erase(body.body_id);expected_resting.erase(body.body_id)
	if absf(state.step-expected)>1e-7:last_error=&"unexpected_physics_step"
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
	operation_id+=1;var id:=operation_id;busy=true
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
	operation_id+=1;var id:=operation_id;busy=true
	generation=epoch;domain_id=domain;owner_token+=1;request_id=0;pose_seq=0;last_error=&""
	layout=positions.duplicate(true);holds[&"attach"]=true;_start_layout(positions)
	error=await _wait_initial_sample();holds.erase(&"attach");busy=false
	return _result(id,error)

func shutdown() -> Dictionary:
	if closed:return _result(operation_id,&"")
	closing=true;operation_id+=1;var id:=operation_id
	if not _has_current_grant():_hold_all()
	await get_tree().physics_frame
	_finalize_resting_steps();_hold_all()
	var retry_at:=Time.get_ticks_msec()
	while pending:
		if Time.get_ticks_msec()-retry_at>=500:runtime.retry_retirement();retry_at=Time.get_ticks_msec()
		await get_tree().physics_frame
	for row in registry:row.body.service=null
	active=false;closed=true;_event(&"closed")
	return _result(id,&"")

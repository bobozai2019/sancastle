extends "res://tests/floating_props/contact_probe.gd"

var phases: Dictionary={1:0,2:0,3:0}
var dwell: Dictionary={1:0.0,2:0.0,3:0.0}
var forces: Dictionary={}
var transitions: Array=[]
var trace: Array=[]
var processed_id:=0
var original_instances: Dictionary={}
var following_wave: Dictionary={}
var captured_phases: Dictionary={}
var priming_native_dry_rest:=true

func _fixture_path() -> String:return "res://tests/floating_props/wave_fixture.tscn"
func _extra_sources() -> PackedStringArray:
	var paths:=super._extra_sources();paths.append("res://tests/floating_props/wave_fixture.tscn");return paths
func _target_time() -> float:return 26.0
func _environment() -> Dictionary:
	return {"engine":Engine.get_version_info().string,"probe":probe_case,"boundary":{"enabled":true,"mode":0,"mean_level_m":0.4,"amplitude_m":0.4,"omega_rad_s":TAU/12.0,"phase_rad":-PI/2.0,"period_s":12.0}}
func _configure_domain(domain) -> void:
	domain.water.fill(0.0)
	for index in 65536:
		var x: float=(float(index%256)+0.5-128.0)*0.125
		domain.sand[index]=0.3+0.1*(x+16.0)
func _after_attach() -> void:
	super._after_attach()
	for row in service.registry:original_instances[row.body_id]=row.body.get_instance_id()
	call_deferred("_prime_native_dry_rest")

func _prime_native_dry_rest() -> void:
	# A slower render/readback schedule may repeatedly hold the bodies before
	# native sleep is reached. Establish an explicit dry-rest precondition with
	# public completed water work and genuine Jolt steps, never sleeping=true.
	check("dry_rest_public_user_hold",(await service.set_paused(true,&"user")).error.is_empty())
	var accepted:=true
	for index in 60:accepted=runtime.request_tick(1.0/30.0).is_empty() and accepted
	check("dry_rest_two_seconds_public_water_admitted",accepted)
	await _idle()
	check("dry_rest_public_resume",(await service.set_paused(false,&"user")).error.is_empty())
	var deadline:=Time.get_ticks_msec()+15000
	while service.admitted_time_s<1.0 and service.last_error.is_empty() and Time.get_ticks_msec()<deadline:await physics_frame
	observations.dry_rest={"water_time_s":runtime.current.advanced_time_s,"actual_time_s":service.actual_time.duplicate(),"sleeping":service.registry.map(func(row):return row.body.sleeping),"input":"60public1/30s ticks while locally held; water producer then held until1s genuine Jolt consumption; no body pose/sleep write"}
	check("dry_rest_native_sleep_reached",service.registry.all(func(row):return row.body.sleeping) and service.last_error.is_empty())
	priming_native_dry_rest=false

func _clearance(prop: RigidBody3D) -> float:
	var normal:=Vector3(-0.1,1,0).normalized();var constant:=1.9/sqrt(1.01);var lowest:=INF
	for child in prop.get_children():
		if not child is CollisionShape3D or child.disabled:continue
		var transform: Transform3D=child.global_transform;var shape: Shape3D=child.shape;var radius:=0.0
		if shape is BoxShape3D:
			var half: Vector3=shape.size*0.5
			radius=absf(transform.basis.x.dot(normal))*half.x+absf(transform.basis.y.dot(normal))*half.y+absf(transform.basis.z.dot(normal))*half.z
		elif shape is CapsuleShape3D:radius=shape.radius+maxf(0.0,shape.height*0.5-shape.radius)*absf(transform.basis.y.dot(normal))
		elif shape is SphereShape3D:radius=shape.radius
		lowest=minf(lowest,transform.origin.dot(normal)-constant-radius)
	return lowest

func _process(delta: float) -> bool:
	super._process(0.0 if priming_native_dry_rest else delta)
	if service==null or not service.active:return false
	if producing and runtime.current.advanced_time_s>=15.0 and following_wave.is_empty():
		var request:={"domain_id":"main_beach","generation":runtime.generation(),"request_id":1,"start_tick":runtime.current._scheduled_tick+runtime.current.pending_count()+2,"profile_id":&"test_packet","amplitude_m":0.2,"duration_s":6.0,"seed":0}
		following_wave={"request":request,"result":runtime.request_wave(request)}
		check("larger_following_wave_publicly_admitted",following_wave.result.accepted)
	for event in full_events:
		if event.event_id<=processed_id:continue
		processed_id=event.event_id
		if event.kind==&"point_force":
			var data: Dictionary=event.data
			forces[Vector2i(data.body_id,data.point_id)]=data
		if event.kind not in [&"physics",&"sleep_step"]:continue
		var id: int=event.data.body_id;var prop: RigidBody3D=service.registry[id-1].body;var data: Dictionary=service.profiles[id]
		var buoyancy:=0.0;var max_h:=0.0
		for index in data.points.size():
			var force: Dictionary=forces.get(Vector2i(id,index+1),{})
			if force.is_empty():continue
			buoyancy+=1000.0*9.8*data.points[index].effective_volume_m3*force.fraction
			max_h=maxf(max_h,force.sample_h)
		var support: bool=event.kind==&"sleep_step"
		if event.kind==&"physics":
			var terrain_id: int=runtime.surfaces[runtime.current_index].get_node("Terrain").get_instance_id()
			for contact in event.data.contacts:support=support or contact.collider_id==terrain_id
		var clearance:=_clearance(prop);var fraction: float=buoyancy/(9.8*data.mass_kg)
		var afloat: bool=clearance>0.015 and fraction>0.65 and max_h>0.001
		var grounded: bool=absf(clearance)<=0.006 and support
		var eligible: bool=grounded if phases[id]==1 else afloat
		var step: float=event.data.get("state_step",event.data.get("effective_step_s",0.0))
		dwell[id]=float(dwell[id])+step if eligible else 0.0
		if phases[id]<3 and dwell[id]>=0.2:
			phases[id]+=1;dwell[id]=0.0
			transitions.append({"body_id":id,"phase":phases[id],"water_time_s":event.captured_time_s,"physical_time_s":event.data.actual_time_s,"clearance_m":clearance,"buoyancy_weight_ratio":fraction,"native_support":support,"position":prop.global_position})
			print("WAVE_PHASE ",id," ",phases[id]," water ",event.captured_time_s)
		trace.append({"body_id":id,"time_s":event.captured_time_s,"clearance_m":clearance,"buoyancy_weight_ratio":fraction,"support":support,"h":max_h,"phase":phases[id],"position":prop.global_position})
	var common: int=mini(phases[1],mini(phases[2],phases[3]))
	if common>0 and not captured_phases.has(common):
		captured_phases[common]=false;_capture_phase(common)
	return false

func _capture_phase(phase: int) -> void:
	await RenderingServer.frame_post_draw
	captured_phases[phase]=root.get_texture().get_image().save_png(output.get_base_dir()+"/phase_"+str(phase)+".png")==OK

func _extra_final_checks() -> void:
	super._extra_final_checks()
	observations.wave={"transitions":transitions,"trace":trace,"phases":phases,"original_instances":original_instances,"following_wave":following_wave}
	for row in service.registry:
		check("same_body_full_float_beach_refloat_"+str(row.body_id),phases[row.body_id]==3 and row.body.get_instance_id()==original_instances[row.body_id])
		var slept:=false;var woke_after_sleep:=false;var bad_run:=0.0;var max_bad_run:=0.0
		for event in full_events:
			if event.data.get("body_id")!=row.body_id:continue
			if event.kind==&"sleep_step":slept=true
			if slept and event.kind==&"wake" and event.data.reason==&"water_covered":woke_after_sleep=true
		for item in trace:
			if item.body_id!=row.body_id:continue
			bad_run=bad_run+1.0/60.0 if item.clearance_m< -0.005 else 0.0
			max_bad_run=maxf(max_bad_run,bad_run)
		check("native_sleep_then_water_wake_"+str(row.body_id),woke_after_sleep)
		check("no_sustained_below_tolerance_contact_"+str(row.body_id),max_bad_run<0.1)
	for phase in [1,2,3]:check("phase_image_"+str(phase),captured_phases.get(phase,false))

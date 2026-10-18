extends "res://tests/floating_props/lifecycle_probe.gd"

var full_events: Array=[]
var last_event_id:=0
var capture_gap:=false
var forces: Dictionary={}
var phase: Dictionary={1:0,2:0,3:0}
var dwell: Dictionary={1:0.0,2:0.0,3:0.0}
var transitions: Array=[]
var sampled_states: Array=[]
var next_wave_s:=18.0
var next_edit_s:=30.0
var next_record_s:=0.0
var max_lag_s:=0.0
var running:=false
var original_instances: Dictionary={}
var target_time_s:=180.0
var peak_water_eta: Dictionary={1:-1000000.0,2:-1000000.0,3:-1000000.0}
var wave_inputs: Array=[]

func _collect() -> void:
	if not is_instance_valid(props):return
	var fresh: Array=[]
	for index in range(props.events.size()-1,-1,-1):
		var event: Dictionary=props.events[index]
		if event.event_id<=last_event_id:break
		fresh.append(event)
	fresh.reverse()
	for event in fresh:
		if event.event_id!=last_event_id+1:capture_gap=true
		last_event_id=event.event_id;full_events.append(event)
		max_lag_s=maxf(max_lag_s,event.captured_time_s-props.origin_time_s-event.admitted_time_s)
		if event.kind==&"point_force":forces[Vector2i(event.data.body_id,event.data.point_id)]=event.data
		if event.kind not in [&"physics",&"sleep_step"]:continue
		var id: int=event.data.body_id;var profile: Dictionary=props.profiles[id];var buoyancy:=0.0
		for index in profile.points.size():
			var force: Dictionary=forces.get(Vector2i(id,index+1),{})
			if not force.is_empty():buoyancy+=1000.0*9.8*profile.points[index].effective_volume_m3*force.fraction
		var support: bool=event.kind==&"sleep_step";var speed:=0.0
		if event.kind==&"physics":
			var terrain_id: int=scene.runtime.surfaces[scene.runtime.current_index].get_node("Terrain").get_instance_id()
			var vertical_impulse:=0.0
			for contact in event.data.contacts:
				if contact.collider_id==terrain_id:vertical_impulse+=maxf(0.0,contact.impulse.y)
			support=vertical_impulse>0.05*9.8*profile.mass_kg*event.data.state_step
			speed=event.data.linear_velocity.length()
		var h:=0.0;var eta:=-1000000.0;var wet:=false
		for point in props.latest_sample.get("points",[]):
			if point.body_id==id:
				h=maxf(h,point.h)
				if point.h>props.ProbeCodec.DRY_DEPTH_M:wet=true;eta=maxf(eta,point.eta)
		if phase[id]<=2 and wet:peak_water_eta[id]=maxf(peak_water_eta[id],eta)
		var afloat: bool=not support and buoyancy>0.65*9.8*profile.mass_kg and h>props.ProbeCodec.DRY_DEPTH_M
		var eligible: bool=afloat
		if phase[id]==1:eligible=support
		# A beached board can retain a wet end. Prove actual retreat and a
		# stationary terrain-supported interval, rather than requiring all water
		# samples to be below1mm (which is a stronger, unrelated drying condition).
		if phase[id]==2:eligible=support and speed<=0.1 and buoyancy<0.95*9.8*profile.mass_kg and (not wet or peak_water_eta[id]-eta>=0.03)
		var quantum: float=event.data.get("state_step",event.data.get("effective_step_s",0.0))
		dwell[id]=float(dwell[id])+quantum if eligible else 0.0
		if phase[id]<4 and dwell[id]>=0.25:
			phase[id]+=1;dwell[id]=0.0
			transitions.append({"body_id":id,"phase":phase[id],"water_time_s":event.captured_time_s,"actual_time_s":event.data.actual_time_s,"h_m":h,"wet_eta_m":eta if wet else null,"peak_eta_m":peak_water_eta[id],"speed_m_s":speed,"support":support,"buoyancy_weight_ratio":buoyancy/(9.8*profile.mass_kg)})
			print("MAIN_LONG_PHASE ",id," ",phase[id]," time ",event.captured_time_s)

func _process(_delta: float) -> bool:
	_collect()
	if not running or scene==null or scene.runtime.current==null:return false
	var time: float=scene.runtime.current.advanced_time_s
	if time>=next_wave_s:
		var request:={"domain_id":"main_beach","generation":scene.runtime.generation(),"request_id":scene.runtime.current.boundary.highwater+1,"start_tick":scene.runtime.current._scheduled_tick+scene.runtime.current.pending_count()+2,"profile_id":&"test_packet","amplitude_m":0.1 if next_wave_s==18.0 else 0.2,"duration_s":6.0,"seed":111+int(next_wave_s)}
		var admitted: Dictionary=scene.runtime.request_wave(request);wave_inputs.append({"request":request,"result":admitted,"at_actual_time_s":time})
		check("long_public_wave_"+str(int(next_wave_s)),admitted.accepted);next_wave_s+=72.0
	if time>=next_edit_s:
		var selected: StringName=&"fill_v1" if int(next_edit_s/30.0)%2==1 else &"dig_v1";var profile: Dictionary=scene.registry.profile(selected)
		var request:={"domain_id":"main_beach","generation":scene.runtime.generation(),"command_id":scene.runtime.highwater()+1,"sim_tick":scene.runtime.current.completed_tick,"profile_id":selected,"profile_version":1,"profile_hash":profile.profile_hash,"start_xz_m":Vector2(0,4),"parameters":{"amount_m3":0.01,"radius_m":0.4},"features":{"water_policy":3}}
		check("long_public_edit_"+str(int(next_edit_s)),scene.runtime.submit_intent(request).accepted);next_edit_s+=30.0
	if time>=next_record_s:
		sampled_states.append({"water_time_s":time,"actual_time_s":props.actual_time.duplicate(),"admitted_time_s":props.admitted_time_s,"state_seq":scene.runtime.current.completed_state_seq,"phase":phase.duplicate(),"poses":_poses(),"owners":scene.runtime.current.ownership_counts()})
		print("MAIN_LONG_PROGRESS ",time," / ",target_time_s," lag ",time-props.origin_time_s-props.admitted_time_s)
		next_record_s+=10.0
	return false

func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg=="--case=short":target_time_s=40.0
		if arg=="--case=extended":target_time_s=300.0
	orphan_baseline=int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT));DisplayServer.window_set_size(Vector2i(1280,720))
	scene=load("res://scenes/main.tscn").instantiate();scene.playing=false;props=scene.get_node("FloatingProps/Service");props.trace_enabled=true;root.add_child(scene)
	var deadline:=Time.get_ticks_msec()+90000
	while (scene._booting or not scene.ready_for_ticks) and scene.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	check("long_full_main_ready",not scene._booting and scene.ready_for_ticks and props.active)
	if scene._booting:await _close();return
	for row in props.registry:original_instances[row.body_id]=row.body.get_instance_id()
	observations.profile=props.profiles.duplicate(true);observations.sources=scene.configuration.sources.duplicate(true);observations.engine=Engine.get_version_info();observations.trace_enabled=true
	running=true;scene.playing=true;deadline=Time.get_ticks_msec()+600000
	while scene.runtime.current.advanced_time_s<target_time_s and props.last_error.is_empty() and scene.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	running=false;scene.playing=false;await _wait_paused();_collect()
	check("actual_simulation_seconds_"+str(int(target_time_s)),scene.runtime.current.advanced_time_s>=target_time_s and props.last_error.is_empty() and scene.last_error.is_empty())
	check("bounded_live_consumer_lag",max_lag_s<0.5)
	check("long_event_stream_complete",not capture_gap)
	for row in props.registry:
		if target_time_s>=180.0:check("same_body_main_float_beach_dry_refloat_"+str(row.body_id),phase[row.body_id]==4 and row.body.get_instance_id()==original_instances[row.body_id])
		check("long_clock_matches_real_quanta_"+str(row.body_id),absf(props.actual_time[row.body_id]-props.admitted_time_s)<maxf(1e-6,props.admitted_time_s*1e-7))
	observations.final={"actual_time_s":props.actual_time.duplicate(),"admitted_time_s":props.admitted_time_s,"advanced_time_s":scene.runtime.current.advanced_time_s,"state_seq":scene.runtime.current.completed_state_seq,"tick":scene.runtime.current.completed_tick}
	observations.long_run={"target_time_s":target_time_s,"max_lag_s":max_lag_s,"phases":phase,"transitions":transitions,"states":sampled_states,"instances":original_instances,"wave_inputs":wave_inputs,"retreat_oracle":{"minimum_local_water_eta_drop_m":0.03,"maximum_stationary_speed_m_s":0.1,"maximum_buoyancy_weight_ratio":0.95,"minimum_terrain_support_weight_fraction":0.05,"dwell_actual_s":0.25,"all_points_dry_required":false}}
	await RenderingServer.frame_post_draw
	check("long_main_final_image",root.get_texture().get_image().save_png(output.get_base_dir()+"/main_final.png")==OK)
	await scene.shutdown();_collect();observations.events=full_events
	await _close()

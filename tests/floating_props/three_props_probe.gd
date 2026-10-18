extends "res://tests/floating_props/bottle_clock_probe.gd"

func _fixture_path() -> String:return "res://tests/floating_props/three_props_fixture.tscn"

func _extra_sources() -> PackedStringArray:
	return PackedStringArray(["res://tests/floating_props/three_props_fixture.tscn","res://scenes/props/wood_plank.tscn","res://scenes/props/wood_stick.tscn","res://assets/props/wood_plank_profile.tres","res://assets/props/wood_stick_profile.tres"])

func _target_time() -> float:
	return 1.4 if probe_case in ["tilt_width","tilt_length"] else super._target_time()

func _configure_domain(domain) -> void:
	if probe_case not in ["tilt_width","tilt_length"]:return
	for name in ["Bottle","WoodPlank","WoodStick"]:fixture.get_node(name).rotation=Vector3.ZERO
	for index in 65536:
		var x: float=(float(index%256)+0.5-128.0)*0.125
		var z: float=(float(index/256)+0.5-128.0)*0.125
		domain.water[index]=2.0+0.08*(z if probe_case=="tilt_width" else x)

func _extra_final_checks() -> void:
	check("one_service_three_profiles_nine_points",service.registry.size()==3 and service.profiles[1].points.size()==2 and service.profiles[2].points.size()==4 and service.profiles[3].points.size()==3)
	observations.all_bodies={}
	for row in service.registry:
		var prop: RigidBody3D=row.body
		observations.all_bodies[row.body_id]={"position":prop.position,"rotation":prop.rotation,"velocity":service.saved[row.body_id].linear,"angular_velocity":service.saved[row.body_id].angular,"actual_time_s":service.actual_time[row.body_id]}
		check("same_actual_clock_"+str(row.body_id),absf(service.actual_time[row.body_id]-service.admitted_time_s)<_clock_error_budget())
		check("same_body_script_"+str(row.body_id),prop.get_script()==service.Body)
		if probe_case in ["flow_positive","flow_negative"]:
			var sign_flow:=1.0 if probe_case=="flow_positive" else -1.0
			var start: Transform3D=service.layout[row.body_id]
			check("follows_flow_"+str(row.body_id),(prop.position.x-start.origin.x)*sign_flow>0.15 and service.saved[row.body_id].linear.x*sign_flow>0.08)
		elif probe_case=="normal":
			var offset: float=0.045 if row.body_id==1 else (0.004 if row.body_id==2 else 0.0)
			check("configured_static_waterline_"+str(row.body_id),absf(prop.position.y-(1.2+offset))<0.04 and absf(service.saved[row.body_id].linear.y)<0.08 and absf(prop.rotation.z)<0.2)
	if probe_case=="tilt_width":check("four_point_plank_tilts_across_width",fixture.get_node("WoodPlank").rotation.x< -0.02)
	if probe_case=="tilt_length":
		for name in ["Bottle","WoodPlank","WoodStick"]:check("length_tilt_"+name,fixture.get_node(name).rotation.z>0.02)

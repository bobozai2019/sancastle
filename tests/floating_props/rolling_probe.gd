extends "res://tests/floating_props/contact_probe.gd"

func _configure_domain(domain) -> void:
	domain.water.fill(0.0)
	for name in ["Bottle","WoodPlank","WoodStick"]:fixture.get_node(name).rotation=Vector3.ZERO
	for index in 65536:
		var z: float=(float(index/256)+0.5-128.0)*0.125
		domain.sand[index]=3.0+0.15*z

func _extra_final_checks() -> void:
	super._extra_final_checks()
	_collect_events()
	var rows: Array=[]
	for event in full_events:
		if event.kind==&"physics" and event.data.body_id==3:rows.append(event)
	observations.rolling={"slope_z":0.15,"radius_m":0.035,"native_stick_steps":rows}
	check("real_native_rolling_beyond_old_angular_guard",_exceeds_old_guard(rows))

func _exceeds_old_guard(rows: Array) -> bool:
	for event in rows:
		# Original dictionaries still contain native vectors before JSON encoding.
		if event.data.angular_velocity.length()>8.0:return true
	return false

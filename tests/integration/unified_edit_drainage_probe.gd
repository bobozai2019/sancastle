extends "res://tests/integration/unified_edit_water_probe.gd"

# Exercise the real GPU response with water ticks paused: disabling drainage
# must preserve depth/sediment exactly while still applying the local impulse.
func suspended() -> void:
	for profile_id in [&"fill_v1",&"shovel_v1"]:
		var label:=String(profile_id)
		if profile_id==&"shovel_v1":expect("begin",await perform("begin",control_identity(),"begin"),L.Outcome.NO_CHANGE)
		var command: Dictionary
		if profile_id==&"shovel_v1":command=shape_request(profile_id,Vector2.ZERO,Vector2(1,0),1,{"speed_m_s":0.25},1,11,2)
		else:
			command=local_request(profile_id,Vector2(3,0),{"speed_m_s":0.25})
			command.features.material_policy=0
		command.features.water_policy=2
		var result:=await perform(label,command)
		expect(label,result,L.Outcome.APPLIED)
		if result.is_empty():return
		var sample: Dictionary=cases[-1]
		for field in ["water","water1","sediment0","sediment1"]:
			check(label+"_preserves_"+field,sample.before[field].sha256==sample.after[field].sha256)
		check(label+"_still_pushes_water",sample.before.qx0.sha256!=sample.after.qx0.sha256 or sample.before.qz0.sha256!=sample.after.qz0.sha256)
		check(label+"_zero_instant_displacement",result.displaced_water_m3==0.0 and result.retained_water_m3==0.0)
		var stages: Array=pipeline.executor.traces[-1].water_stages
		check(label+"_skips_connectivity",stages.has("velocity_only") and not stages.has("packed"))
		check(label+"_uses_parallel_prepare",stages.has("velocity_prepare_parallel") and not stages.has("displace"))
		check(label+"_keeps_audit",stages.has("audit_merge") and stages.has("velocity_reduce"))
		if profile_id==&"shovel_v1":expect("end",await perform("end",control_identity(),"end"),L.Outcome.NO_CHANGE)
	var enabled:=local_request(&"fill_v1",Vector2(-3,0),{"speed_m_s":0.25})
	enabled.features.material_policy=0
	enabled.features.water_policy=3
	var result:=await perform("enabled",enabled)
	expect("enabled",result,L.Outcome.APPLIED)
	if result.is_empty():return
	check("reenabled_displaces_water",result.displaced_water_m3>0.0 and cases[-1].before.water.sha256!=cases[-1].after.water.sha256)
	check("reenabled_uses_packed",pipeline.executor.traces[-1].water_stages.has("packed"))
	for policy in [0,1]:
		var invalid:=local_request(&"fill_v1",Vector2.ZERO,{"speed_m_s":0.25});invalid.features.water_policy=policy
		invalid.features.material_policy=0
		check("inactive_impulse_rejected_"+str(policy),not pipeline.submit_intent(invalid).accepted)
	observations.traces=pipeline.executor.traces.duplicate(true)

extends "res://tools/muscl_performance/formal_inputs.gd"

var compact_material_diagnostic:=false

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg=="--case=material_diagnostic":compact_material_diagnostic=true
	super._initialize()
	if compact_material_diagnostic:ticks=101

func capture_render() -> void:
	if not compact_material_diagnostic:super.capture_render();return
	var rd: RenderingDevice=owner.state.rd
	var result:={"decision":rd.buffer_get_data(owner.water.decision),"control":rd.buffer_get_data(owner.transport.control),"accepted_indirect":rd.buffer_get_data(owner.water.indirect)}
	for name in owner.water.muscl.buffers:result["muscl_"+name]=rd.buffer_get_data(owner.water.muscl.buffers[name])
	capture_received.call_deferred(result)

func before_tick(tick: int) -> void:
	await super.before_tick(tick)
	if tick==90:
		var profile: Dictionary=beach.registry.profile(&"suspended_v1")
		var parameters: Dictionary=profile.defaults.duplicate(true);parameters.amount_m3=0.02;parameters.radius_m=0.5
		var request:={"domain_id":beach._domain_id(),"generation":beach.generation,"command_id":7,"sim_tick":tick,"profile_id":&"suspended_v1","profile_version":profile.version,"profile_hash":profile.profile_hash,"start_xz_m":Vector2(-8,0),"parameters":parameters,"features":{"water_policy":0},"seed":101}
		check("fixed_suspended_admitted",owner.submit_intent(request).accepted)
		await material_idle()
		print("FIXED_MATERIAL_RESULT suspended ",JSON.stringify(owner.result(7)))
		check("fixed_suspended_applied",owner.result(7).get("outcome",-1)==owner.L.Outcome.APPLIED)
	if tick==100:
		var identity:={"domain_id":beach._domain_id(),"generation":beach.generation,"command_id":8,"sim_tick":tick,"stroke_id":9001,"baseline_token":9001}
		check("fixed_molded_begin",owner.submit_control("begin",identity).accepted)
		var command=Brush.make_command(&"wall_v1",{"height_m":0.3,"bottom_width_m":1.0,"top_width_m":0.5},Vector2(3,2.5),Vector2(3,3.5),beach._domain_id(),beach.generation,9,9001,0,tick,9001)
		command.material_profile_id=&"molded_v1";command.water_policy=2;command.speed_m_s=0.25
		check("fixed_molded_command",owner.submit_legacy(command,2,0.25).accepted)
		identity.command_id=10;check("fixed_molded_end",owner.submit_control("end",identity).accepted)
		await material_idle()
		print("FIXED_MATERIAL_RESULT molded ",JSON.stringify(owner.result(9)))
		check("fixed_molded_applied",owner.result(9).get("outcome",-1)==owner.L.Outcome.APPLIED)

func material_idle() -> void:
	var deadline:=Time.get_ticks_msec()+30000
	while (owner.pending_count()>0 or owner.active_count()>0) and owner.fault_reason().is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	check("material_inputs_idle",owner.fault_reason().is_empty() and owner.pending_count()==0 and owner.active_count()==0)

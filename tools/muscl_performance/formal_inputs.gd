extends "res://tools/muscl_performance/formal_states.gd"

const Brush=preload("res://scripts/simulation/brushes/brush_protocol.gd")

func before_tick(tick: int) -> void:
	if tick==10:
		var wave: Dictionary=beach.runtime.request_wave({"domain_id":beach._domain_id(),"generation":beach.generation,"request_id":1,"start_tick":12,"profile_id":&"test_packet","amplitude_m":0.1,"duration_s":1.0,"seed":48})
		check("fixed_wave_accepted",wave.accepted)
	if tick not in [40,70]:return
	var stroke:=7001+tick
	var command_id:=1 if tick==40 else 4
	var identity:={"domain_id":beach._domain_id(),"generation":beach.generation,"command_id":command_id,"sim_tick":tick,"stroke_id":stroke,"baseline_token":stroke}
	check("fixed_tool_begin",owner.submit_control("begin",identity).accepted)
	var command=Brush.make_command(&"shovel_v1",{"trench_width_m":0.5,"depth_m":0.15,"shoulder_width_m":0.5},Vector2(0,-0.5),Vector2(0,0.5),beach._domain_id(),beach.generation,command_id+1,stroke,0,tick,stroke)
	command.material_profile_id=&"plain_sand_v1";command.water_policy=2;command.speed_m_s=0.25
	check("fixed_tool_command",owner.submit_legacy(command,2,0.25).accepted)
	identity.command_id=command_id+2
	check("fixed_tool_end",owner.submit_control("end",identity).accepted)
	var deadline:=Time.get_ticks_msec()+30000
	while (owner.pending_count()>0 or owner.active_count()>0) and owner.fault_reason().is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	check("fixed_tool_applied",owner.result(command_id+1).get("outcome",-1)==owner.L.Outcome.APPLIED)

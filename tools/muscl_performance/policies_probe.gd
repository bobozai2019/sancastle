extends "res://tools/muscl_performance/formal_states.gd"

const Brush=preload("res://scripts/simulation/brushes/brush_protocol.gd")
var target:=Vector2.ZERO
var policy_results: Array=[]

func _initialize() -> void:
	super._initialize()
	ticks=4

func before_tick(tick: int) -> void:
	if tick==0:
		capture_done=false;RenderingServer.call_on_render_thread(capture_render)
		while not capture_done:await process_frame
		var found:=false
		# Stay away from domain boundaries and select an actually wet seed cell.
		for z in range(80,176):
			for x in range(64,192):
				var clear:=true
				for dz in range(-8,9):
					for dx in range(-8,9):
						if captured.obstacle[(z+dz)*256+x+dx]!=0:clear=false
				if clear and captured.water_0.decode_float((z*256+x)*4)>0.2:
					target=Vector2((float(x)+0.5-128.0)*0.125,(float(z)+0.5-128.0)*0.125);found=true;break
			if found:break
		check("wet_edit_target_found",found)
	var command_id:=tick*3+1;var stroke:=8100+tick
	var identity:={"domain_id":beach._domain_id(),"generation":beach.generation,"command_id":command_id,"sim_tick":tick,"stroke_id":stroke,"baseline_token":stroke}
	check("policy_begin:"+str(tick),owner.submit_control("begin",identity).accepted)
	var command=Brush.make_command(&"wall_v1",{"height_m":0.3,"bottom_width_m":1.0,"top_width_m":0.5},target,target+Vector2(0.0,0.25),beach._domain_id(),beach.generation,command_id+1,stroke,0,tick,stroke)
	var speed:=0.25 if tick in [2,3] else 0.0
	command.material_profile_id=&"plain_sand_v1";command.water_policy=tick;command.speed_m_s=speed
	var admission: Dictionary=owner.submit_legacy(command,tick,speed)
	check("policy_command:"+str(tick),admission.accepted)
	if not admission.accepted:print("POLICY_ADMISSION ",JSON.stringify(admission))
	identity.command_id=command_id+2;check("policy_end:"+str(tick),owner.submit_control("end",identity).accepted)
	var deadline:=Time.get_ticks_msec()+30000
	while (owner.pending_count()>0 or owner.active_count()>0) and owner.fault_reason().is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	check("policy_idle:"+str(tick),owner.pending_count()==0 and owner.active_count()==0 and owner.fault_reason().is_empty())
	var result: Dictionary=owner.result(command_id+1)
	check("policy_applied:"+str(tick),result.get("outcome",-1)==owner.L.Outcome.APPLIED)
	policy_results.append({"policy":tick,"result":result})
	FileAccess.open(output.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"pass":not failed,"target":target,"policies":policy_results,"scope":"Fixed wet-domain wall edits for policies0–3 through public begin/legacy/end; full dual-slot/control/ledger snapshots after each completed edit and water tick"},"\t"))

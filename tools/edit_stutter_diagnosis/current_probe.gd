extends "res://tools/unified_edit_pipeline/diagnose_shovel_latency.gd"

# Current formal main scene with opt-in diagnostics. The optional reference
# selects the former deferred retirement ACK; numeric and rendering work stay.
var sample_count:=160
var policy_override:=-1
var deferred_retirement_reference:=false

func _initialize() -> void:
	super._initialize()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--samples="):sample_count=int(arg.trim_prefix("--samples="))
		if arg.begins_with("--policy="):policy_override=int(arg.trim_prefix("--policy="))
		if arg=="--deferred-retirement-reference":deferred_retirement_reference=true
	probe_sources[get_script().resource_path]=FileAccess.get_sha256(get_script().resource_path)

func _configured() -> void:
	# Probe-only reference: force the existing cross-thread ACK branch, which
	# exactly reproduces the former unconditional call_deferred retirement.
	# No slot state, transport proof, dispatch, or numeric work is substituted.
	if deferred_retirement_reference:scene.runtime.current._owner_thread_id=-1
	super._configured()

func _exercise() -> void:
	check("supported_edit_tool",case_id in ["dig","fill"])
	var tool: StringName=&"remove_sand" if case_id=="dig" else &"place_sand"
	scene.panel._on_tool_pressed(tool)
	if policy_override>=0:scene.water_policy=policy_override
	var amount: float=scene.dig_amount_m3 if case_id=="dig" else scene.fill_amount_m3
	observations.current_probe={
		"tool":tool,"amount_m3":amount,"policy":scene.water_policy,
		"policy_override":policy_override,"speed_m_s":scene.signed_speed_m_s,
		"samples_per_phase":sample_count,"seed":101,
		"viewport":root.get_visible_rect().size,
		"camera_transform":str(root.get_camera_3d().global_transform),
		"initial_completed_tick":scene.runtime.current.completed_tick,
		"initial_completed_state_seq":scene.runtime.current.completed_state_seq
	}
	observations.current_probe.retirement_variant="deferred_reference" if deferred_retirement_reference else "owner_thread_ack"
	check("visible_full_window",DisplayServer.get_name()!="headless" and root.visible and DisplayServer.window_get_size()==Vector2i(1280,720))
	phase="paused_idle"
	for i in 60:await process_frame
	phase="playing_idle";scene.playing=true
	for i in 120:await process_frame
	for live in [true,false]:
		phase="playing_drag" if live else "paused_drag";scene.playing=live
		for stroke in 2:
			var point:=start_point+Vector2(stroke*0.35,-1.5)
			var before:=Time.get_ticks_usec()
			var admitted: Dictionary=scene.input.begin(tool,point,scene.panel.parameters(),amount,scene.water_policy,scene.signed_speed_m_s)
			samples.append({"phase":phase,"action":"begin","cpu_us":Time.get_ticks_usec()-before,"at_us":before,"frame":Engine.get_process_frames(),"response":admitted})
			for step in sample_count/2:
				point=start_point+Vector2(stroke*0.35,-1.5+3.0*float(step+1)/(sample_count/2))
				var screen: Vector2=root.get_camera_3d().unproject_position(Vector3(point.x,1.0,point.y))
				before=Time.get_ticks_usec();var hit: Dictionary=scene.pick(screen);var pick_us:=Time.get_ticks_usec()-before
				before=Time.get_ticks_usec();var result: Dictionary=scene.input.move(point);var move_us:=Time.get_ticks_usec()-before
				var preview_started:=Time.get_ticks_usec();scene.preview_at(point)
				samples.append({"phase":phase,"action":"move","frame":Engine.get_process_frames(),"at_us":before,"move_cpu_us":move_us,"pick_cpu_us":pick_us,"preview_submit_cpu_us":Time.get_ticks_usec()-preview_started,"pick_hit":not hit.is_empty(),"response":result})
				await process_frame
			scene.input.finish()
		phase+="_tail"
		for i in 60:await process_frame

func _capture_scope() -> String:
	return "Current formal main, default dig/fill amount and water policy unless explicitly overridden. Optional deferred-retirement-reference reproduces the former ACK scheduling branch without changing product source. Fixed initial footprint, two 3m strokes per live/paused phase using real PlayerInput and preview. One move per rendered frame; not a wall-clock input-rate test. Ray pick timed but does not choose path. Evolving phases are not identical-state A/B."

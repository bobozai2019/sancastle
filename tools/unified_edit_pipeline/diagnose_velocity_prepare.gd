extends "res://tools/unified_edit_pipeline/diagnose_shovel_latency.gd"

# Same visible main scene, selected wet footprint, simulation and inputs for
# both runs. Only the velocity-only preparation dispatch is substituted.
func _initialize() -> void:
	super._initialize()
	probe_sources[get_script().resource_path]=FileAccess.get_sha256(get_script().resource_path)

func _exercise() -> void:
	scene._on_connected_drainage_toggled(false)
	observations.velocity_prepare={"policy":scene.water_policy,"reference_serial":"--reference-velocity" in OS.get_cmdline_user_args(),"samples_per_phase":64}
	phase="paused_idle"
	for i in 30:await process_frame
	phase="playing_idle";scene.playing=true
	for i in 60:await process_frame
	for live in [true,false]:
		phase="playing_drag" if live else "paused_drag";scene.playing=live
		var point:=start_point+Vector2(0.0 if live else 0.35,-1.5)
		var before:=Time.get_ticks_usec()
		var admitted: Dictionary=scene.input.begin(&"shovel_v1",point,scene.panel.parameters(),0.1,scene.water_policy,scene.signed_speed_m_s)
		samples.append({"phase":phase,"action":"begin","cpu_us":Time.get_ticks_usec()-before,"at_us":before,"frame":Engine.get_process_frames(),"response":admitted})
		for step in 64:
			point=start_point+Vector2(0.0 if live else 0.35,-1.5+3.0*float(step+1)/64.0)
			before=Time.get_ticks_usec()
			var result: Dictionary=scene.input.move(point);var move_us:=Time.get_ticks_usec()-before
			scene.preview_at(point)
			samples.append({"phase":phase,"action":"move","frame":Engine.get_process_frames(),"at_us":before,"move_cpu_us":move_us,"response":result})
			await process_frame
		scene.input.finish();phase+="_tail"
		for i in 30:await process_frame

func _capture_scope() -> String:
	return "Visible main/default shovel, water_policy2, 64 samples each live/paused phase. Reference flag changes only candidate preparation. Frame pacing changes simulation/input timing; not bit-identical evolved domains or a manual-user trace."

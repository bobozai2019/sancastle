extends "res://tools/unified_edit_pipeline/diagnose_shovel_latency.gd"

# Diagnostic only: retain the actual main scene, water tick and tool path.
var long_strokes: Array=[]
var sweep_area:=false

func _initialize() -> void:
	super._initialize()
	sweep_area="--sweep-area" in OS.get_cmdline_user_args()
	probe_sources["res://tools/unified_edit_pipeline/diagnose_shovel_long.gd"]=FileAccess.get_sha256("res://tools/unified_edit_pipeline/diagnose_shovel_long.gd")

func _long_idle(seconds: float, label: String, live: bool) -> void:
	phase=label;scene.playing=live
	var until:=Time.get_ticks_usec()+int(seconds*1000000.0)
	while Time.get_ticks_usec()<until:await process_frame

func _exercise() -> void:
	if manual:
		await _long_idle(5.0,"manual_before_idle",true)
		await super._exercise()
		DisplayServer.window_set_title("Shovel trace: capture complete; measuring released tail")
		await _long_idle(15.0,"manual_release_live",true)
		await _long_idle(5.0,"manual_release_paused",false)
		return
	await _long_idle(5.0,"long_before_idle",true)
	scene.playing=true
	var started:=Time.get_ticks_usec();var stroke:=0
	while Time.get_ticks_usec()-started<int(duration_s*1000000.0):
		phase="long_drag_"+str(int((Time.get_ticks_usec()-started)/10000000))
		# Three nearby tracks repeatedly deepen and reshape the same footprint.
		var direction:=1.0 if stroke%2==0 else -1.0
		var offset:=float(stroke%14)*0.55-2.0 if sweep_area else float(stroke%3)*0.35
		var half_length:=4.0 if sweep_area else 1.5
		var steps:=214 if sweep_area else 80
		var point:=start_point+Vector2(offset,-half_length*direction)
		var before:=Time.get_ticks_usec()
		var admitted: Dictionary=scene.input.begin(&"shovel_v1",point,scene.panel.parameters(),0.1,scene.water_policy,scene.signed_speed_m_s) if not sweep_area or stroke==0 else scene.input.move(point)
		samples.append({"phase":phase,"action":"begin","at_us":before,"frame":Engine.get_process_frames(),"response":admitted})
		long_strokes.append({"stroke":stroke,"at_us":before,"point":point,"parameters":scene.panel.parameters(),"admitted":admitted})
		for step in steps:
			phase="long_drag_"+str(int((Time.get_ticks_usec()-started)/10000000))
			point=start_point+Vector2(offset,direction*(-half_length+2.0*half_length*float(step+1)/float(steps)))
			var camera:=root.get_camera_3d();var screen: Vector2=camera.unproject_position(Vector3(point.x,1.0,point.y))
			before=Time.get_ticks_usec();var hit: Dictionary=scene.pick(screen);var pick_us:=Time.get_ticks_usec()-before
			before=Time.get_ticks_usec();var result: Dictionary=scene.input.move(point);var move_us:=Time.get_ticks_usec()-before
			before=Time.get_ticks_usec();scene.preview_at(point);var preview_us:=Time.get_ticks_usec()-before
			samples.append({"phase":phase,"action":"move","frame":Engine.get_process_frames(),"at_us":before,"move_cpu_us":move_us,"pick_cpu_us":pick_us,"preview_submit_cpu_us":preview_us,"pick_hit":not hit.is_empty(),"response":result})
			await process_frame
			if Time.get_ticks_usec()-started>=int(duration_s*1000000.0):break
		if not sweep_area:scene.input.finish()
		stroke+=1
	scene.input.finish()
	await _long_idle(15.0,"long_release_live",true)
	await _long_idle(5.0,"long_release_paused",false)

func _observe() -> void:
	super._observe()
	var row: Dictionary=frames.back()
	row.memory_static=Performance.get_monitor(Performance.MEMORY_STATIC)
	row.object_count=Performance.get_monitor(Performance.OBJECT_COUNT)

func finish() -> void:
	observations.long_strokes=long_strokes
	observations.long_pattern="manual" if manual else ("held_area_sweep" if sweep_area else "repeated_three_tracks")
	if (water_only or detail_gpu) and observer!=null and observer.response!=null:
		observations.water_calls=observer.response.calls.duplicate(true)
	super.finish()

func _capture_scope() -> String:
	if manual:return super._capture_scope()
	return "Visible main/default shovel, live water, held 8m adjacent tracks or repeated three nearby 3m tracks (long_pattern), one sample per process frame, 10s wall-time bins; then 15s released live and 5s paused. Variable throughput changes simulated time and edit count. Not identical user path or a fixed-state performance gate."

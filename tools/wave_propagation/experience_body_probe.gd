extends "res://tools/wave_propagation/experience_probe.gd"
# Diagnostic completed-time pacing: main auto-queue disabled; all children,
# common publication, collision, Probe and real Jolt grants remain active.
func _process(delta: float) -> bool:
	if scene != null and not scene.is_processing():
		scene.input.poll()
		scene._update_reflection()
	return super._process(delta)

func snapshot(label: String) -> void:
	check("real_solver:"+label,owner.state.water_solver_id == solver_id and (owner.water.muscl != null) == (solver_id == "muscl_mc_ssprk2_v1"))
	await super.snapshot(label)
	if scene == null: return
	var props = scene.floating_props
	var deadline := Time.get_ticks_msec()+20000
	# The production service admits complete physical quanta with its existing
	# 1e-7 budget tolerance. Wait for that exact number AND terminal callbacks,
	# rather than accepting a one-quantum observation lag.
	var quantum := 1.0 / float(Engine.physics_ticks_per_second)
	var target_steps := int(floor((owner.advanced_time_s-props.origin_time_s+1e-7)/quantum))
	var target_time := float(target_steps)*quantum
	while props.last_error.is_empty() and (props.admitted_time_s < target_time-1e-7 or not props.expected_steps.is_empty()) and Time.get_ticks_msec()<deadline:
		await process_frame
	var clock_ok: bool = props.last_error.is_empty() and absf(props.admitted_time_s-target_time)<1e-7 and props.expected_steps.is_empty()
	for row in props.registry:
		clock_ok = clock_ok and int(round(float(props.actual_time.get(row.body_id,0.0))/quantum)) == target_steps
	check("body_clock:"+label,clock_ok)
	var bodies: Array=[]
	for row in props.registry:
		var body: RigidBody3D=row.body
		bodies.append({"body_id":row.body_id,"position_m":[body.position.x,body.position.y,body.position.z],"linear_velocity_m_s":[body.linear_velocity.x,body.linear_velocity.y,body.linear_velocity.z],"angular_velocity_rad_s":[body.angular_velocity.x,body.angular_velocity.y,body.angular_velocity.z],"frozen":body.freeze,"actual_time_s":props.actual_time.get(row.body_id,0.0)})
	var report := {"label":label,"quantum_s":quantum,"target_steps":target_steps,"target_time_s":target_time,"water_time_s":owner.advanced_time_s,"admitted_time_s":props.admitted_time_s,"origin_time_s":props.origin_time_s,"last_sample_time_s":props.last_sample_time_s,"sample":props.sample,"events":props.events.duplicate(true),"evicted":props.events_evicted,"bodies":bodies,"error":String(props.last_error),"holds":props.holds,"generation":str(props.generation)}
	var path: String=output.path_join(current.id).path_join(label+"_props.json")
	FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	current.snapshots[-1].props={"path":path,"sha256":FileAccess.get_sha256(path)}
	props.events.clear();props.events_evicted=0
	if label == "edited" or (label == "before" and current.id == "main_control"):
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join(current.id).path_join("frame_000.png"))

func run_main() -> void:
	var packed = load("res://scenes/main.tscn")
	check("main_scene_loaded", packed is PackedScene)
	if failed: return
	scene = packed.instantiate()
	scene.playing = false
	scene.water_solver_id = solver_id
	# Place the already-authored bodies before attach; no active service reset.
	scene.get_node("FloatingProps/Bottle").position.x = -1.5625
	scene.get_node("FloatingProps/Bottle").position.z = 0.0625
	scene.get_node("FloatingProps/WoodPlank").position.x = -2.5625
	scene.get_node("FloatingProps/WoodPlank").position.z = 0.0625
	root.add_child(scene)
	var began := Time.get_ticks_msec()
	while (not scene.ready_for_ticks or scene._booting) and scene.last_error.is_empty() and Time.get_ticks_msec()-began<90000: await process_frame
	check("main_ready:" + String(scene.last_error),scene.ready_for_ticks and scene.last_error.is_empty())
	if failed: return
	owner = scene.runtime.current
	scene.floating_props.trace_enabled = true
	sources.merge(scene.configuration.sources)
	var save_path := output.path_join("main_initial.sandue")
	check("save",(await scene.save_gpu_checkpoint(save_path)).is_empty())
	for kind in ["main_control","main_shovel"]:
		if kind != "main_control":
			scene.set_process(true)
			check("restore",(await scene.restore_gpu_checkpoint(save_path)).is_empty())
			var restore_started := Time.get_ticks_msec()
			while not scene.ready_for_ticks and scene.last_error.is_empty() and Time.get_ticks_msec()-restore_started < 90000: await process_frame
			check("restore_readmitted",scene.ready_for_ticks and scene.last_error.is_empty())
			owner = scene.runtime.current
		scene.set_process(false)
		scene.hide_hud = true
		while scene.floating_props.busy: await physics_frame
		check("real_body_unpause",(await scene.floating_props.set_paused(false,&"user")).error.is_empty())
		scene.floating_props.events.clear(); scene.floating_props.events_evicted = 0
		current = {"id":kind,"snapshots":[],"configuration":scene.configuration,"camera":str(scene.player_camera.global_transform)}
		await snapshot("before")
		if kind == "main_shovel":
			var parameters := {"trench_width_m":0.5,"depth_m":0.15,"shoulder_width_m":0.5}
			check("main_begin",scene.input.begin(&"shovel_v1",Vector2(0,-0.5),parameters,0.1,2,0.25).accepted)
			check("main_move",scene.input.move(Vector2(0,0.5)).accepted)
			check("main_end",scene.input.finish().accepted)
			await idle()
			current.tool = {"start":[0,-0.5],"end":[0,0.5],"parameters":parameters,"policy":2,"speed_m_s":0.25,"terminals":scene.input.terminal.duplicate(true)}
			await snapshot("edited")
		await advance_and_capture()
		cases.append(current)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join(kind+"_4s.png"))
		if failed: break
	scene.set_process(true)
	await scene.shutdown()
	check("main_released",scene.unified_release_complete())
	var service = root.get_node("BeachScenes")
	if service.active_scene == scene: service.active_scene = null
	root.remove_child(scene)
	scene.free()
	scene = null
	owner = null


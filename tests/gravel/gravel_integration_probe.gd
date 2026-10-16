extends "res://tests/gravel/gravel_scene_switch_probe.gd"

var trace_file: FileAccess
var trackers := {}
var closure := {}
var motion_counts := {}
var sampled_frames := 0
var total_ticks := 0
var stability := false
var overlay: Label
var resources := []

func _process(_delta: float) -> bool:
	if overlay!=null and is_instance_valid(preview):
		overlay.text="%s | tick %d | sim %.2fs | render frame %d" % [preview.scene_key,preview.completed_ticks,preview.completed_ticks/30.0,Engine.get_frames_drawn()]
	return false

func _sample_bilinear(values: PackedFloat32Array, x: float, z: float) -> float:
	var cx := (x+16.0)/0.125-0.5
	var cz := (z+16.0)/0.125-0.5
	var ix := floori(cx)
	var iz := floori(cz)
	var fx := cx-ix
	var fz := cz-iz
	var a := values[clampi(iz,0,255)*256+clampi(ix,0,255)]
	var b := values[clampi(iz,0,255)*256+clampi(ix+1,0,255)]
	var c := values[clampi(iz+1,0,255)*256+clampi(ix,0,255)]
	var d := values[clampi(iz+1,0,255)*256+clampi(ix+1,0,255)]
	return lerpf(lerpf(a,b,fx),lerpf(c,d,fx),fz)

func _trace() -> void:
	var particles := await _gravel()
	var authority := await _snapshot()
	var water: PackedFloat32Array=authority.water.to_float32_array()
	var qx: PackedFloat32Array=authority.momentum_x.to_float32_array()
	var qz: PackedFloat32Array=authority.momentum_z.to_float32_array()
	var values: PackedFloat32Array=particles["state_%d" % particles.current_index].to_float32_array()
	var key: String=preview.scene_key
	if not trackers.has(key): trackers[key]={}
	if not motion_counts.has(key): motion_counts[key]=0
	var finite := true
	for id in 512:
		var p := Vector3(values[id*4],values[id*4+1],values[id*4+2])
		var wet: float=values[id*4+3]
		var h := maxf(0.0,_sample_bilinear(water,p.x,p.z))
		var u := Vector2(_sample_bilinear(qx,p.x,p.z),_sample_bilinear(qz,p.x,p.z))/maxf(h,0.006)
		finite=finite and is_finite(p.x) and is_finite(p.y) and is_finite(p.z) and absf(p.x)<=16 and absf(p.z)<=16 and wet in [0.0,1.0]
		var tracking: Dictionary=trackers[key].get(id,{"phase":0,"p":p,"wet":wet,"tick":particles.tick,"dry_samples":0})
		var dx: float = p.x-tracking.p.x
		var dz: float = p.z-tracking.p.z
		if absf(dx)+absf(dz)>0.00001: motion_counts[key]+=1
		if tracking.phase==0 and wet==1.0 and dx>0.00001:
			tracking.phase=1
			tracking.onshore_tick=particles.tick
		elif tracking.phase==1 and wet==0.0 and tracking.wet==0.0 and absf(dx)+absf(dz)==0.0:
			tracking.dry_samples+=1
			if tracking.dry_samples>=2:
				tracking.phase=2
				tracking.stranded_tick=particles.tick
		elif tracking.phase==2 and wet==1.0 and dx< -0.00001 and u.x<0.0:
			tracking.phase=3
			tracking.restarted_tick=particles.tick
			if not closure.has(key):
				closure[key]={"id":id,"onshore_tick":tracking.onshore_tick,"stranded_tick":tracking.stranded_tick,"restarted_tick":particles.tick,"rewet_u_x_m_s":u.x,"delta_x_m":dx}
				print("GRAVEL_REAL_CLOSURE ",key," ",JSON.stringify(closure[key]))
		trace_file.store_line(JSON.stringify({"scene":key,"id":id,"generation":preview.generation,"tick":particles.tick,"simulation_seconds":particles.tick/30.0,"wall_usec":Time.get_ticks_usec(),"render_frame":Engine.get_frames_drawn(),"revision":particles.revision,"p":[p.x,p.y,p.z],"wet":wet,"local_h":h,"local_u":[u.x,u.y],"local_sampling":"completed-state at destination; not pre-step field","phase":tracking.phase}))
		tracking.p=p;tracking.wet=wet;tracking.tick=particles.tick
		trackers[key][id]=tracking
	sampled_frames+=1
	_check("finite_"+key+"_"+str(particles.tick),finite)
	if sampled_frames%10==0:
		print("GRAVEL_INTEGRATION_PROGRESS ",total_ticks/30.0," sim_s; closures=",JSON.stringify(closure))
	trace_file.flush()

func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg=="--stability": stability=true
	if output.is_empty(): output="res://test_output/gpu_gravel/integration_"+str(Time.get_unix_time_from_system()).replace(".","_")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	trace_file=FileAccess.open(output.path_join("trace.jsonl"),FileAccess.WRITE)
	root.size=Vector2i(1280,720) if stability else Vector2i(640,360)
	service=root.get_node("BeachScenes")
	preview=load("res://scenes/playable/test1_backwash.tscn").instantiate()
	preview.playing=false
	preview.hide_hud=true
	root.add_child(preview)
	var overlay_scene: Node=load("res://tests/gravel/movie_overlay.tscn").instantiate()
	root.add_child(overlay_scene)
	overlay=overlay_scene.get_node("Status")
	current_scene=preview
	var deadline := Time.get_ticks_msec()+120000
	while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_msec()<deadline: await process_frame
	_check("backwash_ready",preview.ready_for_ticks,preview.last_error)
	if not preview.ready_for_ticks: _finish();quit(1);return
	var segments := [{"scene":"test1_backwash","ticks":1200}]
	if stability: segments=[{"scene":"test1_backwash","ticks":1800},{"scene":"main","ticks":1800},{"scene":"test1_capture","ticks":1800}]
	for segment in segments:
		if preview.scene_key!=segment.scene: await _switch(segment.scene)
		preview.player_camera.position=Vector3(-3,2.5,4)
		preview.player_camera.look_at(Vector3(-2,0.2,0))
		preview.set_player_camera(true)
		preview.player_camera.set_process(false)
		await _frames()
		root.get_texture().get_image().save_png(output.path_join(segment.scene+"_start.png"))
		await _trace()
		for block in int(segment.ticks/30):
			await _ticks(30)
			total_ticks+=30
			await _trace()
			if stability and block==20:
				var held := await _gravel()
				await create_timer(0.5).timeout
				var paused := await _gravel()
				_check("stability_pause_"+segment.scene,_same(held,paused))
			if stability and block==30:
				var command: Dictionary={"domain_id":preview.shadow_domain.domain_id,"generation":preview.generation,"sim_tick":preview.completed_ticks,"command_id":preview.command_queue.last_command_id+1,"kind":&"place_sand","shape":&"circle","transform":{"position_m":Vector3(-2,0,0),"end_position_m":Vector3(-2,0,0)},"radius_m":0.3,"strength":1.0,"amount_m3":0.01,"seed":101}
				var error: StringName=preview.input_scheduler.submit(command)
				await preview.input_scheduler.drain_due()
				_check("stability_edit_"+segment.scene,error.is_empty() and preview.last_error.is_empty())
			if stability and block==40:
				var checkpoint_path := output.path_join(segment.scene+"_stability.bin")
				var save_error: StringName=await preview.save_gpu_checkpoint(checkpoint_path)
				var before:=await _gravel()
				var restore_error: StringName=await preview.restore_gpu_checkpoint(checkpoint_path)
				var after:=await _gravel()
				_check("stability_restore_"+segment.scene,save_error.is_empty() and restore_error.is_empty() and _same(before,after))
		await _settle()
		resources.append({"scene":segment.scene,"tick":preview.completed_ticks,"gravel_textures":preview.gravel_field.textures.size(),"gravel_uniform_sets":preview.gravel_field.uniform_sets.size(),"gravel_pending":preview.gravel_field.pending,"gravel_owner_callbacks":preview.gravel_capture_callbacks,"static_memory":Performance.get_monitor(Performance.MEMORY_STATIC),"resource_count":Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),"node_count":Performance.get_monitor(Performance.OBJECT_NODE_COUNT)})
		root.get_texture().get_image().save_png(output.path_join(segment.scene+"_end.png"))
		_check("actual_motion_"+segment.scene,motion_counts.get(segment.scene,0)>0,motion_counts.get(segment.scene,0))
	if stability:
		await _switch("test1_backwash")
		_check("180_sim_seconds",total_ticks==5400)
	else:
		_check("actual_backwash_strand_reverse_restart",closure.has("test1_backwash"),closure)
	trace_file.close()
	FileAccess.open(output.path_join("resource_samples.json"),FileAccess.WRITE).store_string(JSON.stringify(resources,"\t"))
	FileAccess.open(output.path_join("integration.json"),FileAccess.WRITE).store_string(JSON.stringify({"closure":closure,"motion_counts":motion_counts,"simulated_ticks":total_ticks,"simulated_seconds":total_ticks/30.0,"snapshot_count":sampled_frames,"seed":preview.gravel_profile.seed,"profile":preview.gravel_profile,"window":[root.size.x,root.size.y],"gpu":RenderingServer.get_video_adapter_name(),"driver":RenderingServer.get_current_rendering_driver_name(),"movie_timing":"render_frame ties trace to engine movie frames; simulation time uses completed_tick/30, never wall fps","resource_releases":service.release_records},"\t"))
	await preview.shutdown()
	_check("shutdown",preview.gpu_release_done and preview.gravel_field==null)
	_finish()
	print("GRAVEL_INTEGRATION_OUTPUT ",output)
	var passed := true
	for row in checks: passed=passed and row.pass
	quit(0 if passed else 1)

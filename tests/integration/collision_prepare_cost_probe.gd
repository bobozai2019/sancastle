extends SceneTree

var output := ""
var scene
var proxy
var samples := []
var checks := []
var revision := 0

func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	call_deferred("_run")

func check(name: String, passed: bool) -> void:
	checks.append({"name":name,"pass":passed})
	if not passed:printerr("PREPARE_COST_FAIL ",name)

func _run() -> void:
	if output.is_empty():quit(2);return
	DirAccess.make_dir_recursive_absolute(output)
	root.size=Vector2i(1920,1080);DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	scene=load("res://scenes/main.tscn").instantiate();scene.playing=false;root.add_child(scene)
	var deadline:=Time.get_ticks_msec()+90000
	while not scene.ready_for_ticks and scene.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	check("main_ready",scene.ready_for_ticks and scene.last_error.is_empty())
	if not scene.ready_for_ticks:quit(1);return
	proxy=load("res://scenes/gpu_collision_proxy.tscn").instantiate()
	proxy.solver=scene.solver;proxy.generation=scene.generation;proxy.profile_latency_details=true
	# A separate collision-only fixture outside the beach; never edits authoritative fields.
	proxy.position=Vector3(10000,0,10000);root.add_child(proxy)
	scene.playing=true
	await create_timer(2.0).timeout
	for count in [1,4,16]:
		var chunks:=PackedInt32Array()
		for i in count:chunks.append(i)
		for repeat_index in 25:
			var policies:= ["baseline","serial","worker1","worker2","worker4"]
			if repeat_index%2==1:policies.reverse()
			for policy in policies:
				var heights:=PackedFloat32Array();heights.resize(count*1089)
				for index in heights.size():heights[index]=0.1+float(index)*0.000001+float(revision%2)*0.000001
				revision+=1;proxy.prepare_policy=policy
				var start:=Time.get_ticks_usec()
				proxy._apply_data(heights.to_byte_array(),chunks,revision,proxy.generation,0.0,PackedInt64Array(),start,start)
				var admission_end:=Time.get_ticks_usec()
				deadline=Time.get_ticks_msec()+10000
				while proxy.has_prepare_in_flight() and Time.get_ticks_msec()<deadline:await process_frame
				var end:=Time.get_ticks_usec()
				var valid: bool=not proxy.has_prepare_in_flight()
				for index in chunks.size():valid=valid and proxy.shapes[chunks[index]].shape.map_data.to_byte_array()==heights.slice(index*1089,(index+1)*1089).to_byte_array()
				check("byte_heights_and_complete",valid)
				samples.append({"chunks":count,"policy":policy,"repeat":repeat_index,
					"call_cpu_us":admission_end-start,"wall_us":end-start,"apply_cpu_ms":proxy.last_apply_ms,
					"submit_cpu_ms":proxy.last_replace_ms,"segments":proxy.last_prepare_segments.duplicate(true),
					"worker":proxy.last_prepare_worker.duplicate(true) if policy.begins_with("worker") else {},
					"background_tick":scene.completed_ticks})
				await process_frame
	scene.playing=false
	check("no_fixture_invalid_data",proxy.invalid_readbacks==0)
	check("all_fixture_groups_reclaimed",proxy.prepare_scheduler.group_id==-1 and proxy.prepare_scheduler.payload_bytes()==0)
	var configuration: Dictionary={"engine":Engine.get_version_info(),"adapter":RenderingServer.get_video_adapter_name(),
		"driver":ProjectSettings.get_setting("rendering/rendering_device/driver.windows"),"window":DisplayServer.window_get_size(),
		"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"physics_hz":Engine.physics_ticks_per_second,
		"waves":scene.wave_requests.size(),"erosion":scene.enable_erosion,"render_profile":scene.requested_render_profile_sha256}
	proxy.free()
	await scene.shutdown()
	check("main_released",scene.gpu_release_done)
	var passed:=true
	for row in checks:passed=passed and row.pass
	var file:=FileAccess.open(output.path_join("result.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass":passed,"checks":checks,"samples":samples,"configuration":configuration,
		"scope":"375 paired CPU preparation/real Jolt submissions under visible 1080p main load; separate far-away fixture, not actual command latency or formal A/B game cost"},"\t"));file.close()
	print("PREPARE_COST_COMPLETE ",passed);quit(0 if passed else 1)

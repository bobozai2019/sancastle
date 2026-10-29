extends SceneTree

var output := ""
var seconds := 60.0
var cycles := 6
var scene
var service
var rows := []
var checks := []
var probe_started := 0
var service_source := ""
var released_texture_result := -1

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
		if arg.begins_with("--seconds="): seconds = arg.trim_prefix("--seconds=").to_float()
		if arg.begins_with("--cycles="): cycles = arg.trim_prefix("--cycles=").to_int()
		if arg.begins_with("--service-source="): service_source = arg.trim_prefix("--service-source=")
	if output.is_empty() or FileAccess.file_exists(output.path_join("result.json")):
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	probe_started = Time.get_ticks_usec()
	var file := FileAccess.open(output.path_join("pid.txt"), FileAccess.WRITE)
	file.store_string(str(OS.get_process_id()))
	call_deferred("_run")

func check(name: String, ok: bool, details: Variant = null) -> void:
	checks.append({"name": name, "pass": ok, "details": details})
	print("LIFETIME_CHECK ", name, " ", ok)

func sample(label: String, frame_ms: float = 0.0, frames: int = 0) -> void:
	var row := {"label": label, "wall_s": (Time.get_ticks_usec() - probe_started) / 1000000.0,
		"static_bytes": OS.get_static_memory_usage(), "objects": Performance.get_monitor(Performance.OBJECT_COUNT),
		"resources": Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT), "nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"orphans": Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
		"video_bytes": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED),
		"texture_bytes": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED),
		"buffer_bytes": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_BUFFER_MEM_USED),
		"physics_objects": Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS),
		"mean_frame_ms": frame_ms / maxi(frames, 1), "frames": frames}
	if is_instance_valid(scene):
		row.merge({"key": scene.scene_key, "tick": scene.completed_ticks, "substeps": scene.last_substeps,
			"checkpoints": scene.checkpoints.size(), "waves": scene.wave_requests.size(),
			"gpu_prefix": scene.gpu_prefix.size(), "input_events": scene.input_events.size(),
			"gpu_events": scene.gpu_events.size(), "scheduler_terminal": scene.input_scheduler.terminal.size(),
			"sampling": scene.get_node("Interface/PerformancePanel").sampling})
	rows.append(row)
	print("LIFETIME_SAMPLE ", JSON.stringify(row))
	var file := FileAccess.open(output.path_join("progress.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"rows": rows, "checks": checks}, "\t"))

func _observe(duration: float, label: String) -> void:
	var start := Time.get_ticks_usec()
	var last := start
	var boundary := start
	var sum := 0.0
	var frames := 0
	while (Time.get_ticks_usec() - start) / 1000000.0 < duration:
		await process_frame
		var now := Time.get_ticks_usec()
		sum += (now - last) / 1000.0
		last = now
		frames += 1
		if now - boundary > 5000000:
			sample(label, sum, frames)
			boundary = now
			sum = 0.0
			frames = 0
	sample(label + "_end", sum, frames)

func _ready_scene() -> void:
	var deadline := Time.get_ticks_msec() + 90000
	while not scene.ready_for_ticks and scene.last_error.is_empty() and Time.get_ticks_msec() < deadline: await process_frame
	check(scene.scene_key + "_ready", scene.ready_for_ticks and scene.last_error.is_empty(), scene.last_error)
	# Keep the visible probe isolated from clicks/keys in its test window.
	root.gui_disable_input = true
	scene.set_process_input(false)
	scene.set_process_unhandled_input(false)
	scene.player_camera.set_process(false)
	scene.player_camera.set_process_input(false)
	scene.player_camera.set_process_unhandled_input(false)

func _texture_rids(owner) -> Array[RID]:
	var textures: Array[RID] = []
	for value in owner.solver.textures.values():
		if value is Array:
			for rid in value: textures.append(rid)
		else: textures.append(value)
	for rid in owner.stable_q.values(): textures.append(rid)
	textures.append(owner.solver.published_sand)
	textures.append(owner.solver.published_water)
	textures.append(owner.local_front_field.texture)
	textures.append(owner.local_front_field.x_texture)
	textures.append(owner.sediment_coupler.dirty_max_texture)
	textures.append(owner.sand_audit.output)
	for rid in owner.foam_field.textures + owner.foam_field.bed_textures: textures.append(rid)
	return textures

func _check_texture_release(textures: Array[RID]) -> void:
	var rd := RenderingServer.get_rendering_device()
	var live := 0
	for rid in textures:
		if rd.texture_is_valid(rid): live += 1
	call_deferred("_texture_release_received", live)

func _texture_release_received(live: int) -> void:
	released_texture_result = live

func _run() -> void:
	root.size = Vector2i(1280, 720)
	service = root.get_node("BeachScenes")
	if not service_source.is_empty():
		var baseline_script := GDScript.new()
		baseline_script.source_code = FileAccess.get_file_as_string(service_source)
		if baseline_script.reload() != OK:
			quit(1)
			return
		service.set_script(baseline_script)
	sample("empty")
	var packed := load("res://scenes/main.tscn") as PackedScene
	if packed == null:
		check("main_load", false)
		quit(1)
		return
	scene = packed.instantiate()
	packed = null
	scene.playing = false
	root.add_child(scene)
	current_scene = scene
	await _ready_scene()
	if not scene.ready_for_ticks:
		quit(1)
		return
	await _observe(2.0, "warm_initial")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("main_ready.png"))
	scene.playing = true
	await _observe(seconds, "running_sampled")
	scene.get_node("Interface/PerformancePanel/Margin/Rows/Header/Sampling").button_pressed = false
	await _observe(10.0, "running_unsampled")
	scene.playing = false
	for index in cycles:
		var key: String = ["test1_capture", "test1_backwash", "main"][index % 3]
		var old_id: int = scene.get_instance_id()
		var old_textures := _texture_rids(scene)
		var old_solver = scene.solver
		var old_proxy = scene.collision_proxy
		check("admitted_" + str(index), service.request_switch(key))
		var deadline := Time.get_ticks_msec() + 180000
		while service.busy and Time.get_ticks_msec() < deadline: await process_frame
		scene = service.active_scene
		scene.set_process_input(false)
		scene.set_process_unhandled_input(false)
		scene.player_camera.set_process(false)
		scene.player_camera.set_process_input(false)
		scene.player_camera.set_process_unhandled_input(false)
		check("switched_" + str(index), not service.busy and scene.scene_key == key and scene.ready_for_ticks and service.last_error.is_empty(), service.last_error)
		check("old_node_freed_" + str(index), not is_instance_id_valid(old_id))
		check("old_solver_released_" + str(index), old_solver.rd == null and old_solver.textures.is_empty())
		check("old_proxy_freed_" + str(index), not is_instance_valid(old_proxy))
		released_texture_result = -1
		RenderingServer.call_on_render_thread(_check_texture_release.bind(old_textures))
		while released_texture_result < 0: await process_frame
		check("old_gpu_textures_invalid_" + str(index), released_texture_result == 0, {"captured": old_textures.size(), "still_valid": released_texture_result})
		old_solver = null
		old_proxy = null
		scene.playing = false
		await _observe(3.0, "switch_" + str(index))
		# A fixed amount of live work distinguishes a paused new scene from one
		# whose solver/collision actually runs after old resources are released.
		scene.playing = true
		await _observe(5.0, "target_running_" + str(index))
		scene.playing = false
	await scene.shutdown()
	check("final_gpu_release", scene.gpu_release_done)
	scene.queue_free()
	scene = null
	service.active_scene = null
	await _observe(3.0, "released_all")
	var pass_all := true
	for item in checks: pass_all = pass_all and item.pass
	var file := FileAccess.open(output.path_join("result.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass": pass_all, "rows": rows, "checks": checks, "service_source": service_source,
		"release_records": service.release_records if "release_records" in service else [],
		"engine": Engine.get_version_info(), "adapter": RenderingServer.get_video_adapter_name(),
		"vsync": DisplayServer.window_get_vsync_mode(), "window": [1280, 720]}, "\t"))
	quit(0 if pass_all else 1)

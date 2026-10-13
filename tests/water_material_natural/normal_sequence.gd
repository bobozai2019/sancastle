extends SceneTree

var output := "D:/godot/project/sandcastle/test_output/water_material_natural/t01_sequence"
var preview: Node3D

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	call_deferred("_run")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	preview = load("res://scenes/water_material_natural_candidate/texture_layers.tscn").instantiate()
	preview.replay_target_tick = 360
	root.add_child(preview)
	var frames := []
	var deadline := Time.get_ticks_msec() + 180000
	for tick in range(360, 511):
		preview.replay_target_tick = tick
		preview.replay_ready = false
		while not preview.replay_ready:
			await process_frame
			if not preview.last_error.is_empty() or Time.get_ticks_msec() > deadline:
				push_error("sequence failure " + preview.last_error)
				quit(1)
				return
		if preview.completed_ticks != tick or not is_equal_approx(preview.visual_time_s, float(tick)/30.0):
			push_error("sequence completed-state clock mismatch")
			quit(1)
			return
		preview.set_fixture_camera(&"close")
		for mode in [1,2]:
			preview.water_material.set_shader_parameter("natural_normal_mode", mode)
			preview.water_material.set_shader_parameter("use_detail_normals", true)
			for i in range(2): await process_frame
			await RenderingServer.frame_post_draw
			var path := output + "/mode%d_%04d.png" % [mode, tick-360]
			if root.get_texture().get_image().save_png(path) != OK:
				quit(1)
				return
			frames.append({"tick":tick,"time_s":preview.visual_time_s,"mode":mode,"path":path,
				"sha256":FileAccess.get_sha256(path),"revision":preview.solver.state_revision,
				"generation":preview.generation,"wall_us":Time.get_ticks_usec()})
	var file := FileAccess.open(output + "/manifest.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"frames":frames,"camera":"close","viewport_px":root.size,
		"timebase":"completed_tick / 30; offline paired captures, not measured realtime throughput",
		"candidate_sha256":FileAccess.get_sha256(preview.candidate_profile_path),
		"shader_sha256":FileAccess.get_sha256(preview.water_material.shader.resource_path)},"\t"))
	file.close()
	print("PASS: paired 151 completed ticks / 5 simulated seconds")
	quit(0)

extends SceneTree

var preview: Node3D
var output := ""
var frames: Array[Dictionary] = []
var commands: Array[Dictionary] = []
var started := 0
var previous := 0
var next_command := 0
var observed := {}
var finished := false
var input_mode := "fixed_tick"
var start_tick := 0

func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			output = arg.trim_prefix("--output=")
		elif arg.begins_with("--input-mode="):
			input_mode = arg.trim_prefix("--input-mode=")
	call_deferred("_run")

func _run() -> void:
	if output.is_empty():
		quit(1)
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	root.size = Vector2i(1920, 1080)
	preview = load("res://tests/edit_validation/edit_baseline_trace.tscn").instantiate()
	preview.profile_tool_latency = true
	preview.trace_output = output
	root.add_child(preview)
	var timeout := Time.get_ticks_usec() + 120000000
	while not preview.ready_for_ticks:
		if not preview.last_error.is_empty() or Time.get_ticks_usec() > timeout:
			_finish("initialization failed: " + preview.last_error)
			return
		await process_frame
	started = Time.get_ticks_usec()
	start_tick = 0
	previous = started
	while Time.get_ticks_usec() - started < 20000000:
		await process_frame
		var now := Time.get_ticks_usec()
		frames.append({"us": now, "frame_ms": (now - previous) / 1000.0,
			"tick": preview.completed_ticks})
		previous = now
		if not preview.last_error.is_empty():
			_finish(preview.last_error)
			return
		var due: bool = preview.completed_ticks >= next_command * 24 + start_tick if input_mode == "fixed_tick" else now - started >= next_command * 800000
		if next_command < 20 and due:
			var index := next_command
			var point := Vector3(-2.0 + index * 0.04, 0.0, 1.0)
			var kind := &"remove_sand" if index % 2 == 0 else &"place_sand"
			# Cursor motion is recorded; it does not imply a warmed prefetch.
			if index % 2 == 0:
				Input.warp_mouse(preview.overview_camera.unproject_position(point))
				preview._update_brush_indicator()
			var submit := Time.get_ticks_usec()
			var error: StringName = _submit_fixed(kind, point, start_tick + 2 + index * 24) if input_mode == "fixed_tick" else preview._submit_brush(kind, 0.01, point, point, &"circle")
			var id: int = preview.command_id
			preview.event("submit", [id], {"error": String(error), "index": index})
			commands.append({"command_id": id, "submit_us": submit, "kind": String(kind),
				"position_m": [point.x, point.y, point.z], "amount_m3": 0.01, "error": String(error),
				"submit_completed_tick": preview.completed_ticks, "command": preview.command_queue.pending.back().duplicate(true) if not preview.command_queue.pending.is_empty() else {}})
			next_command += 1
		await RenderingServer.frame_post_draw
		for command in commands:
			var id: int = command.command_id
			if not observed.has(id) and preview.tool_revision_by_command_id.has(id):
				observed[id] = true
				preview.event("first_post_draw_after_revision", [id], preview.tool_revision_by_command_id[id])
	_finish("")

func _submit_fixed(kind: StringName, point: Vector3, target: int) -> StringName:
	# Same queue and patch path, with an explicit future tick for replay fidelity.
	preview.command_id += 1
	var command := {"domain_id": preview.shadow_domain.domain_id,
		"generation": preview.shadow_domain.generation, "sim_tick": target,
		"command_id": preview.command_id, "kind": kind, "shape": &"circle",
		"transform": {"position_m": point}, "radius_m": 0.38,
		"strength": 1.0, "amount_m3": 0.01, "seed": preview.command_id}
	var error: StringName = preview.command_queue.submit(command)
	if error.is_empty():
		preview.last_tool_submit_usec = Time.get_ticks_usec()
	return error

func _write(name: String, value: Variant) -> void:
	var file := FileAccess.open(output.path_join(name), FileAccess.WRITE)
	file.store_string(JSON.stringify(value, "\t"))

func _finish(error: String) -> void:
	if finished:
		return
	finished = true
	_write("trace.json", preview.take_events())
	_write("frames.json", frames)
	_write("commands.json", commands)
	_write("runtime.json", {"error": error, "engine": Engine.get_version_info(),
		"adapter": RenderingServer.get_video_adapter_name(), "viewport": [root.size.x, root.size.y],
		"vsync": DisplayServer.window_get_vsync_mode(), "start_us": started,
		"input_mode": input_mode, "start_tick": start_tick,
		"end_us": Time.get_ticks_usec(), "completed_ticks": preview.completed_ticks,
		"profile_sha256": preview.requested_render_profile_sha256,
		"effective_profile": preview.effective_render_profile,
		"effective_profile_sha256": preview.effective_render_profile_sha256,
		"prefetch_hits": preview.sand_prefetch_hits, "sand_only_syncs": preview.sand_only_syncs,
		"observed_commands": observed.size(), "cost_acceptance": "diagnostic_only"})
	preview.queue_free()
	for i in 4:
		await process_frame
	print("TRACE_COMPLETE error=" + error)
	quit(0 if error.is_empty() else 1)

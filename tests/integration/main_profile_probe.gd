extends "res://tests/water_material_natural/rdc_main_smoke.gd"

func _frames(count: int = 8) -> void:
	for i in count:
		await process_frame
		await RenderingServer.frame_post_draw

func _settle() -> void:
	var deadline := Time.get_ticks_msec() + 30000
	while preview.busy or preview.input_running or preview.collision_proxy.staging_texture.is_valid() or not preview.collision_proxy.pending_revisions.is_empty():
		await process_frame
		if Time.get_ticks_msec() > deadline:
			_check("settle_timeout", false)
			break

func _run() -> void:
	root.size = Vector2i(1280, 720)
	preview = load("res://scenes/main.tscn").instantiate()
	preview.playing = false
	root.add_child(preview)
	var deadline := Time.get_ticks_msec() + 180000
	while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_msec() < deadline: await process_frame
	_check("main_ready", preview.ready_for_ticks and preview.last_error.is_empty(), preview.last_error)
	if not preview.ready_for_ticks: _finish(); quit(1); return
	var panel = preview.get_node("Interface/PerformancePanel")
	var toggle: CheckButton = panel.sample_toggle
	await _frames()
	_check("sampling_enabled_on_render_thread", panel.sampling and preview.solver.profile_passes and preview.collision_proxy.profile_passes)
	await _ticks(4)
	await _settle()
	await create_timer(0.65).timeout
	var core_positive := true
	for key in ["boundary", "water", "sediment", "material", "foam", "audit"]:
		core_positive = core_positive and panel.last_stages.has(key) and float(panel.last_stages.get(key, {}).get("ms", 0.0)) > 0.0
	_check("real_gpu_stage_samples", core_positive and panel.accepted_frames > 0, panel.last_stages.duplicate(true))
	_check("live_frame_metrics", panel.snapshot.get("fps", 0.0) > 0.0 and panel.snapshot.get("frame_ms", 0.0) > 0.0, panel.snapshot.duplicate(true))
	var held_tick: int = preview.completed_ticks
	await create_timer(0.65).timeout
	_check("paused_display_keeps_simulation_frozen", preview.completed_ticks == held_tick and "暂停" in panel.state.text and "上次" in panel.stage_values.text)
	preview.playing = true
	await create_timer(1.2).timeout
	preview.playing = false
	await _settle()
	_check("realtime_tick_rate", preview.completed_ticks > held_tick and panel.snapshot.ticks_per_s > 0.0, panel.snapshot.duplicate(true))
	await create_timer(0.6).timeout
	# A click on the information panel must not submit a world edit.
	var before_events: int = preview.input_events.size()
	var click := InputEventMouseButton.new()
	click.position = panel.get_global_rect().position + Vector2(8, 80)
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	Input.parse_input_event(click)
	await _frames(2)
	click.pressed = false
	Input.parse_input_event(click)
	await _frames(2)
	_check("profile_panel_blocks_world_edit", preview.input_events.size() == before_events)
	var path := output.path_join("profile_checkpoint.bin")
	var save_error: StringName = await preview.save_gpu_checkpoint(path)
	_check("save_with_profiling", save_error.is_empty(), String(save_error))
	await _ticks(2)
	await _settle()
	var sampled := await _snapshot()
	var previous_generation: int = preview.generation
	var restore_error: StringName = await preview.restore_gpu_checkpoint(path)
	await _frames(1)
	_check("restore_resets_timestamp_generation", restore_error.is_empty() and preview.generation != previous_generation and panel.sample_generation == preview.generation and panel.last_stages.is_empty(), {"error":String(restore_error),"old_generation":previous_generation,"new_generation":panel.sample_generation,"stages":panel.last_stages.duplicate(true)})
	toggle.button_pressed = false
	await _frames()
	_check("sampling_off_restores_flags", not panel.sampling and not preview.solver.profile_passes and not preview.collision_proxy.profile_passes)
	var accepted: int = panel.accepted_frames
	await _ticks(2)
	await _settle()
	var unsampled := await _snapshot()
	var exact := true
	for field in FIELDS: exact = exact and sampled[field] == unsampled[field]
	_check("profiling_does_not_change_10_fields", exact)
	_check("off_does_not_collect", panel.accepted_frames == accepted and "采样关闭" in panel.render_time.text)
	toggle.button_pressed = true
	await _frames()
	preview.hide_hud = true
	preview._update_status()
	await _frames()
	_check("f6_hides_and_disables_sampling", not panel.visible and not panel.sampling and not preview.solver.profile_passes and not preview.collision_proxy.profile_passes)
	preview.hide_hud = false
	preview._update_status()
	await _frames()
	await _ticks(2)
	await _settle()
	await create_timer(0.65).timeout
	_check("show_resumes_current_generation_samples", panel.visible and panel.sampling and panel.accepted_frames > accepted and panel.last_stages.has("foam"))
	for size in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = size
		await _frames()
		var rect: Rect2 = panel.get_global_rect()
		_check("layout_%dx%d" % [size.x,size.y], root.get_visible_rect().encloses(rect) and not rect.intersects(preview.get_node("Interface/EditPanel").get_global_rect()) and not rect.intersects(preview.status_label.get_global_rect()), rect)
		root.get_texture().get_image().save_png(output.path_join("profile_%dx%d.png" % [size.x,size.y]))
	var effective := {"engine":Engine.get_version_info(),"adapter":RenderingServer.get_video_adapter_name(),"driver":ProjectSettings.get_setting("rendering/rendering_device/driver.windows"),"vsync":DisplayServer.window_get_vsync_mode(),"snapshot":panel.snapshot.duplicate(true),"accepted_frames":panel.accepted_frames,"timestamp_frame":panel.last_capture_frame}
	var record := FileAccess.open(output.path_join("profile_snapshot.json"), FileAccess.WRITE)
	record.store_string(JSON.stringify(effective,"\t")); record.close()
	await preview.shutdown()
	_check("clean_shutdown", preview.gpu_release_done and preview.last_error.is_empty(), preview.last_error)
	_finish()
	var passed := true
	for row in checks: passed = passed and row.pass
	quit(0 if passed else 1)

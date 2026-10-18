extends SceneTree

# G0 observes the existing path. It does not enable the new protocol.
var preview
var output := ""
var checks := []
var failed := false

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	call_deferred("_run")

func check(label: String, value: bool) -> void:
	checks.append({"name":label,"pass":value})
	failed = failed or not value
	print("PIPELINE_BASELINE ", label, " ", value)

func _run() -> void:
	preview = load("res://scenes/main.tscn").instantiate()
	preview.playing = false
	root.add_child(preview)
	var deadline := Time.get_ticks_msec() + 60000
	while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_msec() < deadline:
		await process_frame
	check("main_ready", preview.ready_for_ticks and preview.last_error.is_empty())
	var info := {"engine":Engine.get_version_info(),"adapter":RenderingServer.get_video_adapter_name(),
		"driver":RenderingServer.get_current_rendering_driver_name(),"window_size":DisplayServer.window_get_size(),
		"vsync":DisplayServer.window_get_vsync_mode(),"headless":DisplayServer.get_name()=="headless",
		"runtime_script":preview.get_script().resource_path,"batch_limit":preview.edit_frame_batch_limit,
		"old_frame_pipeline":preview.edit_frame_pipeline_enabled,"erosion":preview.enable_erosion,
		"profile":preview._runtime_configuration_signature()}
	check("visible_window", not info.headless and info.window_size.x > 0)
	if not failed:
		preview.playing = true
		while preview.completed_ticks < 3 and preview.last_error.is_empty() and Time.get_ticks_msec() < deadline:
			await process_frame
		preview.playing = false
		while preview.tick_pending and preview.last_error.is_empty() and Time.get_ticks_msec() < deadline:
			await process_frame
		check("existing_water_ticks", preview.completed_ticks >= 3 and preview.last_error.is_empty())
	info.completed_ticks = preview.completed_ticks
	info.last_error = preview.last_error
	await preview.shutdown()
	check("release", preview.gpu_release_done and preview.solver.rd == null)
	preview.queue_free()
	await process_frame
	if not output.is_empty():
		var file := FileAccess.open(output, FileAccess.WRITE)
		if file != null: file.store_string(JSON.stringify({"pass":not failed,"checks":checks,"runtime":info},"\t"))
	quit(1 if failed else 0)

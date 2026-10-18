extends SceneTree

# Run a matching Godot editor binary against the actual release PCK, with a
# visible window and normal defaults (release templates disable script overrides):
# godot --main-pack <release/sandcastle.pck> --script res://tests/integration/export_startup_probe.gd -- --output=<absolute directory>
var output := "user://export_startup_probe"
var failed := false
var checks := []

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	call_deferred("_run")

func check(label: String, passed: bool) -> void:
	checks.append({"name": label, "pass": passed})
	failed = failed or not passed
	print("EXPORT_STARTUP ", label, " ", passed)

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	var preview = load(ProjectSettings.get_setting("application/run/main_scene")).instantiate()
	root.add_child(preview)
	current_scene = preview
	var deadline := Time.get_ticks_msec() + 90000
	while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_msec() < deadline:
		await process_frame
	check("normal_defaults_ready", preview.ready_for_ticks and preview.last_error.is_empty())
	var evidence := {"error": preview.last_error, "engine": Engine.get_version_info(), "adapter": RenderingServer.get_video_adapter_name()}
	if preview.ready_for_ticks:
		check("gpu_pipeline_ready", preview.async_backend_ready)
		check("water_material_bound", preview.water_material != null and preview.water_material.get_shader_parameter("use_async_clock") == true)
		var start_tick: int = preview.completed_ticks
		deadline = Time.get_ticks_msec() + 30000
		while preview.completed_ticks < start_tick + 30 and preview.last_error.is_empty() and Time.get_ticks_msec() < deadline:
			await process_frame
		check("water_simulation_advances", preview.completed_ticks >= start_tick + 30)
		check("runtime_stays_healthy", preview.last_error.is_empty())
		evidence["completed_ticks"] = preview.completed_ticks
		evidence["visual_time_s"] = preview.visual_time_s
		evidence["profile"] = preview.effective_compilation
		await RenderingServer.frame_post_draw
		check("screenshot_saved", root.get_texture().get_image().save_png(output.path_join("main.png")) == OK)
	await preview.shutdown()
	check("gpu_resources_released", preview.gpu_release_done)
	preview.queue_free()
	await process_frame
	var file := FileAccess.open(output.path_join("report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass": not failed, "checks": checks, "evidence": evidence}, "\t"))
	file.close()
	quit(1 if failed else 0)

extends SceneTree

# Run from a directory OUTSIDE the project so loose sources cannot hide missing
# PCK files. Use a matching editor binary; release templates disable --script:
# godot --main-pack <absolute PCK> --script <absolute probe> -- --output=<absolute directory>
const Presentation = preload("res://scripts/simulation/unified_edit/presentation.gd")
const Layout = preload("res://scripts/simulation/unified_edit/layout.gd")
const Codec = preload("res://scripts/simulation/unified_edit/checkpoint_codec.gd")
var output := "user://export_startup_probe"
var scene_key := "main"
var smoke := false
var failed := false
var checks: Array = []
var preview
var evidence: Dictionary = {}

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
		if arg.begins_with("--scene="): scene_key = arg.trim_prefix("--scene=")
		if arg == "--smoke": smoke = true
	call_deferred("_run")

func check(label: String, passed: bool) -> void:
	checks.append({"name": label, "pass": passed})
	failed = failed or not passed
	print("EXPORT_STARTUP ", label, " ", passed)

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	var path: String = ProjectSettings.get_setting("application/run/main_scene") if scene_key == "main" else "res://scenes/playable/" + scene_key + ".tscn"
	preview = load(path).instantiate()
	root.add_child(preview)
	current_scene = preview
	var deadline := Time.get_ticks_msec() + 90000
	while (not preview.ready_for_ticks or preview._booting) and preview.last_error.is_empty() and Time.get_ticks_msec() < deadline:
		await process_frame
	check("normal_defaults_ready", preview.ready_for_ticks and preview.last_error.is_empty())
	evidence = {"error": preview.last_error, "engine": Engine.get_version_info(), "adapter": RenderingServer.get_video_adapter_name(), "scene": path, "main_pack": ProjectSettings.get_setting("application/run/main_scene")}
	if preview.ready_for_ticks:
		check("text_resources_preserved", ProjectSettings.get_setting("editor/export/convert_text_resources_to_binary") == false)
		for profile in ["dig_v1", "dig_sweep_v1", "fill_v1", "fill_sweep_v1", "castle_v1", "wall_v1", "shovel_v1"]:
			check(profile + "_water_policies_preserved", preview.configuration.profiles[profile].allowed_features.water_policy == [0, 1, 2, 3])
		var owner = preview.runtime.current
		check("gpu_pipeline_ready", owner != null and preview.runtime.ready_for_input())
		var bound: bool = not preview.material_bindings.is_empty()
		for binding in preview.material_bindings:
			for parameter in binding.parameters:
				var texture: Variant = binding.material.get_shader_parameter(parameter)
				bound = bound and texture is Texture2DRD and texture.texture_rd_rid == owner.views.textures[binding.parameters[parameter]]
		check("water_and_sand_materials_bound", bound)
		var start_tick: int = owner.completed_tick
		deadline = Time.get_ticks_msec() + 30000
		while owner.completed_tick < start_tick + 30 and preview.last_error.is_empty() and Time.get_ticks_msec() < deadline:
			await process_frame
		check("water_simulation_advances", owner.completed_tick >= start_tick + 30)
		preview.playing = false
		await _idle()
		evidence["completed_ticks"] = owner.completed_tick
		evidence["visual_time_s"] = owner.advanced_time_s
		evidence["configuration"] = preview.configuration
		await _capture("main")
		var baseline := PackedByteArray() if smoke else await _sand_snapshot("before")
		for tool in [&"place_sand", &"remove_sand"]:
			preview.panel.get_node("Margin/Controls/Tools/" + ("Fill" if tool == &"place_sand" else "Dig")).pressed.emit()
			check(String(tool) + "_button_selects_tool", preview.selected_sand_tool == tool)
			var count: int = preview.input.terminal.size()
			var admission: Dictionary = preview.input.begin(tool, Vector2(3, 0), {}, 0.1, preview.water_policy, preview.signed_speed_m_s)
			evidence[String(tool) + "_admission"] = admission
			check(String(tool) + "_admitted", admission.accepted)
			preview.input.finish()
			await _idle()
			var applied := false
			var volume := 0.0
			for index in range(count, preview.input.terminal.size()):
				var row: Dictionary = preview.input.terminal[index]
				if row.outcome == Layout.Outcome.APPLIED:
					volume += float(row.get("added_m3" if tool == &"place_sand" else "removed_m3", 0.0))
					applied = true
			check(String(tool) + "_gpu_applied", applied and volume > 0.0)
			evidence[String(tool) + "_volume_m3"] = volume
			if not smoke:
				var actual := await _sand_snapshot(String(tool))
				check(String(tool) + "_changes_sand_bytes", not actual.is_empty() and actual != baseline)
				baseline = actual
			await _capture(String(tool))
		evidence["tool_results"] = preview.input.terminal.duplicate(true)
		check("runtime_stays_healthy", preview.last_error.is_empty() and owner.fault_reason().is_empty())
		# Keep hash rejection active in exports as well as source-tree runs.
		var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(preview.presentation_manifest))
		document.metadata.seed.sha256 = "0".repeat(64)
		var invalid := output.path_join("invalid_manifest.json")
		FileAccess.open(invalid, FileAccess.WRITE).store_string(JSON.stringify(document))
		check("changed_seed_rejected", Presentation.read(invalid).error == &"presentation_artifact_changed")
	await preview.shutdown()
	check("gpu_resources_released", preview.unified_release_complete())
	var service = root.get_node("BeachScenes")
	if service.active_scene == preview: service.active_scene = null
	current_scene = null
	root.remove_child(preview)
	preview.free()
	await process_frame
	var file := FileAccess.open(output.path_join("report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass": not failed, "checks": checks, "evidence": evidence}, "\t"))
	file.close()
	quit(1 if failed else 0)

func _idle() -> void:
	var owner = preview.runtime.current
	var deadline := Time.get_ticks_msec() + 30000
	while (owner.pending_count() != 0 or owner.active_count() != 0 or not preview.input.waiting.is_empty()) and Time.get_ticks_msec() < deadline:
		await process_frame
	check("queue_idle_" + str(checks.size()), owner.pending_count() == 0 and owner.active_count() == 0 and preview.input.waiting.is_empty())

func _sand_snapshot(label: String) -> PackedByteArray:
	var path := output.path_join(label + ".sandue")
	check(label + "_checkpoint_saved", (await preview.save_gpu_checkpoint(path)).is_empty())
	await process_frame
	await process_frame
	var saved := Codec.load(path, preview.configuration)
	check(label + "_checkpoint_valid", saved.error.is_empty())
	return saved.checkpoint.native.fields.sand if saved.error.is_empty() else PackedByteArray()

func _capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	check(label + "_screenshot_saved", root.get_texture().get_image().save_png(output.path_join(label + ".png")) == OK)

extends SceneTree

# Run through validate_export.py with its explicit isolated --path so loose
# project sources cannot hide missing PCK files. Use a matching editor binary; release templates disable --script:
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
	check("pack_isolated_from_loose_sources", not FileAccess.file_exists("res://tools/validate_export.py"))
	var path: String = ProjectSettings.get_setting("application/run/main_scene") if scene_key == "main" else "res://scenes/playable/" + scene_key + ".tscn"
	preview = load(path).instantiate()
	root.add_child(preview)
	current_scene = preview
	var deadline := Time.get_ticks_msec() + 90000
	while (not preview.ready_for_ticks or preview._booting) and preview.last_error.is_empty() and Time.get_ticks_msec() < deadline:
		await process_frame
	check("normal_defaults_ready", preview.ready_for_ticks and preview.last_error.is_empty())
	# Let the parameter service publish the boot-to-ready busy transition before
	# asserting native control availability (the first edit also emits changed).
	await process_frame
	evidence = {"error": preview.last_error, "engine": Engine.get_version_info(), "adapter": RenderingServer.get_video_adapter_name(), "scene": path, "main_pack": ProjectSettings.get_setting("application/run/main_scene")}
	var presentation := Presentation.read(preview.presentation_manifest)
	if presentation.error.is_empty():
		var data: Dictionary = presentation.metadata
		var dependencies := Presentation.dependencies(PackedStringArray([path, preview.presentation_manifest, data.scene.path, data.seed.path]))
		check("presentation_dependencies_complete", dependencies.error.is_empty())
		if not dependencies.error.is_empty(): evidence["dependency_failure"] = dependencies
	if preview.ready_for_ticks:
		var water: ShaderMaterial=preview.get_node("GpuWaterSurface").material_override
		var detail: Texture2D=water.get_shader_parameter("foam_detail_texture")
		check("foam_formal_mode",water.get_shader_parameter("foam_detail_mode")==1)
		check("foam_static_texture",detail!=null and detail.resource_path=="res://assets/water_foam/foam_detail.png")
		check("foam_raw_texture_identity",FileAccess.get_sha256("res://assets/water_foam/foam_detail.png")=="05c18a800db479f3e2a2568867051d29a3438d2cd7225830e000e8598935e50b")
		if detail!=null:
			var image:=detail.get_image()
			check("foam_imported_mips_budget",image!=null and image.get_width()==512 and image.get_mipmap_count()==9 and image.get_data_size()<=2097152)
			if image!=null:evidence.foam={"path":detail.resource_path,"bytes":image.get_data_size(),"mips":image.get_mipmap_count(),"format":image.get_format()}
		check("foam_debug_disabled",water.get_shader_parameter("foam_flow_debug")==false)
		for item in [["visual_foam_detail_scale_per_m","foam_detail_scale_per_m",1.2],["visual_foam_hole_strength","foam_hole_strength",0.8],["visual_foam_flow_cycle_s","foam_flow_cycle_s",3.5]]:
			var row=root.get_node("Parameters").get_node_or_null("water/Margin/Rows/Scroll/Fields/"+item[0])
			check("foam_ui_row_"+item[0],row!=null)
			if row!=null:
				var control: SpinBox=row.get_node("Line/Value")
				var previous: float=control.value
				var expected: float=4.0 if item[0]=="visual_foam_flow_cycle_s" else 1.0
				check("foam_ui_default_"+item[0],is_equal_approx(previous,expected))
				check("foam_ui_enabled_"+item[0],control.editable)
				control.value=item[2]
				check("foam_ui_shader_consumes_"+item[0],is_equal_approx(float(water.get_shader_parameter(item[1])),float(item[2])))
				control.value=previous
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
		check("props_held_before_fixed_ticks",(await preview._props_hold(true,&"user")).is_empty())
		# Show the final foam resource under actual accumulated wave history.
		while owner.completed_tick<720 and preview.last_error.is_empty():
			var tick_error: StringName=preview.runtime.request_tick(1.0/30.0)
			check("foam_tick_admitted_"+str(owner.completed_tick),tick_error.is_empty())
			if not tick_error.is_empty():break
			await _idle()
		check("foam_completed_history",owner.completed_tick>=720)
		evidence["completed_ticks"] = owner.completed_tick
		evidence["visual_time_s"] = owner.advanced_time_s
		evidence["props_error"] = String(preview.floating_props.last_error) if preview.floating_props!=null else ""
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

extends "res://tests/water_material_natural/rdc_main_smoke.gd"

class CountingSolver:
	extends SandcastleGpuShallowSolver
	var scans := 0
	var steps := []
	func substeps_from_cfl(delta: float, data: PackedByteArray) -> int:
		scans += 1
		return super.substeps_from_cfl(delta, data)
	func dispatch_substep(delta: float, _boundary: bool = false) -> bool:
		steps.append(delta)
		state_revision += 1
		return true

func _frames(count: int = 8) -> void:
	for i in count:
		await process_frame
		await RenderingServer.frame_post_draw

func _cfl_contract() -> void:
	var data := PackedFloat32Array([0.1, 1.0, 6.0, 2.0]).to_byte_array()
	var original := CountingSolver.new()
	original.grid_size = 16; original.cell_size_m = 0.125
	var reused := CountingSolver.new()
	reused.grid_size = 16; reused.cell_size_m = 0.125
	var count := reused.substeps_from_cfl(1.0/30.0, data)
	var ok := original.dispatch_tick_with_cfl(1.0/30.0, data, 0)
	ok = reused.dispatch_tick_validated(1.0/30.0, count, 0) and ok
	_check("cfl_reuse_same_substeps_and_delta", ok and original.steps == reused.steps and original.state_revision == reused.state_revision)
	_check("validated_dispatch_does_not_rescan", reused.scans == 1)
	var held := reused.state_revision
	_check("cfl_bad_revision_rejected", not reused.dispatch_tick_validated(1.0/30.0, count, held-1))
	var invalid := true
	for delta in [0.0, -1.0, NAN, INF]:
		invalid = invalid and not reused.dispatch_tick_validated(delta, count, held)
	_check("cfl_invalid_delta_rejected", invalid)
	_check("cfl_zero_and_overload_rejected", not reused.dispatch_tick_validated(1.0/30.0, 0, held) and not reused.dispatch_tick_validated(1.0/30.0, reused.MAX_SUBSTEPS+1, held) and reused.state_revision == held and reused.overload_events == 1)
	_check("cfl_invalid_tiles_still_rejected", reused.substeps_from_cfl(1.0/30.0, PackedByteArray()) == -1 and reused.substeps_from_cfl(1.0/30.0, PackedFloat32Array([NAN,0.0,0.0,0.0]).to_byte_array()) == -1)
	var locked := preload("res://scripts/simulation/edit_validation/gpu_water_editor.gd").new()
	locked.receipt_pending = true
	_check("validated_dispatch_preserves_receipt_lock", not locked.dispatch_tick_validated(1.0/30.0,1,0))

var paired_tiles := PackedByteArray()
var paired_revision := -1
var paired_done := false
var paired_ok := false

func _paired_tiles_ready(data: PackedByteArray, revision: int) -> void:
	paired_tiles = data
	paired_revision = revision

func _dispatch_paired_cfl(reuse: bool) -> void:
	var post := Callable(preview, "_dispatch_coupled_substep")
	if reuse:
		var substeps: int = preview.solver.substeps_from_cfl(1.0/30.0, paired_tiles)
		paired_ok = preview.solver.dispatch_tick_validated(1.0/30.0, substeps, paired_revision, post)
	else:
		paired_ok = preview.solver.dispatch_tick_with_cfl(1.0/30.0, paired_tiles, paired_revision, post)
	call_deferred("_paired_complete")

func _paired_complete() -> void:
	paired_done = true

func _paired_cfl_contract() -> void:
	var path := output.path_join("cfl_pair_checkpoint.bin")
	var saved: StringName = await preview.save_gpu_checkpoint(path)
	_check("cfl_pair_saved", saved.is_empty(),String(saved))
	if not saved.is_empty(): return
	var results := []
	for reuse in [false,true]:
		paired_tiles.clear(); paired_revision = -1
		RenderingServer.call_on_render_thread(func() -> void:
			preview.solver.request_cfl_tiles(_paired_tiles_ready))
		var deadline := Time.get_ticks_msec()+30000
		while paired_revision<0 and Time.get_ticks_msec()<deadline: await process_frame
		_check("cfl_pair_tiles_"+str(reuse), paired_revision==preview.solver.state_revision and not paired_tiles.is_empty())
		paired_done = false; paired_ok = false
		RenderingServer.call_on_render_thread(_dispatch_paired_cfl.bind(reuse))
		while not paired_done and Time.get_ticks_msec()<deadline: await process_frame
		_check("cfl_pair_dispatch_"+str(reuse), paired_done and paired_ok)
		results.append(await _snapshot())
		var restored: StringName = await preview.restore_gpu_checkpoint(path)
		_check("cfl_pair_restore_"+str(reuse), restored.is_empty(),String(restored))
	var equal := true
	for field in FIELDS: equal = equal and results[0][field]==results[1][field]
	_check("real_gpu_cfl_paths_preserve_all_10_fields", equal)

func _profile_contract() -> void:
	preview.refresh_effective_render_profile()
	var revision: int = preview.effective_profile_revision
	await _ticks(4)
	_check("stable_ticks_do_not_reseal_profile", preview.effective_profile_revision == revision)
	var time: float = float(preview.completed_ticks)/30.0
	_check("cached_profiles_keep_completed_clock", preview.visual_time_s == time and preview.effective_render_profile.visual_time_s == time and preview.effective_candidate.visual_time_s == time and preview.effective_style.visual_time_s == time)
	var hash: String = preview.effective_render_profile_sha256
	_check("lazy_digest_matches_current_complete_profile", hash == JSON.stringify(preview.effective_render_profile).sha256_text() and not preview.effective_profile_digest_dirty and preview.effective_render_profile.has("test1_foam_splats"))
	preview.invalidate_effective_render_profile()
	await _ticks(1)
	_check("explicit_invalidation_revalidates_once", preview.effective_profile_revision == revision+1 and not preview.effective_profile_dirty)
	var guards := true
	for i in preview.compiled_bundle.components.size():
		var material: ShaderMaterial = preview.water_material if preview.compiled_bundle.components[i].material=="water" else preview.terrain_material
		for key in preview.compiled_constants[i]:
			var prior: Variant = material.get_shader_parameter(key)
			var expected: Variant = preview.compiled_constants[i][key]
			material.set_shader_parameter(key, not expected if expected is bool else float(expected)+1.0)
			preview._seal_test1_effective_profile()
			guards = guards and preview.last_error == "compiled_constant_mismatch: "+String(key)
			material.set_shader_parameter(key, prior)
			preview.last_error = ""
			guards = preview._validate_compiled_inputs() and guards
	_check("all_23_compiled_constants_still_reject_and_recover", guards)
	var shader: Shader = preview.water_material.shader
	preview.water_material.shader = load("res://assets/water_material_natural_candidate/water_height.gdshader")
	preview._seal_test1_effective_profile()
	_check("compiled_shader_path_still_rejected", preview.last_error=="compiled_shader_path_mismatch")
	preview.water_material.shader = shader; preview.last_error = ""
	_check("profile_recovers_after_negative_cases", preview.refresh_effective_render_profile())

func _reflection_contract() -> void:
	var viewport: SubViewport = preview.reflection_viewport
	var camera: Camera3D = preview.player_camera
	var revision: int = preview.reflection_revision
	var before := viewport.get_texture().get_image().get_data()
	await _frames(12)
	_check("static_reflection_stops_rendering", viewport.render_target_update_mode == SubViewport.UPDATE_ONCE and preview.reflection_revision == revision and before == viewport.get_texture().get_image().get_data(), {"mode":viewport.render_target_update_mode,"initial_revision":revision,"revision":preview.reflection_revision,"dynamic":preview.reflection_has_dynamic_material,"dirty":preview.reflection_dirty,"nodes_dirty":preview.reflection_nodes_dirty})
	var transform := camera.global_transform
	var projected: Variant = preview.water_material.get_shader_parameter("prototype_planar_view_projection")
	camera.position.x += 0.5
	await _frames()
	_check("camera_move_refreshes_reflection", preview.reflection_revision > revision and preview.water_material.get_shader_parameter("prototype_planar_view_projection") != projected and before != viewport.get_texture().get_image().get_data())
	camera.global_transform = transform
	await _frames()
	_check("camera_restore_keeps_original_reflection_pixels", before == viewport.get_texture().get_image().get_data())
	# SubViewport's node getter keeps UPDATE_ONCE; the rendering server disables it after drawing.
	var fov: float = camera.fov
	revision = preview.reflection_revision; camera.fov += 4.0
	await _frames()
	_check("projection_change_refreshes_reflection", preview.reflection_revision > revision and preview.reflection_camera.fov == camera.fov)
	camera.fov = fov
	viewport.size = Vector2i(768,432); revision = preview.reflection_revision
	await _frames()
	_check("reflection_resize_refreshes", preview.reflection_revision > revision and viewport.get_texture().get_width() == 768)
	viewport.size = Vector2i(960,540)
	var rock: MeshInstance3D = preview.get_node("ReflectionRockEnvironment/LeftRock")
	var position := rock.position
	revision = preview.reflection_revision; rock.position.x += 1.0
	await _frames()
	_check("rock_transform_refreshes_reflection", preview.reflection_revision > revision)
	rock.position = position
	var material := StandardMaterial3D.new()
	rock.material_override = material
	await _frames()
	revision = preview.reflection_revision; material.albedo_color = Color.RED
	await _frames()
	_check("replacement_material_changes_refresh_reflection", preview.reflection_revision > revision, {"initial_revision":revision,"revision":preview.reflection_revision})
	rock.material_override = null
	var energy: float = preview.get_node("SandFixtureSun").light_energy
	revision = preview.reflection_revision; preview.get_node("SandFixtureSun").light_energy = energy+0.5
	await _frames()
	_check("sun_energy_refreshes_reflection", preview.reflection_revision > revision)
	preview.get_node("SandFixtureSun").light_energy = energy
	var sun_basis: Basis = preview.get_node("SandFixtureSun").basis
	preview.get_node("SandFixtureSun").rotate_y(0.1)
	await _frames()
	_check("sun_direction_uniform_updates_when_changed", preview.water_material.get_shader_parameter("prototype_light_direction_world") == preview.get_node("SandFixtureSun").global_basis.z.normalized())
	preview.get_node("SandFixtureSun").basis = sun_basis
	preview.reflection_update_always = true
	await _frames(2)
	_check("dynamic_reflection_can_render_continuously", viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS)
	preview.reflection_update_always = false; preview.invalidate_reflection()
	await _frames()
	_check("reflection_returns_to_cached_mode", viewport.render_target_update_mode == SubViewport.UPDATE_ONCE,{"mode":viewport.render_target_update_mode,"dynamic":preview.reflection_has_dynamic_material,"dirty":preview.reflection_dirty,"nodes_dirty":preview.reflection_nodes_dirty})
	preview.refresh_effective_render_profile()

func _ui_contract() -> void:
	var button: Button = preview.manual_wave_button
	preview._sync_manual_wave_ui()
	_check("wave_button_available", not button.disabled)
	preview.gpu_save_running = true; preview._sync_manual_wave_ui()
	_check("wave_button_tracks_save_state", button.disabled)
	preview.gpu_save_running = false; preview.manual_wave_message = "cache regression"
	preview._sync_manual_wave_ui()
	_check("wave_button_and_message_update", not button.disabled and preview.manual_wave_label.text == "cache regression")
	preview._update_status()
	_check("status_text_preserves_player_instructions", "右键转向 WASD移动" in preview.status_label.text and "桶 " not in preview.status_label.text)
	var panel = preview.get_node("Interface/PerformancePanel")
	await create_timer(0.7).timeout
	await _frames()
	var captured: int = panel.seen_frame
	await _frames(16)
	_check("paused_sampling_drains_then_stops_empty_collects", not panel.collect_pending and panel.quiet_capture_frames>=2 and panel.seen_frame==captured and panel.snapshot.fps>0.0)
	await _ticks(2)
	await create_timer(0.65).timeout
	_check("sampling_resumes_for_manual_ticks", panel.seen_frame>captured and panel.last_stages.has("water"))
	var prior: int = preview.reflection_revision
	var path := output.path_join("frame_cache_checkpoint.bin")
	var error: StringName = await preview.save_gpu_checkpoint(path)
	_check("cached_profile_checkpoint_save", error.is_empty(),String(error))
	var fields := await _snapshot()
	await _ticks(1)
	var generation: int = preview.generation
	var restored: StringName = await preview.restore_gpu_checkpoint(path)
	await _frames()
	_check("restore_invalidates_profile_and_reflection", restored.is_empty() and preview.effective_profile_generation==preview.generation and preview.generation!=generation and preview.reflection_revision>prior, String(restored))
	var after := await _snapshot()
	var same := true
	for field in FIELDS: same = same and fields[field]==after[field]
	_check("cache_restore_preserves_all_10_fields", same)
	_check("restore_keeps_profile_clocks_and_digest_current", preview.effective_render_profile.visual_time_s == preview.visual_time_s and preview.effective_style.visual_time_s == preview.visual_time_s and preview.effective_render_profile_sha256 == JSON.stringify(preview.effective_render_profile).sha256_text())

func _run() -> void:
	root.size = Vector2i(1280,720)
	_cfl_contract()
	preview = load("res://scenes/main.tscn").instantiate()
	preview.playing = false; root.add_child(preview)
	var deadline:=Time.get_ticks_msec()+120000
	while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_msec()<deadline: await process_frame
	_check("main_ready",preview.ready_for_ticks and preview.last_error.is_empty(),preview.last_error)
	if not preview.ready_for_ticks: _finish();quit(1);return
	await _frames(12)
	await _profile_contract()
	await _paired_cfl_contract()
	await _reflection_contract()
	await _ui_contract()
	_check("no_unexpected_runtime_error", preview.last_error.is_empty(),preview.last_error)
	await preview.shutdown()
	_check("clean_shutdown",preview.gpu_release_done)
	_finish()
	var passed:=true
	for row in checks: passed=passed and row.pass
	quit(0 if passed else 1)

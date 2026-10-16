extends "res://tests/integration/ui_sand_edit_probe.gd"

const Store = preload("res://scripts/simulation/checkpoint_store.gd")
const READ_FIELDS := ["sand", "sediment", "water", "momentum_x", "momentum_z"]

func _read() -> void:
	for field in READ_FIELDS:
		scene.solver.request_data(field, func(bytes: PackedByteArray) -> void: call_deferred("_received", field, bytes))
	scene.solver.rd.texture_get_data_async(scene.solver.textures.sediment[1-scene.solver.current_index], 0, func(bytes: PackedByteArray) -> void: call_deferred("_received", "spare_sediment", bytes))

func snapshot() -> Dictionary:
	fields = {}
	RenderingServer.call_on_render_thread(_read)
	var deadline := Time.get_ticks_msec() + 30000
	while fields.size() < 6 and Time.get_ticks_msec() < deadline: await process_frame
	check("readback_complete", fields.size() == 6)
	return fields.duplicate()

func volume(bytes: PackedByteArray) -> float:
	var result := 0.0
	for value in bytes.to_float32_array(): result += value * 0.015625
	return result

func _settled() -> void:
	var deadline := Time.get_ticks_msec() + 30000
	while (scene.busy or scene.input_running or scene.collision_proxy.staging_texture.is_valid() or not scene.collision_proxy.pending_revisions.is_empty() or scene.collision_proxy.has_prepare_in_flight()) and scene.last_error.is_empty() and Time.get_ticks_msec() < deadline: await process_frame
	await physics_frame
	await physics_frame

func wet_pick(state: Dictionary, wet: bool) -> Vector2:
	for y in range(640, 160, -20):
		for x in range(320, 960, 20):
			var hit: Dictionary = scene.pick(Vector2(x, y))
			if hit.is_empty() or not scene._pick_current(hit) or absf(hit.position.x) > 13.0 or absf(hit.position.z) > 13.0: continue
			var ix := clampi(int((hit.position.x + 16.0) / 0.125), 7, 248)
			var iz := clampi(int((hit.position.z + 16.0) / 0.125), 7, 248)
			var valid := true
			for dz in range(-6, 7):
				for dx in range(-6, 7):
					var depth: float = state.water.decode_float(((iz+dz)*256+ix+dx)*4)
					if (wet and depth < 0.04) or (not wet and depth > 0.001): valid = false
			if valid: return Vector2(x, y)
	return Vector2(-1, -1)

func _run() -> void:
	if output == "res://test_output/ui_sand_edit_20261016": output = "res://test_output/suspended_sand_20261016"
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1280, 720)
	harness = load("res://tests/experiments/approx_gpu_edit/input_harness.tscn").instantiate()
	root.add_child(harness)
	viewport = harness.get_node("InputViewport")
	for path in ["res://scenes/main.tscn", "res://scenes/playable/test1_capture.tscn", "res://scenes/playable/test1_backwash.tscn"]:
		scene = load(path).instantiate()
		scene.playing = false
		viewport.add_child(scene)
		var deadline := Time.get_ticks_msec() + 90000
		while not scene.ready_for_ticks and scene.last_error.is_empty() and Time.get_ticks_msec() < deadline: await process_frame
		check(scene.scene_key + "_ready", scene.ready_for_ticks, scene.last_error)
		if not scene.ready_for_ticks: break
		scene.get_node("Interface/PerformancePanel/Margin/Rows/Header/Sampling").button_pressed = false
		await _settled()
		await tap(scene.brush_panel.get_node("Margin/Controls/Tools/SuspendedSand").get_global_rect().get_center())
		check("select_suspended_tool", scene.ui_tool == &"suspended_sand")
		scene.brush_panel.get_node("Margin/Controls/OrdinaryParams/FillAmount").value = 0.1
		await tap(scene.get_node("UIVisibility/ToggleUI").get_global_rect().get_center())
		var before := await snapshot()
		var screen := wet_pick(before, true)
		check(scene.scene_key + "_wet_pick", screen.x >= 0)
		if screen.x >= 0:
			var hit: Dictionary = scene.pick(screen)
			var source: float = scene.domain.sand_source_m3
			await tap(screen)
			await _settled()
			var added := await snapshot()
			var amount := volume(added.sediment) - volume(before.sediment)
			check("suspended_adds_full_amount", absf(amount - 0.1) < 0.000001, amount)
			check("bed_water_momentum_unchanged", before.sand == added.sand and before.water == added.water and before.momentum_x == added.momentum_x and before.momentum_z == added.momentum_z)
			check("both_sediment_slots", added.sediment == added.spare_sediment)
			check("source_ledger", absf(scene.domain.sand_source_m3 - source - amount) < 0.000001)
			check("cloud_uses_authoritative_sediment", scene.get_node("SuspendedSandCloud").visible and scene.get_node("SuspendedSandCloud").cloud_material.get_shader_parameter("suspended_sand_state") == scene.sediment_texture)
			await RenderingServer.frame_post_draw
			viewport.get_texture().get_image().save_png(output.path_join(scene.scene_key + "_injected.png"))
			# Save/restore the new tool selection and both suspended-sand slots.
			var save_path := output.path_join(scene.scene_key + ".sandcp")
			var error: StringName = await scene.save_gpu_checkpoint(save_path)
			check("save_suspended_checkpoint", error.is_empty(), error)
			if error.is_empty():
				var saved: Dictionary = Store.load(save_path).checkpoint
				error = await scene.restore_gpu_checkpoint_data(saved)
				check("restore_suspended_checkpoint", error.is_empty(), error)
				check("restore_state_and_selection", added == await snapshot() and scene.ui_tool == &"suspended_sand")
			var start_total := volume(added.sand) + volume(added.sediment)
			# Isolate injected sand from new background erosion during this observation.
			# Production coefficients stay unchanged; transport and settling remain active.
			scene.sediment_coupler.erosion_rate_per_s = 0.0
			for step in 20:
				var tick: int = scene.completed_ticks
				scene._start_tick()
				deadline = Time.get_ticks_msec() + 30000
				while scene.completed_ticks == tick and scene.last_error.is_empty() and Time.get_ticks_msec() < deadline: await process_frame
			await _settled()
			var moved := await snapshot()
			var outside := 0.0
			for i in 65536:
				var cell := Vector2((i%256+0.5)*0.125-16.0, (i/256+0.5)*0.125-16.0)
				if cell.distance_to(Vector2(hit.position.x, hit.position.z)) > 0.85:
					outside += maxf(0.0, moved.sediment.decode_float(i*4) - added.sediment.decode_float(i*4))*0.015625
			check("sediment_moves_outside_brush", outside > 0.000001, outside)
			check("transport_settling_conserve_total", absf(volume(moved.sand)+volume(moved.sediment)-start_total) < 0.0001, volume(moved.sand)+volume(moved.sediment)-start_total)
			check("some_suspended_sand_settles", volume(moved.sediment) < volume(added.sediment), [volume(added.sediment), volume(moved.sediment)])
			await RenderingServer.frame_post_draw
			viewport.get_texture().get_image().save_png(output.path_join(scene.scene_key + "_moved.png"))
			# A fully dry footprint must reject with zero writes and zero source.
			var dry := wet_pick(moved, false)
			check("dry_pick", dry.x >= 0)
			if dry.x >= 0:
				var source_dry: float = scene.domain.sand_source_m3
				await tap(dry)
				await _settled()
				check("dry_rejected_without_mutation", moved == await snapshot() and scene.domain.sand_source_m3 == source_dry and scene.input_results[-1].result.status == 2)
		await scene.get_node("Interface/PerformancePanel").stop_sampling()
		await scene.shutdown()
		scene.queue_free()
		await process_frame
	var passed := not checks.is_empty()
	for row in checks: passed = passed and row.pass
	var file := FileAccess.open(output.path_join("result.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass": passed, "checks": checks, "engine": Engine.get_version_info()}, "\t"))
	quit(0 if passed else 1)

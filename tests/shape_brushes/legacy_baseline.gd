extends "res://tests/water_material_natural/rdc_main_smoke.gd"

var stages := []
const Protocol = preload("res://scripts/simulation/edit_validation/edit_protocol.gd")

func _capture(tag: String) -> Dictionary:
	var state := await _snapshot()
	var identity := {}
	for field in FIELDS:
		var bytes: PackedByteArray = state[field]
		var path := output.path_join(tag + "_" + field + ".bin")
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_buffer(bytes)
		file.close()
		var total := 0.0
		for i in range(0, bytes.size(), 4): total += bytes.decode_float(i)
		identity[field] = {"path": path, "bytes": bytes.size(), "sha256": FileAccess.get_sha256(path), "sum": total}
	var ledger := {}
	for key in ["tool_inventory_m3", "sand_source_m3", "sand_sink_m3"]: ledger[key] = preview.shadow_domain.get(key)
	ledger.water_source_m3 = preview.solver.water_source_m3
	ledger.water_sink_m3 = preview.solver.water_sink_m3
	stages.append({"tag": tag, "tick": preview.completed_ticks, "generation": preview.generation, "revision": preview.solver.state_revision, "fields": identity, "ledger": ledger, "collision": preview.collision_proxy.applied_revisions.duplicate(true)})
	return state

func _settle() -> void:
	var deadline := Time.get_ticks_msec() + 30000
	while preview.busy or preview.input_running or preview.collision_proxy.staging_texture.is_valid() or not preview.collision_proxy.pending_revisions.is_empty():
		await process_frame
		if Time.get_ticks_msec() > deadline:
			_check("settle_timeout", false)
			return

func _run() -> void:
	root.size = Vector2i(1280, 720)
	preview = load("res://scenes/main.tscn").instantiate()
	preview.playing = false
	root.add_child(preview)
	var deadline := Time.get_ticks_msec() + 90000
	while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_msec() < deadline: await process_frame
	_check("main_ready", preview.ready_for_ticks and preview.last_error.is_empty(), preview.last_error)
	if not preview.ready_for_ticks: _finish(); quit(1); return
	await _ticks(2)
	await _settle()
	var previous := await _capture("initial")
	for kind in [&"place_sand", &"remove_sand"]:
		var command := {"domain_id": preview.domain.domain_id, "generation": preview.generation, "sim_tick": preview.completed_ticks, "command_id": preview.command_queue.last_command_id + 1, "kind": kind, "shape": &"circle", "transform": {"position_m": Vector3(-2, 0, 0), "end_position_m": Vector3(-2, 0, 0)}, "radius_m": 0.5, "strength": 1.0, "amount_m3": 0.10, "seed": 101}
		var error: StringName = preview.input_scheduler.submit(command)
		await preview.input_scheduler.drain_due()
		await _settle()
		_check(String(kind), error.is_empty() and not preview.input_scheduler.terminal.is_empty() and preview.input_scheduler.terminal[-1].result.get("status") == 1, preview.input_scheduler.terminal[-1] if not preview.input_scheduler.terminal.is_empty() else String(error))
		var current := await _capture(String(kind))
		var a: PackedFloat32Array = previous.sand.to_float32_array()
		var b: PackedFloat32Array = current.sand.to_float32_array()
		var volume := 0.0
		for i in a.size(): volume += (b[i] - a[i]) * 0.015625
		var budget := Protocol.volume_budget(a, b, 0.015625)
		var actual: float = preview.input_scheduler.terminal[-1].result.actual_sand_m3
		_check(String(kind) + "_raw_volume_matches_receipt", absf(absf(volume) - actual) <= float(budget.edit_m3), {"delta_m3": volume, "receipt_m3": actual, "budget": budget})
		_check(String(kind) + "_external_inventory_zero", preview.shadow_domain.tool_inventory_m3 == 0.0)
		previous = current
	var before := await _capture("saved")
	var save_error: StringName = await preview.save_gpu_checkpoint(output.path_join("legacy_checkpoint.bin"))
	_check("native_save", save_error.is_empty(), String(save_error))
	await _ticks(2)
	await _settle()
	var original_continuation := await _capture("original_continuation")
	var restore_error: StringName = await preview.restore_gpu_checkpoint(output.path_join("legacy_checkpoint.bin"))
	_check("native_restore", restore_error.is_empty(), String(restore_error))
	await _settle()
	var after := await _capture("restored")
	for field in FIELDS: _check("restore_exact_" + field, before[field] == after[field])
	await _ticks(2)
	await _settle()
	var restored_continuation := await _capture("restored_continuation")
	var continuation := {}
	for field in FIELDS: continuation[field] = original_continuation[field] == restored_continuation[field]
	var strict_report := FileAccess.open(output.path_join("strict_continuation_diagnostic.json"), FileAccess.WRITE)
	strict_report.store_string(JSON.stringify({"field_exact": continuation, "scope": "two ticks only; diagnostic, does not reclassify historical strict continuation gate"}, "\t"))
	strict_report.close()
	_check("continue_collision", preview.last_error.is_empty() and preview.collision_proxy.applied_revisions.size() == 64, preview.last_error)
	root.get_texture().get_image().save_png(output.path_join("legacy_main.png"))
	var report := FileAccess.open(output.path_join("raw_stages.json"), FileAccess.WRITE)
	report.store_string(JSON.stringify({"stages": stages, "engine": Engine.get_version_info(), "adapter": RenderingServer.get_video_adapter_name(), "vsync": DisplayServer.window_get_vsync_mode(), "viewport": root.size, "effective_style": preview.effective_style, "source_signature": preview.source_signature}, "\t"))
	report.close()
	await preview.shutdown()
	_check("clean_shutdown", preview.gpu_release_done)
	_finish()
	var passed := true
	for row in checks: passed = passed and row.pass
	quit(0 if passed else 1)

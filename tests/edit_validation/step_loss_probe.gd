extends "res://tests/edit_validation/water_transaction_probe.gd"

var loss_data := PackedByteArray()

func _write(ok: bool, error := "") -> void:
	var file := FileAccess.open(output.path_join("step_loss_probe.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass": ok, "rows": rows, "error": error,
		"scope": "original vs diagnostic update, 15 completed ticks; no cost verdict"}, "\t"))

func _read_loss() -> void:
	lab.solver.rd.buffer_get_data_async(lab.solver.step_loss_buffer, _loss_ready)

func _loss_ready(bytes: PackedByteArray) -> void: call_deferred("_record_loss", bytes)
func _record_loss(bytes: PackedByteArray) -> void: loss_data = bytes

func _seed(size: int, name: String) -> Dictionary:
	var fields := {}
	for key in ["water", "momentum_x", "momentum_z", "sediment"]:
		var values := PackedFloat32Array()
		values.resize(size * size)
		values.fill(0.12 if key == "water" else 0.0)
		fields[key] = values
	if name == "forced_native_limit": fields.momentum_x.fill(0.12 * 8.0)
	if name == "threshold_drying":
		fields.water.fill(0.00105)
		fields.momentum_x.fill(0.0001)
		fields.sediment.fill(0.0002)
	return fields

func _variant(size: int, name: String, diagnostic: bool) -> Dictionary:
	var scene_name := "edit_gpu_water_" + ("diagnostic_" if diagnostic else "") + ("numeric" if size == 64 else "brush") + "_lab.tscn"
	lab = load("res://tests/edit_validation/" + scene_name).instantiate()
	root.add_child(lab)
	while not lab.ready_for_ticks and lab.last_error.is_empty(): await process_frame
	if not lab.last_error.is_empty(): return {}
	await lab.seed_test_fields(_seed(size, name))
	lab.water_policy = 1 if name == "threshold_drying" else 2
	lab.signed_speed_m_s = 0.5 if name == "D_velocity" else 0.0
	var prefix := "%d_%s_%s" % [size, name, "diagnostic" if diagnostic else "original"]
	var amount := 0.0001 if name == "threshold_drying" else 0.48
	var receipt: Dictionary = await lab.apply_gpu_command(_command(1, amount))
	if not lab.last_error.is_empty() or receipt.get("status") != 1: return {}
	var initial: Dictionary = await _snapshot(prefix + "_initial")
	await lab.advance_ticks(15)
	if not lab.last_error.is_empty(): return {}
	var final: Dictionary = await _snapshot(prefix + "_final")
	var statistics := {}
	if diagnostic:
		loss_data.clear()
		RenderingServer.call_on_render_thread(_read_loss)
		while loss_data.is_empty(): await process_frame
		_save(prefix + "_step_loss.bin", loss_data)
		var ix := 0.0
		var iz := 0.0
		var energy := 0.0
		var absolute_momentum := 0.0
		var events := PackedInt64Array([0, 0, 0, 0])
		var finite := true
		var state_flags := 0
		for i in size * size:
			for slot in 4: finite = finite and is_finite(loss_data.decode_float(i * 32 + slot * 4))
			ix += loss_data.decode_float(i * 32) * 0.015625
			iz += loss_data.decode_float(i * 32 + 4) * 0.015625
			energy += loss_data.decode_float(i * 32 + 8) * 0.015625
			absolute_momentum += loss_data.decode_float(i * 32 + 12) * 0.015625
			for slot in 3: events[slot] += loss_data.decode_u32(i * 32 + 16 + slot * 4)
			var last := loss_data.decode_u32(i * 32 + 28)
			events[3] += last & 0x00ffffff
			state_flags |= last >> 24
		statistics = {"removed_momentum_m4_s": [ix, iz], "removed_energy_defined_m5_s2": energy,
			"absolute_removed_momentum_m4_s": absolute_momentum, "events": Array(events),
			"event_order": ["dry_or_ocean_zero", "native_velocity_limit", "blocked_zero", "undefined_zero_depth_energy"],
			"finite": finite, "completed_substeps_state_flags": state_flags, "shader_metadata": lab.shader_metadata}
	await lab.shutdown()
	lab.queue_free()
	await process_frame
	lab = null
	return {"initial": initial, "final": final, "statistics": statistics}

func _run() -> void:
	var failure := ""
	for size in [64, 256]:
		for name in ["D_velocity", "threshold_drying", "forced_native_limit"]:
			var original: Dictionary = await _variant(size, name, false)
			if original.is_empty():
				failure = "original loss fixture failed"
				break
			var observed: Dictionary = await _variant(size, name, true)
			if observed.is_empty():
				failure = "diagnostic fixture failed"
				break
			var exact := true
			for key in original.initial:
				if key != "water_receipt": exact = exact and original.initial[key] == observed.initial[key] and original.final[key] == observed.final[key]
			var stats: Dictionary = observed.statistics
			var expected_events: bool = (name != "forced_native_limit" or stats.events[1] > 0) and (name != "threshold_drying" or stats.events[0] > 0)
			rows.append({"case": name, "grid": size, "pass": exact and stats.finite and expected_events and stats.completed_substeps_state_flags == 0,
				"authority_and_publication_bitwise_equal": exact, "completed_ticks": 15,
				"actual_sim_s": 0.5, "statistics": stats, "expected_event_branch_observed": expected_events})
			_write(false, "running")
		if not failure.is_empty(): break
	var ok := failure.is_empty() and rows.size() == 6
	for row in rows: ok = ok and row.pass
	_write(ok, failure)
	if lab != null:
		await lab.shutdown()
		lab.queue_free()
	finished = true
	print("STEP_LOSS_COMPLETE pass=%s rows=%d" % [str(ok), rows.size()])
	quit(0 if ok else 1)

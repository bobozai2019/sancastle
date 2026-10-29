extends "res://tests/edit_validation/velocity_probe.gd"

var raw_result := PackedByteArray()
var native_cfl := PackedByteArray()

func _write(ok: bool, error := "") -> void:
	var file := FileAccess.open(output.path_join("velocity_negative_probe.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass": ok, "rows": rows, "error": error,
		"scope": "host/GPU invalid speed and native CFL admission boundary; artificial transport fixtures, not ordinary flow"}, "\t"))

func _raw_dispatch(wire: PackedByteArray) -> void:
	if not lab.solver.dispatch_sand_command(wire, _raw_ready): call_deferred("_raw_fail")

func _raw_ready(bytes: PackedByteArray) -> void: call_deferred("_record_raw", bytes)
func _record_raw(bytes: PackedByteArray) -> void: raw_result = bytes
func _raw_fail() -> void: lab._fail("raw negative dispatch unavailable")

func _cfl_read() -> void:
	if lab.solver.request_cfl_tiles(_cfl_ready) != OK: call_deferred("_raw_fail")

func _cfl_ready(bytes: PackedByteArray, _revision: int) -> void: call_deferred("_record_cfl", bytes)
func _record_cfl(bytes: PackedByteArray) -> void: native_cfl = bytes

func _same(before: Dictionary, after: Dictionary) -> bool:
	for key in before:
		if key != "water_receipt" and before[key] != after[key]: return false
	return true

func _invalid(size: int, speed: float, raw: bool) -> void:
	await lab.seed_test_fields(_seed(size, "still"))
	if not lab.last_error.is_empty(): return
	lab.water_policy = 2
	var prefix := "%d_%s_%s" % [size, "raw" if raw else "host", str(speed)]
	var before: Dictionary = await _snapshot(prefix + "_before")
	var revision: int = lab.solver.state_revision
	var stock: float = lab.domain.tool_inventory_m3
	var result := {}
	if raw:
		raw_result.clear()
		var wire := Protocol.encode(_command(1, 0.01), lab.ticket_id + 1, revision, size, 0.125, 2, stock, speed)
		_save(prefix + "_command.bin", wire)
		RenderingServer.call_on_render_thread(_raw_dispatch.bind(wire))
		while raw_result.is_empty() and lab.last_error.is_empty(): await process_frame
		if not lab.last_error.is_empty(): return
		_save(prefix + "_receipt.bin", raw_result)
		result = Protocol.decode_receipt(raw_result)
	else:
		lab.signed_speed_m_s = speed
		result = await lab.apply_gpu_command(_command(1, 0.01))
	var after: Dictionary = await _snapshot(prefix + "_after")
	var identity := _same(before, after)
	var rejected: bool = result.get("status") == 2 and result.get("error_code") == 1 if raw else result.get("error") == "invalid_command"
	var ok: bool = rejected and identity and revision == lab.solver.state_revision and stock == lab.domain.tool_inventory_m3 and lab.reserved_m3 == 0.0
	rows.append({"case": "invalid_speed_raw" if raw else "invalid_speed_host", "grid": size,
		"speed_label": str(speed), "pass": ok, "result": result, "authority_and_display_exact": identity,
		"revision_unchanged": revision == lab.solver.state_revision, "stock_unchanged": stock == lab.domain.tool_inventory_m3})
	_write(false, "running")

func _boundary(size: int, target: float) -> void:
	var seed := _seed(size, "still")
	var depth: float = seed.water[0]
	seed.momentum_x.fill((target - sqrt(9.81 * depth)) * depth)
	await lab.seed_test_fields(seed)
	if not lab.last_error.is_empty(): return
	lab.water_policy = 2
	lab.signed_speed_m_s = 0.0
	var prefix := "%d_cfl_%s" % [size, str(target)]
	var before: Dictionary = await _snapshot(prefix + "_before")
	var stock: float = lab.domain.tool_inventory_m3
	var revision: int = lab.solver.state_revision
	native_cfl.clear()
	RenderingServer.call_on_render_thread(_cfl_read)
	while native_cfl.is_empty() and lab.last_error.is_empty(): await process_frame
	if not lab.last_error.is_empty(): return
	_save(prefix + "_native_cfl.bin", native_cfl)
	var expected: int = lab.solver.substeps_from_cfl(1.0 / 30.0, native_cfl)
	var result: Dictionary = await lab.apply_gpu_command(_command(1, 0.01))
	if not lab.last_error.is_empty(): return
	var after: Dictionary = await _snapshot(prefix + "_after")
	_save(prefix + "_receipt.bin", lab.raw_receipt)
	var meta: PackedByteArray = after.water_receipt
	var physical_identity := true
	for key in ["water", "sediment", "momentum_x", "momentum_z", "published_water"]: physical_identity = physical_identity and before[key] == after[key]
	var should_reject := expected > 64
	var status_ok: bool = result.get("status") == 2 and result.get("invalid_flags") == 16 if should_reject else result.get("status") == 1
	var all_exact := _same(before, after)
	var rollback_ok: bool = not should_reject or (all_exact and stock == lab.domain.tool_inventory_m3 and revision == lab.solver.state_revision)
	var steps_ok: bool = int(meta.decode_u32(124)) == expected
	rows.append({"case": "cfl_boundary", "grid": size, "target_signal_m_s": target,
		"native_signal_m_s": native_cfl.to_float32_array()[0], "candidate_signal_m_s": meta.decode_float(120),
		"native_expected_steps": expected, "candidate_steps": meta.decode_u32(124),
		"pass": status_ok and steps_ok and physical_identity and rollback_ok,
		"status_matches_native": status_ok, "steps_match_native": steps_ok,
		"water_momentum_exact": physical_identity, "rejection_rollback": rollback_ok, "result": result})
	_write(false, "running")

func _run() -> void:
	var failure := ""
	for size in [64, 256]:
		lab = load("res://tests/edit_validation/edit_gpu_water_" + ("numeric" if size == 64 else "brush") + "_lab.tscn").instantiate()
		root.add_child(lab)
		while not lab.ready_for_ticks and lab.last_error.is_empty(): await process_frame
		for speed in [NAN, INF, 2.0]:
			for raw in [false, true]:
				await _invalid(size, speed, raw)
				if not lab.last_error.is_empty(): break
		for target in [83.99998, 84.0, 84.00002, 1000.0]:
			await _boundary(size, target)
			if not lab.last_error.is_empty(): break
		if not lab.last_error.is_empty(): failure = lab.last_error
		await lab.shutdown()
		lab.queue_free()
		await process_frame
		lab = null
		if not failure.is_empty(): break
	var ok := failure.is_empty() and rows.size() == 20
	for row in rows: ok = ok and row.pass
	_write(ok, failure)
	finished = true
	print("VELOCITY_NEGATIVE_COMPLETE pass=%s rows=%d" % [str(ok), rows.size()])
	quit(0 if ok else 1)

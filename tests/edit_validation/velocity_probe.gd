extends "res://tests/edit_validation/water_transaction_probe.gd"

var candidate_policy := 2
var command_amount_m3 := 0.01
var case_kinds := ["still", "clip", "dry", "swept", "zero_strength", "center", "degenerate"]

func _velocity_baseline(_size: int, _kind: String, _command: Dictionary, before: Dictionary, _prefix: String) -> Dictionary:
	return before

func _write(ok: bool, error := "") -> void:
	var file := FileAccess.open(output.path_join("velocity_probe.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass": ok, "rows": rows, "error": error,
		"scope": "native D velocity-only numeric/impulse/energy/CFL admission; no E combination or performance"}, "\t"))

func _seed(size: int, kind: String) -> Dictionary:
	var fields := {}
	for key in ["water", "momentum_x", "momentum_z", "sediment"]:
		var values := PackedFloat32Array()
		values.resize(size * size)
		values.fill(0.12 if key == "water" else 0.0)
		fields[key] = values
	if kind == "dry": fields.water.fill(0.0)
	if kind == "clip":
		fields.water.fill(1.2)
		fields.momentum_x.fill(1.2 * 3.9)
	if kind == "center":
		fields.water.fill(0.08)
		fields.momentum_x.fill(0.1)
	return fields

func _case(size: int, kind: String, speed: float) -> void:
	await lab.seed_test_fields(_seed(size, kind))
	if not lab.last_error.is_empty(): return
	lab.water_policy = candidate_policy
	lab.signed_speed_m_s = speed
	var prefix := "%d_%s_%s" % [size, kind, str(speed)]
	var before: Dictionary = await _snapshot(prefix + "_before")
	var command := _command(1, command_amount_m3)
	if kind == "dig": command.kind = &"remove_sand"
	if kind == "zero_strength": command.strength = 0.0
	if kind == "center": command.transform.position_m = Vector3(0.0625,0,0.0625)
	if kind == "degenerate":
		command.shape = &"swept_segment"
		command.transform.end_position_m = Vector3.ZERO
	if kind == "swept":
		command.shape = &"swept_segment"
		command.transform.position_m = Vector3(-1.0,0,-0.25)
		command.transform.end_position_m = Vector3(1.0,0,0.25)
	var original_before := before
	before = await _velocity_baseline(size, kind, command, before, prefix)
	lab.water_policy = candidate_policy
	lab.signed_speed_m_s = speed
	_save(prefix + "_command.bin", Protocol.encode(command, lab.ticket_id + 1, lab.solver.state_revision, size, 0.125, candidate_policy, lab.domain.tool_inventory_m3, speed))
	var receipt: Dictionary = await lab.apply_gpu_command(command)
	if not lab.last_error.is_empty(): return
	var after: Dictionary = await _snapshot(prefix + "_after")
	_save(prefix + "_receipt.bin", lab.raw_receipt)
	var h: PackedFloat32Array = before.water.to_float32_array()
	var bx: PackedFloat32Array = before.momentum_x.to_float32_array()
	var bz: PackedFloat32Array = before.momentum_z.to_float32_array()
	var ax: PackedFloat32Array = after.momentum_x.to_float32_array()
	var az: PackedFloat32Array = after.momentum_z.to_float32_array()
	var ex := PackedFloat64Array(Array(bx))
	var ez := PackedFloat64Array(Array(bz))
	var distribution := true
	var untouched := true
	var bound := true
	var zero_direction_exact := true
	var clamp_count := 0
	var input_energy := 0.0
	var removed_energy := 0.0
	var energy_magnitude := 0.0
	var energy_absolute_delta := 0.0
	var actual_ix := 0.0
	var actual_iz := 0.0
	var loss_x := 0.0
	var loss_z := 0.0
	var max_error := 0.0
	var count := 0
	var max_signal := 0.01
	var area := 0.015625
	for i in size * size:
		var p: Vector3 = command.transform.position_m
		var dx: float = ((i % size) + 0.5 - size * 0.5) * 0.125 - p.x
		var dz: float = (floori(float(i) / size) + 0.5 - size * 0.5) * 0.125 - p.z
		if command.shape == &"swept_segment":
			var end: Vector3 = command.transform.end_position_m
			var sx: float = end.x - p.x
			var sz: float = end.z - p.z
			var l2 := sx * sx + sz * sz
			if l2 > 1e-6:
				var t := clampf((dx * sx + dz * sz) / l2, 0.0, 1.0)
				dx -= sx * t
				dz -= sz * t
		var distance := sqrt(dx * dx + dz * dz)
		var applied: bool = distance <= command.radius_m and h[i] > 0.001 and speed != 0.0 and command.strength != 0.0
		if applied:
			if distance == 0.0 and sqrt(bx[i] * bx[i] + bz[i] * bz[i]) / h[i] <= 4.0:
				zero_direction_exact = zero_direction_exact and ax[i] == bx[i] and az[i] == bz[i]
			count += 1
			var weight := maxf(0.001, 1.0 - distance / command.radius_m)
			var ux := bx[i] / h[i] + (dx / distance if distance > 0.0 else 0.0) * weight * speed
			var uz := bz[i] / h[i] + (dz / distance if distance > 0.0 else 0.0) * weight * speed
			var raw_x := ux * h[i]
			var raw_z := uz * h[i]
			var velocity := sqrt(ux * ux + uz * uz)
			if velocity > 4.0:
				ux *= 4.0 / velocity
				uz *= 4.0 / velocity
				clamp_count += 1
			ex[i] = ux * h[i]
			ez[i] = uz * h[i]
			loss_x += (raw_x - ex[i]) * area
			loss_z += (raw_z - ez[i]) * area
			var energy_before := 0.5 * (bx[i] * bx[i] + bz[i] * bz[i]) / h[i] * area
			var energy_raw := 0.5 * (raw_x * raw_x + raw_z * raw_z) / h[i] * area
			var energy_after := 0.5 * (ex[i] * ex[i] + ez[i] * ez[i]) / h[i] * area
			input_energy += energy_raw - energy_before
			removed_energy += energy_raw - energy_after
			energy_magnitude += absf(energy_before) + absf(energy_raw) + absf(energy_after)
			energy_absolute_delta += absf(energy_raw - energy_before) + absf(energy_raw - energy_after)
			bound = bound and sqrt(ax[i] * ax[i] + az[i] * az[i]) / h[i] <= 4.0 * (1.0 + 16.0 * Protocol.UNIT_ROUNDOFF)
		else: untouched = untouched and ax[i] == bx[i] and az[i] == bz[i]
		max_error = maxf(max_error, maxf(absf(ax[i] - ex[i]), absf(az[i] - ez[i])))
		distribution = distribution and is_finite(ax[i]) and is_finite(az[i]) and absf(ax[i] - ex[i]) <= Protocol.cell_budget(bx[i], ex[i]) and absf(az[i] - ez[i]) <= Protocol.cell_budget(bz[i], ez[i])
		actual_ix += (ax[i] - bx[i]) * area
		actual_iz += (az[i] - bz[i]) * area
		if h[i] > 0.001: max_signal = maxf(max_signal, maxf(absf(ax[i]), absf(az[i])) / maxf(h[i], 0.005) + sqrt(9.81 * h[i]))
	_save(prefix + "_oracle_f64_qx.bin", ex.to_byte_array())
	_save(prefix + "_oracle_f64_qz.bin", ez.to_byte_array())
	var bqx := Protocol.volume_budget(bx, ax, area)
	var bqz := Protocol.volume_budget(bz, az, area)
	var energy_budget := maxf(1e-7, 32.0 * Protocol.UNIT_ROUNDOFF * energy_magnitude + Protocol.reduction_budget(count, energy_absolute_delta))
	var wr: PackedByteArray = after.water_receipt
	var impulse_ok: bool = absf(receipt.get("impulse_x_m4_s", INF) - actual_ix) <= bqx.reduction_m3 and absf(receipt.get("impulse_z_m4_s", INF) - actual_iz) <= bqz.reduction_m3
	var energy_ok: bool = absf(wr.decode_float(88) - input_energy) <= energy_budget and absf(wr.decode_float(92) - removed_energy) <= energy_budget and absf(wr.decode_float(96) - input_energy + removed_energy) <= energy_budget
	var loss_ok: bool = absf(wr.decode_float(76) - loss_x) <= bqx.edit_m3 and absf(wr.decode_float(80) - loss_z) <= bqz.edit_m3
	var cfl_expected := maxi(1, ceili((1.0 / 30.0) * max_signal / (0.35 * 0.125)))
	var cfl_ok: bool = int(wr.decode_u32(124)) == cfl_expected and cfl_expected <= 64
	var same_water: bool = before.water == after.water and before.sediment == after.sediment
	var same_sand: bool = candidate_policy == 2 or (before.sand == after.sand and before.published_sand == after.published_sand)
	var same_initial: bool = candidate_policy == 2 or _combined_initial_equal(original_before)
	var zero_identity: bool = not (speed == 0.0 or command.strength == 0.0) or (before.momentum_x == after.momentum_x and before.momentum_z == after.momentum_z)
	var ok: bool = receipt.get("status") == 1 and distribution and untouched and bound and impulse_ok and energy_ok and loss_ok and cfl_ok and same_water and same_sand and same_initial and zero_identity and zero_direction_exact and receipt.get("clamp_count") == clamp_count
	rows.append({"case": kind, "grid": size, "speed_m_s": speed, "policy": candidate_policy, "pass": ok,
		"C_sand_exact": same_sand, "C_E_initial_exact": same_initial,
		"max_q_error_m2_s": max_error, "distribution": distribution, "unaffected_exact": untouched,
		"affected_speed_bound": bound, "water_sediment_exact": same_water, "zero_control_exact": zero_identity,
		"zero_direction_exact": zero_direction_exact, "local_dispatch": lab.local_dispatch,
		"actual_impulse_m4_s": [actual_ix, actual_iz], "impulse_matches": impulse_ok,
		"clip_loss_matches": loss_ok, "clamp_count": receipt.get("clamp_count"), "expected_clamp_count": clamp_count,
		"input_energy_m5_s2": input_energy, "removed_energy_m5_s2": removed_energy,
		"energy_budget_m5_s2": energy_budget, "energy_matches": energy_ok,
		"candidate_cfl_steps": wr.decode_u32(124), "cfl_matches": cfl_ok, "receipt": receipt})
	_write(false, "running")

func _combined_initial_equal(_before: Dictionary) -> bool:
	return true

func _run() -> void:
	var failure := ""
	var local := "--local-dispatch" in OS.get_cmdline_user_args()
	for size in [64, 256]:
		lab = load("res://tests/edit_validation/edit_gpu_water_" + ("numeric" if size == 64 else "brush") + "_lab.tscn").instantiate()
		root.add_child(lab)
		while not lab.ready_for_ticks and lab.last_error.is_empty(): await process_frame
		lab.local_dispatch = local
		for kind in case_kinds:
			for speed in [0.0, 0.25, 0.5, -0.25]:
				await _case(size, kind, speed)
				if not lab.last_error.is_empty():
					failure = lab.last_error
					break
			if not failure.is_empty(): break
		await lab.shutdown()
		lab.queue_free()
		await process_frame
		lab = null
		if not failure.is_empty(): break
	var ok := failure.is_empty() and rows.size() == case_kinds.size() * 8
	for row in rows: ok = ok and row.pass
	_write(ok, failure)
	if lab != null:
		await lab.shutdown()
		lab.queue_free()
	finished = true
	print("VELOCITY_COMPLETE pass=%s rows=%d" % [str(ok), rows.size()])
	quit(0 if ok else 1)


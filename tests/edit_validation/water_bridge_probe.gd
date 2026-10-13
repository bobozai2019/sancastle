extends "res://tests/edit_validation/water_transaction_probe.gd"

var bridge_input := PackedByteArray()

func _write(ok: bool, error := "") -> void:
	var file := FileAccess.open(output.path_join("water_bridge_probe.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass": ok, "rows": rows, "error": error,
		"scope": "seed initialization -> native textures -> sand/water transaction -> 3 CFL ticks; no performance"}, "\t"))

func _seed(size: int, name: String) -> Dictionary:
	var fields := {}
	for key in ["rock", "sand", "water", "sediment", "momentum_x", "momentum_z", "obstacle"]:
		var values := PackedFloat32Array()
		values.resize(size * size)
		values.fill(0.4 if key == "sand" else 0.12 if key == "water" else 0.0)
		fields[key] = values
	match name:
		"rock_slope":
			for i in size * size: fields.rock[i] = 0.02 * float(i % size) / (size - 1)
		"suspended_flow":
			fields.sediment.fill(0.003)
			fields.momentum_x.fill(0.024)
			fields.momentum_z.fill(-0.012)
		"obstacle_pools", "dry_pools":
			for z in size:
				for x in range(size / 2 + 1, size): fields.rock[z * size + x] = 0.3
				fields["obstacle" if name == "obstacle_pools" else "water"][z * size + size / 2] = 1.0 if name == "obstacle_pools" else 0.0
		"partial_capacity":
			fields.water.fill(0.0)
			for z in range(size / 2 - 8, size / 2 + 8):
				for x in range(size / 2 - 8, size / 2 + 8): fields.water[z * size + x] = 0.12
		"deep": fields.water.fill(1.2)
		"dry": fields.water.fill(0.0)
		"dry_threshold_flow":
			fields.water.fill(0.00105)
			fields.sediment.fill(0.0002)
			fields.momentum_x.fill(0.0001)
		"row_hole", "row_obstacle", "ring_pool", "multiple_holes":
			for z in size:
				for x in size:
					var dx: int = x - size / 2
					var dz: int = z - size / 2
					var masked: bool = absi(dx) <= 2 and absi(dz) <= 2
					if name == "ring_pool": masked = maxi(absi(dx),absi(dz)) >= 4 and maxi(absi(dx),absi(dz)) <= 5
					if name == "multiple_holes": masked = (absi(dx-4)<=1 or absi(dx+4)<=1) and absi(dz)<=1
					if masked: fields["obstacle" if name == "row_obstacle" else "water"][z*size+x] = 1.0 if name == "row_obstacle" else 0.0
	return fields

func _read_bridge() -> void:
	lab.solver.rd.buffer_get_data_async(lab.solver.water_input, _bridge_ready)

func _bridge_ready(data: PackedByteArray) -> void: call_deferred("_record_bridge", data)
func _record_bridge(data: PackedByteArray) -> void: bridge_input = data

func _case(name: String, size: int) -> void:
	var seed := _seed(size, name)
	await lab.seed_test_fields(seed)
	if not lab.last_error.is_empty(): return
	lab.water_policy = 1
	var prefix := "%s_%d" % [name, size]
	var before: Dictionary = await _snapshot(prefix + "_before")
	var stock: float = lab.domain.tool_inventory_m3
	var amount := 0.0001 if name == "dry_threshold_flow" else 0.00001 if name == "small" else 0.48
	var command := _command(1, amount)
	if name == "dig": command.kind = &"remove_sand"
	if name in ["obstacle_pools", "dry_pools"]: command.transform.position_m.x = -size * 0.125 * 0.25
	_save(prefix + "_command.bin", Protocol.encode(command, lab.ticket_id + 1, lab.solver.state_revision, size, 0.125, 1, stock))
	var receipt: Dictionary = await lab.apply_gpu_command(command)
	if not lab.last_error.is_empty(): return
	var after: Dictionary = await _snapshot(prefix + "_after")
	_save(prefix + "_receipt.bin", lab.raw_receipt)
	var input := {}
	for key in ["water", "sediment", "momentum_x", "momentum_z"]: input[key] = before[key].to_float32_array()
	input.old_bed = before.sand.to_float32_array()
	input.new_bed = after.sand.to_float32_array()
	var old_sand: PackedFloat32Array = before.sand.to_float32_array()
	var sand: PackedFloat32Array = after.sand.to_float32_array()
	var rock: PackedFloat32Array = before.rock.to_float32_array()
	var obstacle := PackedFloat32Array()
	obstacle.resize(size * size)
	for i in size * size:
		input.old_bed[i] += rock[i]
		input.new_bed[i] += rock[i]
		obstacle[i] = float(before.obstacle[i]) / 255.0
	input.obstacle = obstacle
	var expected := PackedByteArray()
	expected.resize(size * size * 32)
	expected.fill(0)
	for i in size * size:
		for slot in 7: expected.encode_float(i * 32 + slot * 4, input[["old_bed", "new_bed", "water", "sediment", "momentum_x", "momentum_z", "obstacle"][slot]][i])
	bridge_input.clear()
	RenderingServer.call_on_render_thread(_read_bridge)
	while bridge_input.is_empty(): await process_frame
	_save(prefix + "_gpu_bridge.bin", bridge_input)
	_save(prefix + "_expected_bridge.bin", expected)
	var exact_bridge: bool = expected == bridge_input
	var oracle: Dictionary = Reference.build(input, size, 0.125)
	var distribution := true
	var closure := true
	var right_unchanged := true
	var maximums := {}
	var budgets := {}
	var emerged_dry := true
	var actual_donor := 0.0
	var touched := PackedInt32Array()
	for i in size * size:
		if input.water[i] > 0.001 and obstacle[i] < 0.5: touched.append(i)
	for slot in 4:
		var key: String = ["water", "sediment", "momentum_x", "momentum_z"][slot]
		var actual: PackedFloat32Array = after[key].to_float32_array()
		var maximum := 0.0
		for i in size * size:
			var error: float = absf(actual[i] - oracle[key][i])
			maximum = maxf(maximum, error)
			distribution = distribution and is_finite(actual[i]) and error <= Protocol.cell_budget(input[key][i], oracle[key][i]) and (slot >= 2 or actual[i] >= 0.0)
			if name in ["obstacle_pools", "dry_pools"] and i % size > size / 2: right_unchanged = right_unchanged and actual[i] == input[key][i]
			if slot == 0 and obstacle[i] < 0.5 and input.water[i] > 0.001 and input.new_bed[i] > input.old_bed[i]:
				actual_donor += (input.water[i] - actual[i]) * 0.015625
				if receipt.get("capacity_status", 0) == 0 and input.new_bed[i] >= input.old_bed[i] + input.water[i]: emerged_dry = emerged_dry and actual[i] <= 0.0001
		var budget := Protocol.volume_budget(input[key], actual, 0.015625, touched)
		var loss: float = 0.0 if slot < 2 else after.water_receipt.decode_float(24 if slot == 2 else 28)
		var integral_error: float = absf(_sum(actual) + loss - _sum(input[key]))
		closure = closure and integral_error <= budget.edit_m3
		budgets[key] = {"error": integral_error, "budget": budget.edit_m3, "dry_loss": loss, "unit": "m3" if slot < 2 else "m4/s"}
		maximums[key] = maximum
		_save(prefix + "_oracle_f64_" + key + ".bin", oracle[key].to_byte_array())
	var capacity_status := 0
	for component in oracle.components: capacity_status = maxi(capacity_status, component.capacity_status)
	var water_budget: float = budgets.water.budget
	var receipt_matches: bool = (receipt.get("status") == 1 and receipt.get("capacity_status") == capacity_status and
		absf(receipt.get("displaced_water_m3", -1.0) - actual_donor) <= Protocol.reduction_budget(size * size, absf(actual_donor)) and
		absf(receipt.get("displaced_water_m3", -1.0) - oracle.displaced_water_m3) <= water_budget and
		absf(receipt.get("retained_water_m3", -1.0) - oracle.retained_water_m3) <= water_budget)
	var actual_sand := 0.0
	for i in size * size: actual_sand += (sand[i] - old_sand[i]) * 0.015625
	var sand_closed: bool = absf(lab.domain.tool_inventory_m3 - stock + actual_sand) <= Protocol.reduction_budget(size * size, absf(actual_sand))
	var immutable := true
	for key in ["rock", "compaction", "wetness", "obstacle", "flux"]: immutable = immutable and before[key] == after[key]
	var published: bool = after.water == after.published_water and after.sand == after.published_sand
	var ok: bool = exact_bridge and distribution and closure and right_unchanged and receipt_matches and sand_closed and immutable and published and emerged_dry
	rows.append({"case": name, "grid": size, "pass": ok, "gpu_input_exact": exact_bridge,
		"fast_path_used": after.water_receipt.decode_u32(108),
		"distribution": distribution, "closure": budgets, "right_pool_unchanged": right_unchanged,
		"receipt_matches": receipt_matches, "receipt": receipt, "sand_inventory_closed": sand_closed,
		"immutable_fields": immutable, "published": published, "emerged_dry": emerged_dry,
		"max_errors": maximums, "effective_profile": lab.effective_profile})
	_write(false, "running")
	await lab.advance_ticks(3)
	if not lab.last_error.is_empty(): return
	var continued: Dictionary = await _snapshot(prefix + "_tick003")
	var water: PackedFloat32Array = continued.water.to_float32_array()
	var qx: PackedFloat32Array = continued.momentum_x.to_float32_array()
	var qz: PackedFloat32Array = continued.momentum_z.to_float32_array()
	var finite := true
	var dry_momentum := true
	for i in water.size():
		finite = finite and is_finite(water[i]) and water[i] >= 0.0 and is_finite(qx[i]) and is_finite(qz[i])
		if water[i] <= 0.001: dry_momentum = dry_momentum and qx[i] == 0.0 and qz[i] == 0.0
	var relative := absf(_sum(water) - _sum(input.water)) / maxf(_sum(input.water), 1e-12)
	var stable: bool = finite and dry_momentum and relative <= 0.005 and lab.solver.overload_events == 0 and continued.water == continued.published_water
	rows.append({"case": name + "_continue_3ticks", "grid": size, "pass": stable,
		"actual_sim_s": lab.completed_ticks / 30.0, "finite_nonnegative": finite, "dry_momentum_zero": dry_momentum,
		"water_relative_error": relative, "max_substeps": lab.solver.max_substeps_used,
		"scope": "existing water subsolver, erosion disabled"})
	_write(false, "running")

func _run() -> void:
	var failure := ""
	var cases := ["rock_slope", "suspended_flow", "obstacle_pools", "dry_pools", "partial_capacity", "deep", "dry", "small", "dig", "dry_threshold_flow", "row_hole", "row_obstacle", "ring_pool", "multiple_holes"]
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--case-filter="):
			var selected := arg.trim_prefix("--case-filter=")
			cases = [selected] if selected in cases else []
	for size in [64, 256]:
		lab = load("res://tests/edit_validation/edit_gpu_water_" + ("numeric" if size == 64 else "brush") + "_lab.tscn").instantiate()
		root.add_child(lab)
		while not lab.ready_for_ticks and lab.last_error.is_empty(): await process_frame
		if not lab.last_error.is_empty():
			failure = lab.last_error
			break
		for name in cases:
			await _case(name, size)
			if not lab.last_error.is_empty():
				failure = lab.last_error
				break
		await lab.shutdown()
		lab.queue_free()
		await process_frame
		lab = null
		if not failure.is_empty(): break
	var ok := failure.is_empty() and not cases.is_empty() and rows.size() == cases.size() * 4
	for row in rows: ok = ok and row.pass
	_write(ok, failure)
	if lab != null:
		await lab.shutdown()
		lab.queue_free()
	finished = true
	print("WATER_BRIDGE_COMPLETE pass=%s rows=%d" % [str(ok), rows.size()])
	quit(0 if ok else 1)



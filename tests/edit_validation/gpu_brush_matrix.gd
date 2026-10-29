extends SceneTree

const Protocol = preload("res://scripts/simulation/edit_validation/edit_protocol.gd")
const Domain = preload("res://scripts/simulation/sand_water_domain.gd")
const Queue = preload("res://scripts/sand/tool_command_queue.gd")
var output := ""
var lab: Node3D
var rows := []
var finished := false
var started := 0
var sequence := 0
var failure := ""
var wire_result := PackedByteArray()
var counter_setup_done := false
var local_dispatch := false
var micro_only := false

func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--local-dispatch": local_dispatch = true
		if arg == "--micro-only": micro_only = true
		if arg.begins_with("--output="):
			output = arg.trim_prefix("--output=")
	started = Time.get_ticks_msec()
	call_deferred("_watchdog")
	call_deferred("_run")

func _watchdog() -> void:
	while not finished:
		if Time.get_ticks_msec() - started > 150000:
			_write_report(false, "matrix timeout")
			quit(1)
			return
		await process_frame

func _write_report(ok: bool, error: String = "") -> void:
	var file := FileAccess.open(output.path_join("gpu_brush_matrix.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass": ok, "rows": rows, "error": error,
		"local_dispatch": local_dispatch,
		"micro_only": micro_only,
		"scope": "S00-S07 numeric/brush matrix; no performance or restore verdict"}, "\t"))

func _save(path: String, data: PackedByteArray) -> void:
	var file := FileAccess.open(output.path_join(path), FileAccess.WRITE)
	file.store_buffer(data)

func _hashes(fields: Dictionary) -> Dictionary:
	var hashes := {}
	for key in fields:
		var context := HashingContext.new()
		context.start(HashingContext.HASH_SHA256)
		context.update(fields[key])
		hashes[key] = context.finish().hex_encode()
	return hashes

func _command(id: int, kind: StringName = &"remove_sand", radius: float = 0.75,
		amount: float = 0.01, start: Vector3 = Vector3.ZERO,
		end: Vector3 = Vector3.INF, strength: float = 1.0) -> Dictionary:
	var transform := {"position_m": start}
	if end != Vector3.INF:
		transform.end_position_m = end
	return {"domain_id": lab.domain.domain_id, "generation": lab.generation,
		"sim_tick": lab.completed_ticks, "command_id": id, "kind": kind,
		"shape": &"circle" if end == Vector3.INF else &"swept_segment",
		"transform": transform, "radius_m": radius, "strength": strength,
		"amount_m3": amount, "seed": 101}

func _encoded(command: Dictionary) -> Dictionary:
	var result := command.duplicate(true)
	var p: Vector3 = command.transform.position_m
	result.transform.position_m = [p.x, p.y, p.z]
	if command.transform.has("end_position_m"):
		p = command.transform.end_position_m
		result.transform.end_position_m = [p.x, p.y, p.z]
	return result

func _reference() -> SandWaterDomain:
	var domain := Domain.new(lab.profile.grid_size, 0.125)
	domain.restore(lab.domain.snapshot())
	domain.generation = lab.generation
	return domain

func _stroke(case_id: String, command: Dictionary, reference: SandWaterDomain,
		queue: ToolCommandQueue, before: Dictionary, cumulative_budget: float) -> Dictionary:
	sequence += 1
	var prefix := "%03d_%s_%d" % [sequence, case_id, lab.profile.grid_size]
	var cpu_error: StringName = queue.submit(command)
	var cpu_results: Array[Dictionary] = queue.apply_due_commands(lab.completed_ticks)
	if not cpu_error.is_empty() or cpu_results.is_empty():
		failure = "CPU reference admission " + case_id + ": " + String(cpu_error)
		return {}
	_save(prefix + "_wire.bin", Protocol.encode(command, lab.ticket_id + 1, lab.solver.state_revision,
		lab.profile.grid_size, 0.125, 0, lab.domain.tool_inventory_m3))
	var gpu: Dictionary = await lab.apply_gpu_command(command)
	if not lab.last_error.is_empty():
		failure = lab.last_error
		return {}
	var after: Dictionary = await lab.snapshot_state()
	_save(prefix + "_gpu_sand.bin", after.sand)
	_save(prefix + "_cpu_sand.bin", reference.sand.to_byte_array())
	_save(prefix + "_receipt.bin", lab.raw_receipt)
	var old_sand: PackedFloat32Array = before.sand.to_float32_array()
	var sand: PackedFloat32Array = after.sand.to_float32_array()
	var within_budget := true
	var outside_unchanged := true
	var touched := {}
	for i in cpu_results[0].dirty_cells:
		touched[i] = true
	var maximum := 0.0
	var actual := 0.0
	for i in sand.size():
		var difference := absf(sand[i] - reference.sand[i])
		maximum = maxf(maximum, difference)
		within_budget = within_budget and difference <= Protocol.cell_budget(old_sand[i], reference.sand[i]) and is_finite(sand[i]) and sand[i] >= 0.0
		if not touched.has(i):
			outside_unchanged = outside_unchanged and old_sand[i] == sand[i]
		actual += (sand[i] - old_sand[i]) * 0.015625
	var immutable := true
	for key in before:
		if key != "sand":
			immutable = immutable and before[key] == after[key]
	var budget := Protocol.volume_budget(old_sand, sand, 0.015625, PackedInt32Array(touched.keys()))
	cumulative_budget += budget.edit_m3
	var cpu_applied: bool = cpu_results[0].status == &"applied"
	var gpu_applied: bool = gpu.get("status", -1) == 1
	var closure: bool = absf(absf(actual) - float(gpu.get("actual_sand_m3", 0.0))) <= budget.reduction_m3
	var bucket_error: float = absf(lab.domain.tool_inventory_m3 - reference.tool_inventory_m3)
	var expected_chunks := {}
	var per: int = lab.profile.grid_size / 32
	for i in cpu_results[0].dirty_cells:
		var x: int = i % lab.profile.grid_size
		var z: int = i / lab.profile.grid_size
		var chunk: int = (z / 32) * per + x / 32
		expected_chunks[chunk] = true
		if x % 32 == 0 and x / 32 > 0: expected_chunks[chunk - 1] = true
		if z % 32 == 0 and z / 32 > 0: expected_chunks[chunk - per] = true
		if x % 32 == 0 and z % 32 == 0 and x / 32 > 0 and z / 32 > 0: expected_chunks[chunk - per - 1] = true
	var mask_ok := true
	if gpu_applied:
		for chunk in per * per:
			var bit: bool = (int(gpu.dirty_mask[chunk / 32]) & (1 << (chunk % 32))) != 0
			mask_ok = mask_ok and bit == expected_chunks.has(chunk)
	var status_ok: bool = cpu_applied == gpu_applied
	var pass_row: bool = status_ok and within_budget and outside_unchanged and immutable and closure and bucket_error <= cumulative_budget and mask_ok
	rows.append({"case": case_id, "grid": lab.profile.grid_size, "command": _encoded(command),
		"pass": pass_row, "status_matches": status_ok, "gpu": gpu,
		"max_sand_difference_m": maximum, "outside_unchanged": outside_unchanged,
		"legacy_fields_immutable": immutable, "receipt_closure": closure,
		"bucket_error_m3": bucket_error, "cumulative_budget_m3": cumulative_budget,
		"dirty_mask_matches": mask_ok, "budget": budget, "after_hashes": _hashes(after),
		"initial_stock_m3": reference.tool_inventory_m3 - float(cpu_results[0].sand_delta_m3),
		"actual_delta_m3": actual, "prefix": prefix})
	_write_report(false, "running")
	return {"fields": after, "budget": cumulative_budget}

func _invalid(case_id: String, command: Dictionary, expected: String, before: Dictionary) -> void:
	var stock: float = lab.domain.tool_inventory_m3
	var result: Dictionary = await lab.apply_gpu_command(command)
	var after: Dictionary = await lab.snapshot_state()
	var identical := true
	for key in before:
		identical = identical and before[key] == after[key]
	rows.append({"case": case_id, "grid": lab.profile.grid_size, "pass": result.get("error") == expected and identical and stock == lab.domain.tool_inventory_m3,
		"result": result, "expected": expected, "fields_identical": identical})
	_write_report(false, "running")

func _render_wire(data: PackedByteArray) -> void:
	if not lab.solver.dispatch_sand_command(data, _wire_callback):
		call_deferred("_wire_failed")

func _wire_failed() -> void:
	failure = "raw guard dispatch failed"

func _wire_callback(data: PackedByteArray) -> void:
	call_deferred("_wire_record", data)

func _wire_record(data: PackedByteArray) -> void:
	wire_result = data

func _large_counters_render() -> void:
	lab.solver.owner_generation = lab.generation
	lab.solver.state_revision = 4294967295
	call_deferred("_large_counters_ready")

func _large_counters_ready() -> void:
	counter_setup_done = true

func _raw_guard(case_id: String, offset: int, expected_error: int, before: Dictionary) -> void:
	var command := _command(999)
	var revision: int = lab.solver.state_revision
	var data := Protocol.encode(command, lab.ticket_id + 1, revision, lab.profile.grid_size, 0.125, 0, lab.domain.tool_inventory_m3)
	if offset == 16:
		data.encode_s64(offset, lab.generation - 1)
	elif offset == 32:
		data.encode_s64(offset, revision - 1)
	else:
		data.encode_float(offset, NAN if offset == 64 else INF)
	wire_result = PackedByteArray()
	RenderingServer.call_on_render_thread(_render_wire.bind(data))
	while wire_result.is_empty() and failure.is_empty(): await process_frame
	var receipt := Protocol.decode_receipt(wire_result)
	var after: Dictionary = await lab.snapshot_state()
	var same := true
	for key in before: same = same and before[key] == after[key]
	_save("guard_%d_%s_command.bin" % [lab.profile.grid_size, case_id], data)
	_save("guard_%d_%s_receipt.bin" % [lab.profile.grid_size, case_id], wire_result)
	rows.append({"case": case_id, "grid": lab.profile.grid_size, "pass": receipt.get("ok", false) and receipt.status == 2 and receipt.error_code == expected_error and same and lab.solver.state_revision == revision,
		"receipt": receipt, "authority_identical": same, "revision_unchanged": lab.solver.state_revision == revision})
	_write_report(false, "running")

func _mixed_legacy(command: Dictionary, reference: SandWaterDomain, queue: ToolCommandQueue) -> Dictionary:
	var before: Dictionary = await lab.snapshot_state()
	var error: StringName = queue.submit(command)
	var cpu: Array[Dictionary] = queue.apply_due_commands(lab.completed_ticks)
	var result: Dictionary = await lab.apply_legacy_command(command)
	var after: Dictionary = await lab.snapshot_state()
	var sand: PackedFloat32Array = after.sand.to_float32_array()
	var old_sand: PackedFloat32Array = before.sand.to_float32_array()
	var sand_ok := true
	var comp_image := Image.create_from_data(lab.profile.grid_size, lab.profile.grid_size, false, Image.FORMAT_RF, reference.compaction.to_byte_array())
	comp_image.convert(Image.FORMAT_RH)
	var expected_compaction := comp_image.get_data()
	var comp_ok: bool = after.compaction == expected_compaction
	var maximum := 0.0
	for i in sand.size():
		var difference := absf(sand[i] - reference.sand[i])
		maximum = maxf(maximum, difference)
		sand_ok = sand_ok and difference <= Protocol.cell_budget(old_sand[i], reference.sand[i])
	var name := "mixed_" + String(command.kind)
	_save("%s_%d_sand.bin" % [name, lab.profile.grid_size], after.sand)
	_save("%s_%d_compaction.bin" % [name, lab.profile.grid_size], after.compaction)
	_save("%s_%d_cpu_compaction_R16.bin" % [name, lab.profile.grid_size], expected_compaction)
	rows.append({"case": name, "grid": lab.profile.grid_size, "pass": error.is_empty() and cpu.size() == 1 and result.has("results") and sand_ok and comp_ok and lab.shadow_sand_revision == lab.solver.state_revision,
		"sand_within_budget": sand_ok, "compaction_Godot_R16_exact": comp_ok, "max_sand_difference_m": maximum,
		"shadow_revision": lab.shadow_sand_revision, "gpu_revision": lab.solver.state_revision})
	_write_report(false, "running")
	return after

func _run() -> void:
	if output.is_empty():
		quit(1)
		return
	root.size = Vector2i(960, 540)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	for size in [64, 256]:
		lab = load("res://tests/edit_validation/edit_gpu_" + ("numeric" if size == 64 else "brush") + "_lab.tscn").instantiate()
		lab.local_dispatch = local_dispatch
		root.add_child(lab)
		while not lab.ready_for_ticks and lab.last_error.is_empty(): await process_frame
		if not lab.last_error.is_empty():
			failure = lab.last_error
			break
		var initial: Dictionary = await lab.snapshot_state()
		for key in initial: _save("initial_%d_%s.bin" % [size, key], initial[key])
		if micro_only:
			await _micro_strokes(size)
			await lab.shutdown()
			lab.queue_free()
			await process_frame
			lab = null
			continue
		for pattern in ["uniform", "thin_mixed", "empty"]:
			var values := PackedFloat32Array()
			values.resize(size * size)
			for i in values.size():
				values[i] = 0.4 if pattern == "uniform" else (0.0 if pattern == "empty" else (0.00001 if i % 3 == 0 else 0.0002 if i % 3 == 1 else 0.02))
			await lab.seed_test_state(values, 2.0)
			var reference := _reference()
			var queue := Queue.new(reference)
			var state: Dictionary = await lab.snapshot_state()
			_save("seed_%d_%s_sand.bin" % [size, pattern], state.sand)
			var budget := 0.0
			var id := 0
			for radius in [0.25, 0.75, 4.0]:
				for kind in [&"remove_sand", &"place_sand"]:
					id += 1
					var result: Dictionary = await _stroke(pattern + "_radius_" + str(radius), _command(id, kind, radius, 0.01), reference, queue, state, budget)
					if result.is_empty(): break
					state = result.fields
					budget = result.budget
			if not failure.is_empty(): break
			for shape_case in ["swept", "degenerate", "edge", "corner", "zero", "insufficient", "outside"]:
				id += 1
				var half: float = size * 0.125 * 0.5
				var command := _command(id)
				match shape_case:
					"swept": command = _command(id, &"remove_sand", 0.75, 0.02, Vector3(-2,0,-1), Vector3(2,0,1))
					"degenerate": command = _command(id, &"remove_sand", 0.75, 0.02, Vector3.ZERO, Vector3.ZERO)
					"edge": command = _command(id, &"remove_sand", 0.75, 0.02, Vector3(half,0,0))
					"corner": command = _command(id, &"place_sand", 0.75, 0.02, Vector3(-half,0,-half))
					"zero": command.strength = 0.0
					"insufficient": command = _command(id, &"place_sand", 0.75, 100.0)
					"outside": command.transform.position_m = Vector3(half + 5, 0, half + 5)
				var result: Dictionary = await _stroke(pattern + "_" + shape_case, command, reference, queue, state, budget)
				if result.is_empty(): break
				state = result.fields
				budget = result.budget
			if not failure.is_empty(): break
			await _invalid(pattern + "_duplicate_id", _command(id), "invalid_command", state)
			var invalid := _command(id + 1)
			invalid.generation -= 1
			await _invalid(pattern + "_old_generation", invalid, "inactive_generation", state)
			for field in ["radius_m", "strength", "amount_m3"]:
				invalid = _command(id + 1)
				invalid[field] = NAN
				await _invalid(pattern + "_nan_" + field, invalid, "invalid_command", state)
			invalid = _command(id + 1)
			invalid.transform.position_m = Vector3(INF,0,0)
			await _invalid(pattern + "_inf_position", invalid, "invalid_command", state)
			invalid = _command(id + 1)
			invalid.sim_tick = 1
			await _invalid(pattern + "_future_due_executor", invalid, "backend_unavailable", state)
			await lab.advance_ticks(1)
			state = await lab.snapshot_state()
			invalid = _command(id + 1)
			invalid.sim_tick -= 1
			await _invalid(pattern + "_stale_tick", invalid, "stale_tick", state)
		if not failure.is_empty(): break
		var flat := PackedFloat32Array()
		flat.resize(size * size)
		flat.fill(0.0)
		for stock in [0.0, 0.01]:
			await lab.seed_test_state(flat, stock)
			var reference := _reference()
			var queue := Queue.new(reference)
			var state: Dictionary = await lab.snapshot_state()
			var budget := 0.0
			for id in range(1, 5):
				var amount := 0.0000003 if stock == 0.0 else 0.01 if id == 1 else 0.0000006
				var result: Dictionary = await _stroke("critical_stock_" + str(stock), _command(id, &"place_sand", 0.75, amount), reference, queue, state, budget)
				if result.is_empty(): break
				state = result.fields
				budget = result.budget
		flat.fill(0.4)
		await lab.seed_test_state(flat, 2.0)
		var reference := _reference()
		var queue := Queue.new(reference)
		var state: Dictionary = await lab.snapshot_state()
		var result: Dictionary = await _stroke("mixed_gpu_dig", _command(1, &"remove_sand", 0.75, 0.02), reference, queue, state, 0.0)
		if result.is_empty(): break
		state = await _mixed_legacy(_command(2, &"smooth", 0.75, 0.01, Vector3.ZERO, Vector3.INF, 0.4), reference, queue)
		state = await _mixed_legacy(_command(3, &"compact", 0.75, 0.01, Vector3.ZERO, Vector3.INF, 0.8), reference, queue)
		result = await _stroke("mixed_gpu_place", _command(4, &"place_sand", 0.75, 0.015), reference, queue, state, result.budget)
		if result.is_empty(): break
		state = result.fields
		await _raw_guard("GPU_old_generation", 16, 5, state)
		await _raw_guard("GPU_old_revision", 32, 7, state)
		await _raw_guard("GPU_nan_radius", 64, 1, state)
		await _raw_guard("GPU_inf_amount", 72, 1, state)
		# Transport-only boundary injection, not a claim of elapsed physical ticks.
		await lab.seed_test_state(flat, 2.0)
		lab.generation = 4294967297
		lab.domain.generation = lab.generation
		lab.completed_ticks = 4294967297
		lab.domain.sim_tick = lab.completed_ticks
		lab.ticket_id = 4294967297
		counter_setup_done = false
		RenderingServer.call_on_render_thread(_large_counters_render)
		while not counter_setup_done: await process_frame
		reference = _reference()
		queue = Queue.new(reference)
		state = await lab.snapshot_state()
		result = await _stroke("int64_identity_revision_carry", _command(9007199254740993), reference, queue, state, 0.0)
		if result.is_empty(): break
		var identity_ok: bool = lab.receipt.command_id == 9007199254740993 and lab.receipt.generation == 4294967297 and lab.receipt.ticket_id == 4294967298 and lab.receipt.applied_tick == 4294967297 and lab.receipt.output_revision == 4294967296
		rows.append({"case": "int64_roundtrip_exact", "grid": size, "pass": identity_ok, "counter_test_only": true})
		await lab.shutdown()
		lab.queue_free()
		await process_frame
		lab = null
	var ok: bool = failure.is_empty() and rows.size() > 0
	for row in rows: ok = ok and row.pass
	_write_report(ok, failure)
	if lab != null:
		await lab.shutdown()
		lab.queue_free()
	finished = true
	print("GPU_MATRIX_COMPLETE pass=%s rows=%d" % [str(ok), rows.size()])
	quit(0 if ok else 1)

func _micro_strokes(size: int) -> void:
	var values := PackedFloat32Array()
	values.resize(size * size)
	for height in [0.4, 8.0]:
		for radius in [0.25, 0.75, 4.0]:
			values.fill(height)
			await lab.seed_test_state(values, 2.0)
			var reference := _reference()
			var queue := Queue.new(reference)
			var state: Dictionary = await lab.snapshot_state()
			var budget := 0.0
			var id := 0
			for amount in [0.0000003, 0.0000006, 0.00001, 0.01]:
				id += 1
				var result: Dictionary = await _stroke("micro_height_%s_radius_%s_amount_%s" % [str(height), str(radius), str(amount)],
					_command(id, &"place_sand", radius, amount), reference, queue, state, budget)
				if result.is_empty(): return
				state = result.fields
				budget = result.budget

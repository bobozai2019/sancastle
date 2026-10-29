extends SceneTree

const Reference = preload("res://scripts/simulation/edit_validation/water_displacement_reference.gd")
const Protocol = preload("res://scripts/simulation/edit_validation/edit_protocol.gd")
var output := ""
var lab: Node3D
var rows := []
var extras := {}
var finished := false
var started := 0
var serial := 0

func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	started = Time.get_ticks_msec()
	call_deferred("_watchdog")
	call_deferred("_run")

func _watchdog() -> void:
	while not finished:
		if Time.get_ticks_msec() - started > 150000:
			_write(false, "transaction timeout")
			quit(1)
			return
		await process_frame

func _write(ok: bool, error := "") -> void:
	var file := FileAccess.open(output.path_join("water_transaction_probe.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass": ok, "rows": rows, "error": error,
		"scope": "native sand/water transaction, forensic readbacks; no performance verdict"}, "\t"))

func _save(name: String, bytes: PackedByteArray) -> void:
	var file := FileAccess.open(output.path_join(name), FileAccess.WRITE)
	file.store_buffer(bytes)

func _read_extras(forensic: bool) -> void:
	if forensic:
		for key in ["rock", "sand", "water", "momentum_x", "momentum_z", "sediment", "wetness", "compaction", "obstacle", "flux"]:
			lab.solver.request_data(key, _on_extra.bind(key))
	lab.solver.rd.texture_get_data_async(lab.solver.published_sand, 0, _on_extra.bind("published_sand"))
	lab.solver.rd.texture_get_data_async(lab.solver.published_water, 0, _on_extra.bind("published_water"))
	lab.solver.rd.buffer_get_data_async(lab.solver.water_receipt, _on_extra.bind("water_receipt"))

func _on_extra(bytes: PackedByteArray, label: String) -> void:
	call_deferred("_record_extra", bytes, label)

func _record_extra(bytes: PackedByteArray, label: String) -> void: extras[label] = bytes

func _snapshot(label: String, forensic := false) -> Dictionary:
	var state: Dictionary = {} if forensic else await lab.snapshot_state()
	extras.clear()
	RenderingServer.call_on_render_thread(_read_extras.bind(forensic))
	while extras.size() < (13 if forensic else 3): await process_frame
	for key in extras: state[key] = extras[key]
	for key in state: _save(label + "_" + key + ".bin", state[key])
	return state

func _command(id: int, amount: float) -> Dictionary:
	return {"domain_id": lab.domain.domain_id, "generation": lab.generation,
		"sim_tick": lab.completed_ticks, "command_id": id, "kind": &"place_sand", "shape": &"circle",
		"transform": {"position_m": Vector3.ZERO}, "radius_m": 0.75, "strength": 1.0,
		"amount_m3": amount, "seed": 101}

func _sum(values) -> float:
	var sum := 0.0
	for value in values: sum += value * 0.015625
	return sum

func _pair(amount: float, local: bool) -> void:
	serial += 1
	var prefix := "pair_%d_%d_%s" % [serial, lab.profile.grid_size, str(local)]
	lab.local_dispatch = local
	await lab.reset_domain()
	lab.water_policy = 0
	var before: Dictionary = await _snapshot(prefix + "_before_B")
	var legacy: Dictionary = await lab.apply_gpu_command(_command(1, amount))
	if not lab.last_error.is_empty(): return
	var b: Dictionary = await _snapshot(prefix + "_after_B")
	_save(prefix + "_receipt_B.bin", lab.raw_receipt)
	await lab.reset_domain()
	lab.water_policy = 1
	var c_before: Dictionary = await _snapshot(prefix + "_before_C")
	var command := _command(1, amount)
	_save(prefix + "_command_C.bin", Protocol.encode(command, lab.ticket_id + 1, lab.solver.state_revision,
		lab.profile.grid_size, 0.125, 1, lab.domain.tool_inventory_m3))
	var result: Dictionary = await lab.apply_gpu_command(command)
	if not lab.last_error.is_empty(): return
	var c: Dictionary = await _snapshot(prefix + "_after_C")
	_save(prefix + "_receipt_C.bin", lab.raw_receipt)
	var seed_equal := true
	for key in before:
		if key != "water_receipt": seed_equal = seed_equal and before[key] == c_before[key]
	var same_sand: bool = b.sand == c.sand and b.published_sand == c.published_sand
	var immutable := true
	for key in ["rock", "wetness", "compaction", "obstacle", "flux"]: immutable = immutable and b[key] == c[key]
	var fields := {}
	for key in ["water", "sediment", "momentum_x", "momentum_z"]: fields[key] = before[key].to_float32_array()
	fields.old_bed = before.sand.to_float32_array()
	fields.new_bed = b.sand.to_float32_array()
	var rock: PackedFloat32Array = before.rock.to_float32_array()
	var obstacle := PackedFloat32Array()
	obstacle.resize(rock.size())
	for i in rock.size():
		fields.old_bed[i] += rock[i]
		fields.new_bed[i] += rock[i]
		obstacle[i] = float(before.obstacle[i]) / 255.0
	fields.obstacle = obstacle
	var oracle: Dictionary = Reference.build(fields, lab.profile.grid_size, 0.125)
	var distribution := true
	var max_errors := {}
	var closure := true
	var water_budget := 0.0
	for key in ["water", "sediment", "momentum_x", "momentum_z"]:
		var actual: PackedFloat32Array = c[key].to_float32_array()
		var maximum := 0.0
		for i in actual.size():
			maximum = maxf(maximum, absf(actual[i] - oracle[key][i]))
			distribution = distribution and is_finite(actual[i]) and absf(actual[i] - oracle[key][i]) <= Protocol.cell_budget(fields[key][i], oracle[key][i])
			if key in ["water", "sediment"]: distribution = distribution and actual[i] >= 0.0
		max_errors[key] = maximum
		var touched := PackedInt32Array()
		for i in actual.size():
			if fields.water[i] > 0.001 and obstacle[i] < 0.5: touched.append(i)
		var budget := Protocol.volume_budget(fields[key], actual, 0.015625, touched)
		if key == "water": water_budget = budget.edit_m3
		closure = closure and absf(_sum(actual) - _sum(fields[key])) <= budget.edit_m3
		_save(prefix + "_oracle_f64_" + key + ".bin", oracle[key].to_byte_array())
	var published: bool = c.water == c.published_water and c.sand == c.published_sand
	var dry := true
	var emerged := 0
	var h: PackedFloat32Array = c.water.to_float32_array()
	for i in h.size():
		if fields.new_bed[i] >= fields.old_bed[i] + fields.water[i]:
			emerged += 1
			dry = dry and h[i] <= 0.0001
	var ok: bool = (legacy.get("status") == 1 and result.get("status") == 1 and seed_equal and same_sand and immutable and distribution and closure and published and dry and
		absf(result.displaced_water_m3 - oracle.displaced_water_m3) <= water_budget and lab.publish_us >= lab.settle_us)
	rows.append({"case": "paired_native_B_C", "prefix": prefix, "grid": lab.profile.grid_size, "local": local,
		"amount_m3": amount, "pass": ok, "seed_equal": seed_equal, "same_sand": same_sand,
		"immutable_fields": immutable, "distribution": distribution, "closure": closure,
		"published_complete": published, "emerged_cells": emerged, "emerged_dry": dry,
		"max_errors": max_errors, "receipt": result, "shader_metadata": lab.shader_metadata,
		"actual_input_shape": "existing weighted circle, not flat cap"})
	_write(false, "running")

func _negative(transport: bool) -> void:
	await lab.reset_domain()
	lab.water_policy = 1
	var prefix := "%s_%d" % ["transport" if transport else "water_audit", lab.profile.grid_size]
	var before: Dictionary = await _snapshot(prefix + "_before")
	var revision: int = lab.solver.state_revision
	var stock: float = lab.domain.tool_inventory_m3
	lab.expect_transport_failure = transport
	RenderingServer.call_on_render_thread(_inject.bind(transport))
	var result: Dictionary = await lab.apply_gpu_command(_command(1, 0.48))
	# Read-only forensic path never makes a failed backend ready again.
	var after: Dictionary = await _snapshot(prefix + "_after", transport)
	var same := true
	for key in before:
		if key != "water_receipt": same = same and before[key] == after[key]
	var status_ok: bool = lab.last_error == "GPU command dispatch failed" if transport else result.get("status") == 2 and result.get("error_code") == 7
	var ok: bool = same and status_ok and revision == lab.solver.state_revision and stock == lab.domain.tool_inventory_m3 and lab.reserved_m3 == 0.0
	_save(prefix + "_main_receipt.bin", lab.raw_receipt)
	rows.append({"case": prefix, "pass": ok, "authority_and_display_unchanged": same,
		"stock_unchanged": stock == lab.domain.tool_inventory_m3, "revision_unchanged": revision == lab.solver.state_revision,
		"reservation_released": lab.reserved_m3 == 0.0, "result": result,
		"injection": "after sand+water commit before receipt" if transport else "delete candidate water before GPU audit"})
	_write(false, "running")

func _inject(transport: bool) -> void:
	if transport: lab.solver.inject_receipt_failure_once = true
	else: lab.solver.inject_water_loss_once = true

func _run() -> void:
	for size in [64, 256]:
		lab = load("res://tests/edit_validation/edit_gpu_water_" + ("numeric" if size == 64 else "brush") + "_lab.tscn").instantiate()
		root.add_child(lab)
		while not lab.ready_for_ticks and lab.last_error.is_empty(): await process_frame
		if not lab.last_error.is_empty(): break
		for local in [false, true]:
			for amount in [0.12, 0.48]:
				await _pair(amount, local)
				if not lab.last_error.is_empty(): break
		if not lab.last_error.is_empty(): break
		await _negative(false)
		await _negative(true)
		await lab.shutdown()
		lab.queue_free()
		await process_frame
		lab = null
	var ok := rows.size() == 12
	for row in rows: ok = ok and row.pass
	_write(ok, "" if lab == null else lab.last_error)
	if lab != null:
		await lab.shutdown()
		lab.queue_free()
	finished = true
	print("WATER_TRANSACTION_COMPLETE pass=%s rows=%d" % [str(ok), rows.size()])
	quit(0 if ok else 1)

extends SceneTree

const Reference = preload("res://scripts/simulation/edit_validation/water_displacement_reference.gd")
var checks := []
var output := ""

func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	call_deferred("_run")

func _state() -> Dictionary:
	var state := {}
	for key in ["old_bed", "new_bed", "water", "sediment", "momentum_x", "momentum_z", "obstacle"]:
		var values := PackedFloat32Array()
		values.resize(64 * 64)
		values.fill(0.12 if key == "water" else 0.0)
		state[key] = values
	return state

func _check(name: String, ok: bool, detail = null) -> void:
	checks.append({"name": name, "pass": ok, "detail": detail})

func _mass(values) -> float:
	var sum := 0.0
	for value in values: sum += value * 0.015625
	return sum

func _cap(state: Dictionary, height: float, center_x: int = 32) -> PackedInt32Array:
	var donor := PackedInt32Array()
	for z in 64:
		for x in 64:
			if Vector2((x + 0.5 - center_x) * 0.125, (z + 0.5 - 32) * 0.125).length() <= 0.75:
				var i := z * 64 + x
				state.new_bed[i] = height
				donor.append(i)
	return donor

func _save(label: String, state: Dictionary, candidate: Dictionary) -> void:
	for key in state:
		var file := FileAccess.open(output.path_join(label + "_before_" + key + ".bin"), FileAccess.WRITE)
		file.store_buffer(state[key].to_byte_array())
	for key in ["water", "sediment", "momentum_x", "momentum_z"]:
		var file := FileAccess.open(output.path_join(label + "_oracle_f64_" + key + ".bin"), FileAccess.WRITE)
		file.store_buffer(candidate[key].to_byte_array())

func _run() -> void:
	var state := _state()
	var candidate: Dictionary = Reference.build(state, 64, 0.125)
	_check("no_edit_identity", candidate.ok and candidate.water == PackedFloat64Array(Array(state.water)) and candidate.displaced_water_m3 == 0.0)
	for height in [0.2, 0.8]:
		state = _state()
		var donors := _cap(state, height)
		candidate = Reference.build(state, 64, 0.125)
		var dry := true
		for i in donors: dry = dry and candidate.water[i] <= 0.0001
		_check("cap_%s_dry_and_closed" % str(height), dry and absf(_mass(candidate.water) - _mass(state.water)) < 1e-10,
			{"components": candidate.components, "donor_cells": donors.size(), "displaced_m3": candidate.displaced_water_m3})
		_save("cap_" + str(height), state, candidate)
	state = _state()
	state.water.fill(0.0)
	_cap(state, 0.8)
	candidate = Reference.build(state, 64, 0.125)
	_check("dry_does_not_create_water_or_momentum", _mass(candidate.water) == 0.0 and _mass(candidate.momentum_x) == 0.0)
	state = _state()
	state.new_bed.fill(0.8)
	candidate = Reference.build(state, 64, 0.125)
	_check("zero_capacity_retains_water", candidate.water == PackedFloat64Array(Array(state.water)) and candidate.components[0].capacity_status == 1 and candidate.retained_water_m3 > 0.0)
	_save("zero_capacity", state, candidate)
	state = _state()
	for i in 4096:
		state.new_bed[i] = -0.2
	candidate = Reference.build(state, 64, 0.125)
	_check("dig_does_not_create_water", candidate.water == PackedFloat64Array(Array(state.water)) and candidate.displaced_water_m3 == 0.0)
	state = _state()
	state.sediment.fill(0.003)
	state.momentum_x.fill(0.024)
	state.momentum_z.fill(-0.012)
	_cap(state, 0.8)
	candidate = Reference.build(state, 64, 0.125)
	_check("suspended_sand_and_momentum_closed", absf(_mass(candidate.sediment) - _mass(state.sediment)) < 1e-10 and
		absf(_mass(candidate.momentum_x) + candidate.dry_momentum_loss[0] - _mass(state.momentum_x)) < 1e-10 and
		absf(_mass(candidate.momentum_z) + candidate.dry_momentum_loss[1] - _mass(state.momentum_z)) < 1e-10)
	_save("suspended_flow", state, candidate)
	for separation in ["obstacle", "dry"]:
		state = _state()
		for z in 64:
			state["obstacle" if separation == "obstacle" else "water"][z * 64 + 32] = 1.0 if separation == "obstacle" else 0.0
		_cap(state, 0.8, 16)
		candidate = Reference.build(state, 64, 0.125)
		var right_unchanged := true
		for z in 64:
			for x in range(33,64):
				right_unchanged = right_unchanged and candidate.water[z * 64 + x] == state.water[z * 64 + x]
		_check(separation + "_does_not_connect_pools", right_unchanged and candidate.components.size() == 2 and absf(_mass(candidate.water) - _mass(state.water)) < 1e-10)
		_save(separation, state, candidate)
	state = _state()
	state.water[0] = NAN
	candidate = Reference.build(state, 64, 0.125)
	_check("nan_state_rejected", not candidate.ok and candidate.error == "invalid_state")
	state = _state()
	state.sediment[0] = -0.1
	candidate = Reference.build(state, 64, 0.125)
	_check("negative_sediment_rejected", not candidate.ok)
	state = _state()
	var bad := PackedFloat64Array(Array(state.water))
	var donors := _cap(state, 0.8)
	for i in donors: bad[i] = 0.0
	_check("deleted_water_negative_control_detected", absf(_mass(bad) - _mass(state.water)) > 1e-7)
	var ok := true
	for check in checks: ok = ok and check.pass
	var file := FileAccess.open(output.path_join("water_reference_probe.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass": ok, "checks": checks, "scope": "independent float64 policy oracle; no GPU or continuous-time verdict"}, "\t"))
	print("WATER_REFERENCE_COMPLETE pass=%s checks=%d" % [str(ok), checks.size()])
	quit(0 if ok else 1)


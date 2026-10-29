extends "res://tests/edit_validation/velocity_probe.gd"

var combined_before := {}

func _init() -> void:
	candidate_policy = 3
	if "--combined-large" in OS.get_cmdline_user_args():
		command_amount_m3 = 0.48
		case_kinds = ["still", "swept", "dry", "clip", "dig"]
	super._init()

func _seed(size: int, kind: String) -> Dictionary:
	var fields := super._seed(size, kind)
	if kind == "dig":
		var sand := PackedFloat32Array()
		sand.resize(size * size); sand.fill(0.3)
		fields.sand = sand
	return fields

func _write(ok: bool, error := "") -> void:
	var file := FileAccess.open(output.path_join("combined_probe.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass": ok, "rows": rows, "error": error,
		"scope": "E compared with actual C then independent F64 velocity oracle; no performance"}, "\t"))

func _velocity_baseline(size: int, kind: String, command: Dictionary, _before: Dictionary, prefix: String) -> Dictionary:
	lab.water_policy = 1
	lab.signed_speed_m_s = 0.0
	var c_receipt: Dictionary = await lab.apply_gpu_command(command)
	_save(prefix + "_C_receipt.bin", lab.raw_receipt)
	var c: Dictionary = await _snapshot(prefix + "_C_after")
	if c_receipt.get("status") != 1:
		lab.last_error = "C baseline rejected"
	await lab.seed_test_fields(_seed(size, kind))
	command.generation = lab.generation
	command.sim_tick = lab.completed_ticks
	combined_before = await _snapshot(prefix + "_E_before")
	return c

func _combined_initial_equal(before: Dictionary) -> bool:
	for key in before:
		if key != "water_receipt" and before[key] != combined_before[key]: return false
	return true

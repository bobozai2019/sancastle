extends SceneTree

const Protocol = preload("res://scripts/simulation/edit_validation/edit_protocol.gd")
const Domain = preload("res://scripts/simulation/sand_water_domain.gd")
const Queue = preload("res://scripts/sand/tool_command_queue.gd")
var checks := []

func _init() -> void:
	call_deferred("_run")

func _check(name: String, ok: bool, detail: Variant = null) -> void:
	checks.append({"name": name, "pass": ok, "detail": detail})

func _run() -> void:
	var output := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			output = arg.trim_prefix("--output=")
	var command := {"domain_id": &"main_beach", "generation": 1,
		"sim_tick": 0, "command_id": 9007199254740993, "kind": &"remove_sand",
		"shape": &"swept_segment", "transform": {"position_m": Vector3(0.25, 0.0, -0.5),
		"end_position_m": Vector3(1.0, 0.0, 0.5)}, "radius_m": 0.75,
		"strength": 1.0, "amount_m3": 0.01, "seed": 4294967297}
	var encoded := Protocol.encode(command, 4294967298, 4294967299, 256, 0.125)
	_check("128byte_and_exact_int64", encoded.size() == 128 and encoded.decode_s64(8) == 9007199254740993 and
		encoded.decode_s64(0) == 4294967298 and encoded.decode_s64(32) == 4294967299 and encoded.decode_s64(96) == 4294967297)
	_check("std430_low_high_identity", encoded.decode_u32(8) == 1 and encoded.decode_u32(12) == 2097152)
	_check("fixed_scalar_offsets", encoded.decode_float(48) == 0.25 and encoded.decode_float(52) == -0.5 and
		encoded.decode_u32(44) == 1 and encoded.decode_u32(80) == 256 and encoded.decode_float(76) == 0.125)
	var inventory_encoded := Protocol.encode(command, 1, 1, 256, 0.125, 0, 1.0000001)
	_check("inventory_wire_never_rounds_up", inventory_encoded.decode_float(92) <= 1.0000001)
	inventory_encoded = Protocol.encode(command, 1, 1, 256, 0.125, 0, -0.0000003)
	_check("signed_inventory_preserves_eps_debt", inventory_encoded.decode_float(92) <= -0.0000003 and inventory_encoded.decode_float(92) < 0.0)
	var receipt := PackedByteArray()
	receipt.resize(128)
	receipt.fill(0)
	receipt.encode_s64(8, command.command_id)
	receipt.encode_s64(32, 4294967300)
	receipt.encode_u32(48, 1)
	receipt.encode_float(56, 0.01)
	var decoded := Protocol.decode_receipt(receipt)
	_check("receipt_identity", decoded.ok and decoded.command_id == command.command_id and decoded.output_revision == 4294967300)
	receipt.encode_float(112, -0.25)
	receipt.encode_float(116, 0.5)
	decoded = Protocol.decode_receipt(receipt)
	_check("impulse_unit_alias_preserves_128byte_abi", decoded.ok and decoded.impulse_x_m4_s == -0.25 and
		decoded.impulse_z_m4_s == 0.5 and decoded.impulse_x_m3_s == decoded.impulse_x_m4_s and
		decoded.impulse_z_m3_s == decoded.impulse_z_m4_s and receipt.size() == 128)
	_check("truncated_receipt_rejected", not Protocol.decode_receipt(receipt.slice(0, 124)).ok)
	receipt.encode_float(56, NAN)
	_check("nan_receipt_rejected", not Protocol.decode_receipt(receipt).ok)
	receipt.encode_float(56, -0.01)
	_check("negative_actual_rejected", not Protocol.decode_receipt(receipt).ok)
	receipt.encode_float(56, 0.01)
	receipt.encode_u32(88, 1)
	_check("applied_invalid_flag_rejected", not Protocol.decode_receipt(receipt).ok)
	receipt.encode_u32(88, 0)
	receipt.encode_s64(0, 4294967298)
	receipt.encode_s64(16, 1)
	receipt.encode_s64(24, 4294967299)
	decoded = Protocol.decode_receipt(receipt)
	_check("receipt_identity_binding", Protocol.receipt_matches(decoded, 4294967298, command.command_id, 1, 4294967299) and
		not Protocol.receipt_matches(decoded, 4294967298, command.command_id, 2, 4294967299) and
		not Protocol.receipt_matches(decoded, 4294967298, command.command_id, 1, 4294967298))
	_check("finite_command", Protocol.finite_command(command))
	var invalid := command.duplicate(true)
	invalid.radius_m = NAN
	_check("nan_input_rejected_by_candidate_preflight", not Protocol.finite_command(invalid))
	var domain := Domain.new(64, 0.125)
	domain.sand.fill(0.4)
	domain.water.fill(0.12)
	var queue := Queue.new(domain)
	invalid.command_id = 1
	var legacy_nan_admission: StringName = queue.submit(invalid)
	_check("legacy_nan_admission_observed", legacy_nan_admission.is_empty(), String(legacy_nan_admission))
	# Do not apply malformed commands to the authoritative/reference domain.
	queue.pending.clear()
	var zero := command.duplicate(true)
	zero.command_id = 2
	zero.shape = &"circle"
	zero.strength = 0.0
	var sand_before := domain.sand.to_byte_array()
	var water_before := domain.water.to_byte_array()
	var error: StringName = queue.submit(zero)
	var results: Array[Dictionary] = queue.apply_due_commands(0)
	_check("zero_strength_legacy_applied_without_mass_change", error.is_empty() and results.size() == 1 and
		results[0].status == &"applied" and domain.sand.to_byte_array() == sand_before and
		domain.water.to_byte_array() == water_before and domain.tool_inventory_m3 == 0.0,
		{"dirty_cells": results[0].dirty_cells.size()})
	var budgets := []
	for height in [0.0, 0.12, 0.4, 0.8, 8.0]:
		budgets.append({"height_m": height, "ulp32": Protocol.ulp32(height),
			"cell_budget_m": Protocol.cell_budget(height, height + 0.01)})
	_check("ulp32_reference_values", Protocol.ulp32(1.0) == pow(2.0, -23.0) and Protocol.ulp32(8.0) == pow(2.0, -20.0), budgets)
	var thick := PackedFloat32Array()
	thick.resize(128)
	thick.fill(8.0)
	var footprint := PackedInt32Array()
	for i in 128: footprint.append(i)
	var unchanged_budget := Protocol.volume_budget(thick, thick, 0.015625, footprint)
	_check("touched_rounding_budget_includes_unchanged_cells", unchanged_budget.count == 128 and
		unchanged_budget.changed_count == 0 and unchanged_budget.quantization_m3 == 2.0 * 0.015625 * 128 * pow(2.0, -20.0), unchanged_budget)
	var ok := true
	for check in checks:
		ok = ok and check.pass
	var report := {"pass": ok, "role": "contract_preflight", "checks": checks,
		"legacy_defect": "ToolCommandQueue admits NaN radius; malformed command not executed",
		"candidate_correctness": "not assessed by this CPU schema preflight", "engine": Engine.get_version_info()}
	if not output.is_empty():
		var file := FileAccess.open(output.path_join("contract_probe.json"), FileAccess.WRITE)
		file.store_string(JSON.stringify(report, "\t"))
	print("CONTRACT_PROBE " + JSON.stringify(report))
	quit(0 if ok else 1)


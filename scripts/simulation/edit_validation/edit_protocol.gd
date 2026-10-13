extends RefCounted

# Frozen internal transport v1. Integer identities never pass through float.
const STRIDE := 128
const UNIT_ROUNDOFF := 0.000000059604644775390625
const LEGACY_EPS := 0.000001
const DRY_DEPTH := 0.001
const COMMAND_INT_OFFSETS := {"ticket_id": 0, "command_id": 8, "generation": 16,
	"sim_tick": 24, "input_revision": 32, "seed": 96}
const RECEIPT_INT_OFFSETS := {"ticket_id": 0, "command_id": 8, "generation": 16,
	"input_revision": 24, "output_revision": 32, "applied_tick": 40}

static func encode(command: Dictionary, ticket: int, revision: int,
		grid_size: int, cell_size: float, policy: int = 0, available_m3: float = 0.0,
		speed_m_s: float = 0.0) -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(STRIDE)
	data.fill(0)
	var integers := {"ticket_id": ticket, "command_id": command.command_id,
		"generation": command.generation, "sim_tick": command.sim_tick,
		"input_revision": revision, "seed": command.seed}
	for key in COMMAND_INT_OFFSETS:
		data.encode_s64(COMMAND_INT_OFFSETS[key], integers[key])
	data.encode_u32(40, 0 if command.kind == &"remove_sand" else 1)
	data.encode_u32(44, 0 if command.shape == &"circle" else 1)
	var start: Vector3 = command.transform.position_m
	var end: Vector3 = command.transform.get("end_position_m", start)
	var values := [start.x, start.z, end.x, end.z, command.radius_m,
		command.strength, command.amount_m3, cell_size]
	for index in values.size():
		data.encode_float(48 + index * 4, float(values[index]))
	data.encode_u32(80, grid_size)
	data.encode_u32(84, policy)
	data.encode_float(88, LEGACY_EPS)
	data.encode_float(92, available_m3)
	# Never round inventory upward when narrowing CPU double to wire float32.
	if data.decode_float(92) > available_m3:
		data.encode_u32(92, data.decode_u32(92) + (1 if available_m3 < 0.0 else -1))
	data.encode_float(104, DRY_DEPTH)
	data.encode_float(108, speed_m_s)
	return data

static func decode_receipt(data: PackedByteArray) -> Dictionary:
	if data.size() != STRIDE:
		return {"ok": false, "error": "receipt_size"}
	var result := {"ok": true}
	for key in RECEIPT_INT_OFFSETS:
		result[key] = data.decode_s64(RECEIPT_INT_OFFSETS[key])
	result.status = data.decode_u32(48)
	result.error_code = data.decode_u32(52)
	result.actual_sand_m3 = data.decode_float(56)
	result.nominal_sand_m3 = data.decode_float(60)
	result.dirty_rect = Rect2i(data.decode_s32(64), data.decode_s32(68),
		data.decode_s32(72), data.decode_s32(76))
	result.dirty_mask = [data.decode_u32(80), data.decode_u32(84)]
	result.invalid_flags = data.decode_u32(88)
	result.clamp_count = data.decode_u32(92)
	result.edited_cells = data.decode_u32(96)
	result.capacity_status = data.decode_u32(100)
	result.displaced_water_m3 = data.decode_float(104)
	result.retained_water_m3 = data.decode_float(108)
	result.impulse_x_m3_s = data.decode_float(112)
	result.impulse_z_m3_s = data.decode_float(116)
	# ABI-compatible aliases above were mislabeled in v1. hu*A is m4/s.
	result.impulse_x_m4_s = result.impulse_x_m3_s
	result.impulse_z_m4_s = result.impulse_z_m3_s
	for key in ["actual_sand_m3", "nominal_sand_m3", "displaced_water_m3", "retained_water_m3",
			"impulse_x_m3_s", "impulse_z_m3_s"]:
		if not is_finite(float(result[key])):
			return {"ok": false, "error": "nonfinite_receipt"}
	for key in ["actual_sand_m3", "nominal_sand_m3", "displaced_water_m3", "retained_water_m3"]:
		if float(result[key]) < 0.0:
			return {"ok": false, "error": "negative_receipt_volume"}
	if result.status == 1 and (result.invalid_flags != 0 or result.error_code != 0):
		return {"ok": false, "error": "invalid_applied_receipt"}
	if result.status > 2 or result.error_code > 8 or data.decode_u32(120) != 0 or data.decode_u32(124) != 0:
		return {"ok": false, "error": "receipt_encoding"}
	return result

static func receipt_matches(receipt: Dictionary, ticket: int, command_id: int,
		generation: int, revision: int) -> bool:
	return receipt.get("ok", false) and receipt.ticket_id == ticket and receipt.command_id == command_id and \
		receipt.generation == generation and receipt.input_revision == revision and \
		(receipt.status != 1 or receipt.output_revision == revision + 1)

static func finite_command(command: Dictionary) -> bool:
	for key in ["radius_m", "strength", "amount_m3"]:
		if typeof(command.get(key)) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(command[key])):
			return false
	if not command.get("transform") is Dictionary:
		return false
	for key in ["position_m", "end_position_m"]:
		if not command.transform.has(key):
			if key == "end_position_m" and command.get("shape") != &"swept_segment":
				continue
			return false
		if not command.transform[key] is Vector3 or not (command.transform[key] as Vector3).is_finite():
			return false
	return true

static func ulp32(value: float) -> float:
	if value == 0.0 or absf(value) < pow(2.0, -126.0):
		return pow(2.0, -149.0)
	return pow(2.0, floor(log(absf(value)) / log(2.0)) - 23.0)

static func cell_budget(before: float, after: float) -> float:
	return maxf(0.0000002, 16.0 * ulp32(maxf(absf(before), absf(after))) +
		16.0 * UNIT_ROUNDOFF * absf(after - before))

static func reduction_budget(count: int, absolute_sum: float) -> float:
	return maxf(0.00000001, (4.0 * UNIT_ROUNDOFF +
		2.0 * count * UNIT_ROUNDOFF * UNIT_ROUNDOFF) * absolute_sum)

static func volume_budget(before: PackedFloat32Array, after: PackedFloat32Array,
		area: float, touched_cells := PackedInt32Array()) -> Dictionary:
	var quantization := 0.0
	var absolute_sum := 0.0
	var count := 0
	var changed_count := 0
	var touched := {}
	for index in touched_cells:
		touched[index] = true
	for index in before.size():
		if before[index] != after[index]:
			changed_count += 1
			absolute_sum += absf(after[index] - before[index]) * area
		if touched.has(index) or before[index] != after[index]:
			count += 1
			quantization += 2.0 * ulp32(maxf(absf(before[index]), absf(after[index]))) * area
	var reduction := reduction_budget(count, absolute_sum)
	return {"count": count, "changed_count": changed_count, "quantization_m3": quantization, "reduction_m3": reduction,
		"edit_m3": maxf(0.0000001, quantization + reduction)}

extends RefCounted

const Spec = preload("res://scripts/sand/brushes/brush_spec.gd")
const Registry = preload("res://scripts/sand/brushes/brush_registry.gd")
const STRIDE := 256
const COMMAND_MAGIC := 0x32535242
const RECEIPT_MAGIC := 0x32535252
const COMMON_FIELDS := ["schema_version", "domain_id", "generation", "command_id", "stroke_id", "sim_tick", "sample_index", "brush_id", "operation", "definition_hash", "template_hash", "start_xz_m", "end_xz_m", "baseline_token", "add_budget_m3", "transfer_budget_m3", "seed", "water_policy", "speed_m_s", "material_profile_id"]
static var registry = Registry.new()

static func make_command(id: StringName, params: Dictionary, start: Vector2, finish: Vector2, domain: StringName, generation: int, command_id: int, stroke: int, sample: int, tick: int, baseline: int) -> Dictionary:
	var definition = registry.definition(id)
	if definition == null or not Spec.parameter_error(id, params).is_empty(): return {}
	var result := {"schema_version": 2, "domain_id": domain, "generation": generation, "command_id": command_id, "stroke_id": stroke, "sim_tick": tick, "sample_index": sample, "brush_id": id, "operation": definition.operation, "definition_hash": definition.definition_hash(), "template_hash": definition.template_hash(), "start_xz_m": start, "end_xz_m": finish, "baseline_token": baseline, "add_budget_m3": 0.0, "transfer_budget_m3": 0.0, "seed": 101, "water_policy": 3, "speed_m_s": 0.0, "material_profile_id": &"plain_sand_v1"}
	for key in params: result[key] = params[key]
	if id == &"castle_v1": result.yaw_rad = wrapf(float(result.yaw_rad), -PI, PI)
	var budget := Spec.budget(id, params, start.distance_to(finish))
	if id == &"shovel_v1": result.transfer_budget_m3 = budget
	else: result.add_budget_m3 = budget
	return result

static func command_error(command: Dictionary) -> StringName:
	if typeof(command.get("schema_version")) != TYPE_INT or command.schema_version != 2: return &"unsupported_brush_version"
	var all: Dictionary = Spec.specification().brushes
	if typeof(command.get("brush_id")) not in [TYPE_STRING, TYPE_STRING_NAME]: return &"invalid_command"
	var id := StringName(command.get("brush_id", ""))
	if not all.has(String(id)): return &"unknown_brush"
	var definition: Dictionary = all[String(id)]
	var ranges: Dictionary = definition.ranges
	if command.size() != COMMON_FIELDS.size() + ranges.size(): return &"invalid_command"
	for key in COMMON_FIELDS:
		if not command.has(key): return &"invalid_command"
	for key in ["generation", "command_id", "stroke_id", "sim_tick", "sample_index", "baseline_token", "seed", "water_policy"]:
		if typeof(command[key]) != TYPE_INT or command[key] < 0: return &"invalid_command"
	for key in ["generation", "command_id", "stroke_id", "baseline_token"]:
		if command[key] == 0: return &"invalid_command"
	if command.sample_index > 4294967295 or command.water_policy not in [0,1,2,3]: return &"invalid_command"
	if typeof(command.domain_id) not in [TYPE_STRING, TYPE_STRING_NAME] or String(command.domain_id).is_empty(): return &"invalid_command"
	if typeof(command.operation) not in [TYPE_STRING, TYPE_STRING_NAME] or String(command.operation) != definition.operation: return &"invalid_command"
	for key in ["start_xz_m", "end_xz_m"]:
		if not command[key] is Vector2 or not (command[key] as Vector2).is_finite(): return &"invalid_command"
	var params := {}
	for key in ranges:
		if not command.has(key): return &"invalid_command"
		params[key] = command[key]
	var error := Spec.parameter_error(id, params)
	if not error.is_empty(): return error
	if typeof(command.definition_hash) != TYPE_STRING or typeof(command.template_hash) != TYPE_STRING: return &"template_mismatch"
	error = registry.validate_identity(id, command.definition_hash, command.template_hash)
	if not error.is_empty(): return error
	if command.material_profile_id not in [&"plain_sand_v1", &"molded_v1"]: return &"material_candidate_invalid"
	for key in ["add_budget_m3", "transfer_budget_m3", "speed_m_s"]:
		if not Spec.finite_number(command[key]): return &"invalid_command"
	if absf(float(command.speed_m_s)) > 1.0: return &"invalid_command"
	var start: Vector2 = command.start_xz_m
	var finish: Vector2 = command.end_xz_m
	var length := start.distance_to(finish)
	if length > 2.0 + 1e-10 or (id == &"castle_v1" and start != finish): return &"invalid_command"
	var radius := 0.0
	if id == &"castle_v1": radius = 2.0 * float(params.scale_xz) * (absf(cos(float(params.yaw_rad))) + absf(sin(float(params.yaw_rad))))
	elif id == &"wall_v1": radius = float(params.bottom_width_m) * 0.5
	else: radius = float(params.trench_width_m) * 0.5 + float(params.shoulder_width_m)
	for point in [start, finish]:
		if point.x - radius < -16.0 or point.y - radius < -16.0 or point.x + radius > 16.0 or point.y + radius > 16.0: return &"out_of_domain"
	var allowed := Spec.budget(id, params, minf(2.0, length))
	if command.add_budget_m3 < 0.0 or command.transfer_budget_m3 < 0.0: return &"budget_exceeded"
	if id == &"shovel_v1":
		if command.add_budget_m3 != 0.0 or command.transfer_budget_m3 > allowed: return &"budget_exceeded"
	elif command.transfer_budget_m3 != 0.0 or command.add_budget_m3 > allowed: return &"budget_exceeded"
	return &""

static func encode(command: Dictionary, ticket: int, revision: int) -> PackedByteArray:
	if not command_error(command).is_empty() or ticket <= 0 or revision < 0: return PackedByteArray()
	var spec := Spec.specification()
	var values: Dictionary = command.duplicate(false)
	values.magic = COMMAND_MAGIC; values.stride = STRIDE; values.ticket_id = ticket; values.input_revision = revision
	values.operation = spec.operation_codes[String(command.operation)]
	values.grid_size = 256; values.cell_size_m = 0.125; values.material_profile = 1 if command.material_profile_id==&"molded_v1" else 0
	values.start_x = command.start_xz_m.x; values.start_z = command.start_xz_m.y
	values.end_x = command.end_xz_m.x; values.end_z = command.end_xz_m.y
	values.scale_x = command.get("scale_xz", 0.0); values.scale_z = values.scale_x
	values.ridge_height_m = 0.5 if command.brush_id == &"shovel_v1" else 0.0
	values.placement_relief_m = 0.0 # Reserved wire field; fixed castle target has no relief rejection.
	values.template_width = 65 if command.brush_id == &"castle_v1" else 0
	values.template_height = values.template_width; values.template_spacing_m = 0.0625 if values.template_width else 0.0
	var data := PackedByteArray(); data.resize(STRIDE); data.fill(0)
	for field in spec.command_layout:
		var name: String = field[0]
		var offset := int(field[1])
		match String(field[2]):
			"i64": data.encode_s64(offset, int(values.get(name, 0)))
			"u32": data.encode_u32(offset, int(values.get(name, 0)))
			"f32":
				var value := float(values.get(name, 0.0))
				data.encode_float(offset, value)
				if name in ["add_budget_m3", "transfer_budget_m3"] and data.decode_float(offset) > value: data.encode_u32(offset, data.decode_u32(offset) - 1)
			"sha256":
				var hash: String = command.definition_hash if name == "definition_sha256" else command.template_hash
				if not hash.is_empty():
					var bytes := hash.hex_decode()
					if bytes.size() != 32: return PackedByteArray()
					for i in 32: data[offset + i] = bytes[i]
	return data

static func decode_receipt(data: PackedByteArray) -> Dictionary:
	if data.size() != STRIDE or data.decode_u32(0) != RECEIPT_MAGIC or data.decode_u32(4) != 2 or data.decode_u32(8) != STRIDE: return {"ok": false, "error": "unsupported_brush_version"}
	var result := {"ok": true}
	for field in Spec.specification().receipt_layout:
		var name: String = field[0]
		var offset := int(field[1])
		match String(field[2]):
			"i64": result[name] = data.decode_s64(offset)
			"u32": result[name] = data.decode_u32(offset)
			"i32": result[name] = data.decode_s32(offset)
			"f32":
				result[name] = data.decode_float(offset)
				if not is_finite(result[name]): return {"ok": false, "error": "invalid_receipt"}
			"bytes48":
				for i in range(offset, offset + 48):
					if data[i] != 0: return {"ok": false, "error": "invalid_receipt"}
	if result.status not in [1,2,3] or result.error_code > 18 or result.capacity_status > 2: return {"ok": false, "error": "invalid_receipt"}
	for key in ["added_m3", "removed_m3", "transferred_m3", "left_received_m3", "right_received_m3", "external_source_delta_m3", "external_sink_delta_m3", "requested_budget_m3", "displaced_water_m3", "retained_water_m3", "eps_sand_m3", "eps_water_m3", "eps_transfer_m3", "nominal_added_m3", "nominal_cut_m3", "max_cell_delta_m"]:
		if result[key] < 0.0: return {"ok": false, "error": "invalid_receipt"}
	if result.status == 1:
		if result.error_code != 0 or result.invalid_flags != 0 or result.output_revision != result.input_revision + 1: return {"ok": false, "error": "invalid_receipt"}
	else:
		if result.output_revision != result.input_revision: return {"ok": false, "error": "invalid_receipt"}
		if result.status == 2 and (result.error_code != 0 or result.invalid_flags != 0): return {"ok": false, "error": "invalid_receipt"}
		if result.status == 3 and result.error_code == 0: return {"ok": false, "error": "invalid_receipt"}
		for key in ["added_m3", "removed_m3", "transferred_m3", "left_received_m3", "right_received_m3", "external_source_delta_m3", "external_sink_delta_m3", "edited_cells", "dirty_x", "dirty_z", "dirty_width", "dirty_height", "dirty_mask_low", "dirty_mask_high"]:
			if result[key] != 0: return {"ok": false, "error": "invalid_receipt"}
		for key in ["displaced_water_m3", "retained_water_m3", "water_error_m3", "impulse_x_m4_s", "impulse_z_m4_s", "sand_error_m3", "eps_sand_m3", "eps_water_m3", "eps_transfer_m3", "nominal_added_m3", "nominal_cut_m3", "max_cell_delta_m"]:
			if result[key] != 0: return {"ok": false, "error": "invalid_receipt"}
	result.dirty_rect = Rect2i(result.dirty_x, result.dirty_z, result.dirty_width, result.dirty_height)
	result.dirty_mask = [result.dirty_mask_low, result.dirty_mask_high]
	return result

static func receipt_matches(receipt: Dictionary, command: Dictionary, ticket: int, revision: int) -> bool:
	if not receipt.get("ok", false): return false
	for key in ["command_id", "stroke_id", "generation", "baseline_token", "sample_index"]:
		if receipt.get(key) != command.get(key): return false
	if receipt.ticket_id != ticket or receipt.input_revision != revision: return false
	if receipt.status == 1:
		if command.brush_id == &"shovel_v1":
			if receipt.external_source_delta_m3 != 0.0 or receipt.external_sink_delta_m3 != 0.0: return false
			if absf(receipt.removed_m3 - receipt.left_received_m3 - receipt.right_received_m3) > receipt.eps_transfer_m3: return false
		else:
			if receipt.removed_m3 != 0.0 or receipt.external_sink_delta_m3 != 0.0 or receipt.external_source_delta_m3 != receipt.added_m3: return false
	return true

extends RefCounted

const PATH := "res://assets/brushes/protocol_v2.json"
static var _cached: Dictionary = {}

static func specification() -> Dictionary:
	if _cached.is_empty():
		var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if value is Dictionary: _cached = value
	return _cached.duplicate(true)

static func finite_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))

static func parameter_error(id: StringName, params: Dictionary) -> StringName:
	var brushes: Dictionary = specification().get("brushes", {})
	if not brushes.has(String(id)): return &"unknown_brush"
	var ranges: Dictionary = brushes[String(id)].ranges
	if params.size() != ranges.size(): return &"invalid_command"
	for key in ranges:
		if not params.has(key) or not finite_number(params[key]): return &"invalid_command"
		if float(params[key]) < float(ranges[key][0]) or float(params[key]) > float(ranges[key][1]): return &"invalid_command"
	if id == &"wall_v1" and float(params.top_width_m) > float(params.bottom_width_m): return &"invalid_command"
	return &""

static func budget(id: StringName, params: Dictionary, length_m: float) -> float:
	if not parameter_error(id, params).is_empty() or not is_finite(length_m) or length_m < 0.0 or length_m > 2.0: return -1.0
	match id:
		&"castle_v1": return 48.0 # Includes filling below the fixed world datum; actual volume is audited on GPU.
		&"wall_v1":
			var w := float(params.bottom_width_m)
			return minf(8.0, (length_m * w + PI * w * w / 4.0) * (float(params.height_m) + 0.25))
		&"shovel_v1":
			var w := float(params.trench_width_m)
			return minf(1.0, float(params.depth_m) * (2.0 * w * length_m / 3.0 + PI * w * w / 8.0))
	return -1.0

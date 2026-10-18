extends RefCounted
class_name Test1GeometryLayout

const STATE := "res://assets/test1_geometry/initial_state.f32"
const STATE_SHA256 := "0d2afa78195b675600e2d36bf4dc4539b9575bb7fd5e25019c43b5df341bd3b3"
const WATER_PROFILE := "res://assets/test1_geometry/water_cycle.json"
static var cached_water_cycle: Dictionary = {}

static func water_cycle() -> Dictionary:
	if cached_water_cycle.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(WATER_PROFILE))
		if not parsed is Dictionary or parsed.get("schema_version") != 1:
			return {}
		for key in ["rest_level_m", "runup_height_m", "period_s"]:
			if not parsed.has(key) or typeof(parsed[key]) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(parsed[key])):
				return {}
		if parsed.rest_level_m < 0.5 or parsed.rest_level_m > 1.1 or parsed.runup_height_m <= 0 or parsed.runup_height_m > 0.6 or parsed.period_s < 12 or parsed.period_s > 60:
			return {}
		if parsed.get("shape") != "smoothstep_5_20_25_45_percent":
			return {}
		cached_water_cycle = parsed
		cached_water_cycle.make_read_only()
	return cached_water_cycle

static func sea_level(seconds: float) -> float:
	var profile := water_cycle()
	if profile.is_empty(): return NAN
	var phase := fposmod(seconds, float(profile.period_s)) / float(profile.period_s)
	var envelope := smoothstep(0.05, 0.20, phase) * (1.0 - smoothstep(0.25, 0.45, phase))
	return float(profile.rest_level_m) + float(profile.runup_height_m) * envelope

static func contains(point: Vector3) -> bool:
	return absf(point.x) <= 15.0 and absf(point.z) <= 7.5

static func initialize(target: SandWaterDomain) -> bool:
	if target.grid_size != 256 or not is_equal_approx(target.cell_size_m, 0.125):
		return false
	if water_cycle().is_empty():
		return false
	if FileAccess.get_sha256(STATE) != STATE_SHA256:
		return false
	var bytes := FileAccess.get_file_as_bytes(STATE)
	if bytes.size() != 65536 * 5 * 4:
		return false
	var state := bytes.to_float32_array()
	var qx := PackedFloat32Array()
	var qz := PackedFloat32Array()
	qx.resize(65536)
	qz.resize(65536)
	for i in 65536:
		var j := i * 5
		target.rock[i] = 0.0
		target.sand[i] = state[j]
		target.water[i] = state[j + 1]
		qx[i] = state[j + 2]
		qz[i] = state[j + 3]
		target.obstacle[i] = state[j + 4]
		target.wetness[i] = 0.8 if target.water[i] > 0.001 else 0.15
		target.compaction[i] = 0.95
	target.domain_id = &"test1_geometry"
	target.set_meta("edit_validation_initial_qx", qx)
	target.set_meta("edit_validation_initial_qz", qz)
	return true

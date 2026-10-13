extends RefCounted
class_name Test1PlayableLayout

const STATE := "res://assets/test1_water_motion/capture_state.rgba32f"
const SEA_OFFSET := 1.6163164377212524
const DATUM_SHIFT := 0.95

static func initialize(target: SandWaterDomain, key: String) -> bool:
	if target.grid_size != 256 or not is_equal_approx(target.cell_size_m, 0.125) or key not in ["test1_capture", "test1_backwash"]:
		return false
	var raw := FileAccess.get_file_as_bytes(STATE)
	if raw.size() != 512 * 256 * 16:
		return false
	var state := raw.to_float32_array()
	var qx := PackedFloat32Array()
	var qz := PackedFloat32Array()
	qx.resize(256 * 256)
	qz.resize(256 * 256)
	for z in 256:
		for x in 256:
			var i := z * 256 + x
			var world := Vector2((float(x) + 0.5) * 0.125 - 16.0, (float(z) + 0.5) * 0.125 - 16.0)
			# Rotate 180 degrees: test1's ocean becomes main's x=0 inlet.
			var uv := Vector2((15.0 - world.x) / 30.0, (world.y + 7.5) / 15.0)
			var cell := uv * Vector2(512.0, 256.0) - Vector2(0.5, 0.5)
			var low := Vector2i(floori(cell.x), floori(cell.y))
			var f := cell - Vector2(low)
			var bed := 0.0
			var depth := 0.0
			var mx := 0.0
			var mz := 0.0
			for dz in 2:
				for dx in 2:
					var j := (clampi(low.y + dz, 0, 255) * 512 + clampi(low.x + dx, 0, 511)) * 4
					var weight := (f.x if dx == 1 else 1.0 - f.x) * (f.y if dz == 1 else 1.0 - f.y)
					var h := maxf(state[j + 2] - 0.05, 0.0)
					bed += state[j + 3] * weight
					depth += h * weight
					mx -= state[j] * h * weight
					mz += state[j + 1] * h * weight
			# The 32m domain padding continues the nearest captured edge.
			target.rock[i] = -1.0
			target.sand[i] = maxf(bed - DATUM_SHIFT + 1.0, 0.0)
			target.water[i] = depth
			target.wetness[i] = 0.8 if depth > 0.001 else 0.15
			target.compaction[i] = 0.95
			qx[i] = mx
			qz[i] = mz
			if not is_finite(target.sand[i]) or not is_finite(depth) or not is_finite(mx) or not is_finite(mz):
				return false
	target.domain_id = StringName(key)
	target.set_meta("edit_validation_initial_qx", qx)
	target.set_meta("edit_validation_initial_qz", qz)
	return true

static func sea_level(key: String, seconds: float) -> float:
	# Godot schedule; original future customWave timing is not recovered.
	var offset := SEA_OFFSET
	if key == "test1_backwash":
		offset *= 0.5 + 0.5 * cos(TAU * seconds / 16.0)
	return offset + 0.049701884388923645 * sin(284.71783447265625 + seconds)

class_name SandcastleBedDisplaySampler
extends RefCounted

## W03 frozen display bed contract for picking and future sand presentation.
## UV (cell_x + 0.5) / size reads exactly that authoritative cell. Between
## centres, rock + sand are interpolated with a monotone cubic weight; samples
## outside the domain clamp to the nearest border cell. This reads only and does
## not change physics or the authoritative GPU state.


static func sample_bed(rock: PackedFloat32Array, sand: PackedFloat32Array,
		grid_size: int, uv: Vector2) -> float:
	if grid_size < 2 or rock.size() != grid_size * grid_size or \
			sand.size() != grid_size * grid_size:
		return NAN
	var cell := uv * float(grid_size) - Vector2(0.5, 0.5)
	var x0 := floori(cell.x)
	var z0 := floori(cell.y)
	var blend := Vector2(_smooth_weight(cell.x - floorf(cell.x)),
		_smooth_weight(cell.y - floorf(cell.y)))
	var b00 := _cell_bed(rock, sand, grid_size, x0, z0)
	var b10 := _cell_bed(rock, sand, grid_size, x0 + 1, z0)
	var b01 := _cell_bed(rock, sand, grid_size, x0, z0 + 1)
	var b11 := _cell_bed(rock, sand, grid_size, x0 + 1, z0 + 1)
	return lerpf(lerpf(b00, b10, blend.x), lerpf(b01, b11, blend.x), blend.y)


static func sample_world(rock: PackedFloat32Array, sand: PackedFloat32Array,
		grid_size: int, cell_size_m: float, world_xz_m: Vector2) -> float:
	if cell_size_m <= 0.0:
		return NAN
	var domain_size_m := float(grid_size) * cell_size_m
	var uv := world_xz_m / domain_size_m + Vector2(0.5, 0.5)
	return sample_bed(rock, sand, grid_size, uv)


static func _cell_bed(rock: PackedFloat32Array, sand: PackedFloat32Array,
		grid_size: int, x: int, z: int) -> float:
	var index := clampi(z, 0, grid_size - 1) * grid_size + clampi(x, 0, grid_size - 1)
	return rock[index] + sand[index]


static func _smooth_weight(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)

class_name SandcastleSandDisplaySampler
extends RefCounted

## S03 piecewise planar bed used by the sand display and heightfield collision.
## The diagonal runs from the high-x/low-z sample to the low-x/high-z sample.


static func sample_bed(rock: PackedFloat32Array, sand: PackedFloat32Array,
		grid_size: int, uv: Vector2) -> float:
	if grid_size <= 1 or rock.size() != grid_size * grid_size or \
			sand.size() != grid_size * grid_size:
		return NAN
	var cell := uv * float(grid_size) - Vector2(0.5, 0.5)
	var low_x := floori(cell.x)
	var low_z := floori(cell.y)
	var fx := cell.x - float(low_x)
	var fz := cell.y - float(low_z)
	var x0 := clampi(low_x, 0, grid_size - 1)
	var z0 := clampi(low_z, 0, grid_size - 1)
	var x1 := clampi(low_x + 1, 0, grid_size - 1)
	var z1 := clampi(low_z + 1, 0, grid_size - 1)
	var i00 := z0 * grid_size + x0
	var i10 := z0 * grid_size + x1
	var i01 := z1 * grid_size + x0
	var i11 := z1 * grid_size + x1
	var v00 := rock[i00] + sand[i00]
	var v10 := rock[i10] + sand[i10]
	var v01 := rock[i01] + sand[i01]
	var v11 := rock[i11] + sand[i11]
	if fx + fz <= 1.0:
		return v00 + fx * (v10 - v00) + fz * (v01 - v00)
	return v11 + (1.0 - fx) * (v01 - v11) + \
		(1.0 - fz) * (v10 - v11)


static func sample_world(rock: PackedFloat32Array, sand: PackedFloat32Array,
		grid_size: int, cell_size_m: float, world_xz: Vector2) -> float:
	if cell_size_m <= 0.0:
		return NAN
	var size_m := float(grid_size) * cell_size_m
	return sample_bed(rock, sand, grid_size,
		(world_xz + Vector2(size_m, size_m) * 0.5) / size_m)

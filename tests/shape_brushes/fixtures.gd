extends RefCounted

const SIZE := 256
const CELL := 0.125
const SEED := 101
const CASES := ["dry_flat", "dry_slope", "thin_sand", "shallow_water", "submerged", "isolated_pool", "boundary"]

# Cell centers, same XZ origin and bed = rock + sand as the live domain.
# These are test initial states; no live profile is changed by their creation.
static func build(id: String) -> Dictionary:
	if id not in CASES: return {}
	var fields := {}
	for name in ["rock", "sand", "water", "momentum_x", "momentum_z", "sediment", "wetness", "compaction", "obstacle"]:
		var values := PackedFloat32Array()
		values.resize(SIZE * SIZE)
		fields[name] = values
	for z in SIZE:
		for x in SIZE:
			var i := z * SIZE + x
			var p := Vector2((x + 0.5 - SIZE / 2.0) * CELL, (z + 0.5 - SIZE / 2.0) * CELL)
			var bed := 0.02 * p.x if id == "dry_slope" else 0.0
			var sand := 0.01 if id == "thin_sand" else 1.0
			var water := 0.0
			if id == "shallow_water": water = 0.10
			if id == "submerged": water = 0.50
			if id == "isolated_pool":
				bed = 0.0 if p.length() <= 4.0 else 0.50
				water = 0.25 if p.length() <= 4.0 else 0.0
			fields.rock[i] = bed - sand
			fields.sand[i] = sand
			fields.water[i] = water
	return {"id": id, "grid_size": SIZE, "cell_size_m": CELL, "seed": SEED, "tick": 0, "camera_position": Vector3(-6, 6, 10), "camera_target": Vector3.ZERO, "fields": fields}

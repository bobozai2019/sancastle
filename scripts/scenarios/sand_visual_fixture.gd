class_name SandcastleSandVisualFixture
extends RefCounted

## S02 twin sand shapes. Relative dimensions and volume match the S01 GPU probe.
const FIXTURE_ID: StringName = &"sand_v1"
const COUPLED_FIXTURE_ID: StringName = &"sand_coupled_v1"
const SEED := 53021
const PACKED_CENTER_X := 80
const LOOSE_CENTER_X := 176
const CENTER_Z := 128
const BASE_RADIUS_CELLS := 8
const CAMERA_IDS := [&"oblique", &"close", &"grazing"]
const CAMERA_POSITIONS := [
	Vector3(0.0, 13.0, 19.0),
	Vector3(-5.8, 3.4, 7.0),
	Vector3(-8.0, 1.5, 4.0),
]
const CAMERA_TARGETS := [
	Vector3(0.0, 0.9, 0.0),
	Vector3(-6.0, 1.1, 0.0),
	Vector3(-6.0, 1.3, 0.0),
]
const CAMERA_FOV := [52.0, 56.0, 52.0]


static func initialize(domain: SandWaterDomain,
		visual_wetness_override: float = -1.0,
		coupled: bool = false) -> bool:
	if domain.grid_size != 256 or not is_equal_approx(domain.cell_size_m, 0.125):
		return false
	if visual_wetness_override >= 0.0 and \
			(not is_finite(visual_wetness_override) or visual_wetness_override > 1.0):
		return false
	for z in domain.grid_size:
		for x in domain.grid_size:
			var i := domain.index(x, z)
			domain.rock[i] = -0.12 if coupled else 0.20
			domain.sand[i] = 0.0
			domain.water[i] = 0.0
			domain.wetness[i] = 0.05
			domain.compaction[i] = 0.1
			for center_x in [PACKED_CENTER_X, LOOSE_CENTER_X]:
				var dx: int = x - center_x
				var dz: int = z - CENTER_Z
				if absi(dx) > BASE_RADIUS_CELLS or absi(dz) > BASE_RADIUS_CELLS:
					continue
				var height := 1.8
				if dx >= 5 and dz >= 3:
					height = 1.55
				if absi(dx) <= 1 and absi(dz) <= 1:
					height = 1.5
				domain.sand[i] = height
				if center_x == PACKED_CENTER_X:
					domain.wetness[i] = visual_wetness_override if \
						visual_wetness_override >= 0.0 else 0.35
					domain.compaction[i] = 0.95
			if coupled:
				# A low, loose seaward toe supports the packed tower's west wall.
				# Its mass is sampled from the authoritative GPU sand field in S05.
				if x >= PACKED_CENTER_X - 11 and x <= PACKED_CENTER_X - 9 and \
						absi(z - CENTER_Z) <= BASE_RADIUS_CELLS:
					domain.sand[i] = 0.18
					domain.compaction[i] = 0.1
				var sea_level := 0.10 if x < 96 else -0.10
				domain.water[i] = maxf(0.0, sea_level - domain.bed_at(i))
				if domain.water[i] > 0.001:
					domain.wetness[i] = 0.8
	return true


static func camera_index(camera_id: StringName) -> int:
	return CAMERA_IDS.find(camera_id)

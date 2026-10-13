class_name SandcastleStandardScenarios
extends RefCounted

## Dimensionless shape templates shared by CPU reference and future GPU setup.
## Terrain heights are metres; horizontal features scale with domain extent.

const SEEDS := [101, 202, 303]
const NAMES := ["sloped_coast", "curved_channel_basin", "sand_wall_two_towers"]
const CAMERA_FOV_DEGREES := 55.0
const TIDE_MEAN_M := 0.10
const TIDE_AMPLITUDE_M := 0.11
const TIDE_ANGULAR_SPEED_RAD_S := 0.35


static func camera_position(grid_size: int, cell_size_m: float) -> Vector3:
	var scale := float(grid_size) * cell_size_m / 8.0
	return Vector3(0.0, 9.5 * scale, 11.0 * scale)


static func tide_level(time_s: float) -> float:
	return TIDE_MEAN_M + TIDE_AMPLITUDE_M * sin(time_s * TIDE_ANGULAR_SPEED_RAD_S)


static func initialize(domain: SandWaterDomain, preset: int) -> bool:
	if preset < 0 or preset >= SEEDS.size():
		return false
	var rng := RandomNumberGenerator.new()
	rng.seed = SEEDS[preset]
	var size := domain.grid_size
	for z in size:
		for x in size:
			var i := domain.index(x, z)
			var nx := float(x) / float(size - 1)
			var nz := float(z) / float(size - 1)
			domain.rock[i] = -0.30 + nx * 0.34
			domain.sand[i] = 0.38 + rng.randf_range(-0.003, 0.003)
			match preset:
				0:
					domain.sand[i] += 0.025 * sin(nz * TAU * 3.0)
				1:
					var channel := absf(nz - 0.5 - 0.11 * sin(nx * TAU * 1.5))
					domain.sand[i] += -0.20 if channel < 0.09 else 0.06
					if nx > 0.70 and channel < 0.20:
						domain.sand[i] -= 0.08
				2:
					if absf(nx - 0.53) < 0.04 and not (nz > 0.46 and nz < 0.55):
						domain.sand[i] += 0.42
					for tower_z in [0.26, 0.76]:
						if Vector2(nx - 0.55, nz - tower_z).length() < 0.075:
							domain.sand[i] += 0.35
			var initial_surface := 0.13 - domain.bed_at(i)
			domain.water[i] = maxf(0.0, initial_surface) if x < size / 3 else 0.0
			domain.wetness[i] = 0.8 if domain.water[i] > 0.001 else 0.15
	return true

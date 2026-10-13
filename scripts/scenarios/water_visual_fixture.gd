class_name SandcastleWaterVisualFixture
extends RefCounted

## Fixed bed for phase two water work. All dimensions are metres; the simulation
## remains 256 x 256 at 0.125 m per cell. This fixture never edits sand at runtime.
const FIXTURE_ID: StringName = &"water_v1"
const SEED := 41021
const CAMERA_IDS := [&"oblique", &"close", &"grazing"]
const CAMERA_POSITIONS := [
	Vector3(0.0, 12.0, 18.0),
	Vector3(-3.8, 2.7, 5.0),
	Vector3(-8.0, 0.95, 3.0),
]
const CAMERA_TARGETS := [
	Vector3(0.0, 0.05, 0.0),
	Vector3(-5.0, 0.05, 0.0),
	Vector3(-5.0, 0.10, 0.0),
]
const CAMERA_FOV := [55.0, 58.0, 54.0]


static func initialize(domain: SandWaterDomain) -> bool:
	if domain.grid_size != 256 or not is_equal_approx(domain.cell_size_m, 0.125):
		return false
	var count := domain.grid_size
	for z in count:
		for x in count:
			var i := domain.index(x, z)
			var world_x := (float(x) + 0.5) * domain.cell_size_m - 16.0
			var world_z := (float(z) + 0.5) * domain.cell_size_m - 16.0
			# A gentle coast intersects the initial surface. A sand ridge and
			# channel are legible through 2/8 cm water in the close camera.
			var coast := 0.012 * world_x
			var ridge := 0.035 * exp(-pow((world_z + 1.5) / 0.65, 2.0))
			var channel := -0.045 * exp(-pow((world_z - 1.5) / 0.85, 2.0))
			var shoal := 0.055 * exp(-pow((world_x + 4.0) / 2.5, 2.0))
			var hill_radius := Vector2(world_x - 1.5, world_z + 2.5).length()
			var highland := 0.38 * (1.0 - smoothstep(1.4, 2.7, hill_radius))
			domain.rock[i] = -0.27 + coast
			domain.sand[i] = 0.30 + ridge + channel + shoal + highland
			var depth := maxf(0.0, 0.105 - domain.bed_at(i))
			domain.water[i] = depth
			domain.wetness[i] = 0.8 if depth > 0.001 else 0.15
			domain.compaction[i] = 0.45
	return true


static func camera_index(camera_id: StringName) -> int:
	return CAMERA_IDS.find(camera_id)

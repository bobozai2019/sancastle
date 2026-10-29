extends RefCounted

## W07 prototype only. Both modes receive exactly the same initial bed and water.
## This is scene input, not a change to the sand or water physics model.
const FIXTURE_ID: StringName = &"water_render_demo_v2"
const COUPLED_FIXTURE_ID: StringName = &"water_render_coupled_v2"
const SEED := 74021
const CAMERA_IDS := [&"oblique", &"close", &"grazing"]
const CAMERA_POSITIONS := [
	Vector3(-1.0, 12.0, 19.0),
	Vector3(-4.8, 3.4, 7.0),
	Vector3(-7.5, 1.45, 4.0),
]
const CAMERA_TARGETS := [
	Vector3(0.0, 0.10, 0.0),
	Vector3(-3.2, 0.08, -1.0),
	Vector3(-5.0, 0.08, -0.8),
]
const CAMERA_FOV := [54.0, 57.0, 54.0]

## Compatibility constants read by the cloned controller's old support tools.
## That fixture-specific auto support sensor is disabled in the prototype.
const PACKED_CENTER_X := 80
const CENTER_Z := 128
const BASE_RADIUS_CELLS := 8


static func initialize(domain: SandWaterDomain,
		_visual_wetness_override: float = -1.0,
		_coupled: bool = false,
		smooth_reference_shore: bool = false,
		natural_reference_shore: bool = false,
		structured_reference_bed: bool = false,
		sculpted_reference_bed: bool = false,
		lobed_reference_bed: bool = false,
		branched_reference_bed: bool = false,
		estuary_reference_bed: bool = false,
		test1_sand_forms: bool = false) -> bool:
	if domain.grid_size != 256 or not is_equal_approx(domain.cell_size_m, 0.125):
		return false
	if branched_reference_bed and not (lobed_reference_bed and
			structured_reference_bed and natural_reference_shore):
		return false
	if estuary_reference_bed and not branched_reference_bed:
		return false
	for z in domain.grid_size:
		for x in domain.grid_size:
			var i := domain.index(x, z)
			var world_x := (float(x) + 0.5) * domain.cell_size_m - 16.0
			var world_z := (float(z) + 0.5) * domain.cell_size_m - 16.0
			var shore := 0.018 * world_x + 0.008 * world_z
			if natural_reference_shore:
				# Broad, unequal bays move the waterline without a repeating tooth pattern.
				var coast_shift_m := 1.45 * exp(-pow((world_z + 9.0) / 3.2, 2.0)) \
					- 1.15 * exp(-pow((world_z - 0.8) / 4.4, 2.0)) \
					+ 1.30 * exp(-pow((world_z - 10.5) / 3.8, 2.0))
				shore -= 0.036 * coast_shift_m
			var ridge := 0.035 * sin(world_z * 2.2 + world_x * 0.35)
			var channel := -0.070 * exp(-pow((world_z + 2.5 + 0.18 * world_x) / 1.05, 2.0))
			var island_r := Vector2(world_x + 2.0, world_z + 3.5).length()
			var island := 0.70 * (1.0 - smoothstep(1.5, 3.0, island_r))
			var steep_r := Vector2(world_x - 6.0, world_z - 3.0).length()
			var steep_bank := 1.10 * (1.0 - smoothstep(0.90, 1.25, steep_r))
			var structured_relief := 0.0
			var exposed_channel := 0.0
			if structured_reference_bed:
				var shelf_envelope := smoothstep(-9.0, -6.0, world_x) * \
					(1.0 - smoothstep(2.5, 4.0, world_x))
				var south_center := 7.2 + 0.26 * world_x + \
					0.80 * sin(0.52 * world_x + 0.4)
				var south_gully := exp(-pow((world_z - south_center) / 0.85, 2.0))
				var south_tongue := exp(-pow((world_z - south_center - 1.65) / 1.08, 2.0))
				var north_center := -8.0 + 0.18 * world_x + \
					0.55 * sin(0.70 * world_x + 1.4)
				var north_gully := exp(-pow((world_z - north_center) / 0.72, 2.0))
				var north_tongue := exp(-pow((world_z - north_center + 1.55) / 1.12, 2.0))
				structured_relief = shelf_envelope * ( \
					-0.055 * south_gully + 0.032 * south_tongue \
					- 0.040 * north_gully + 0.025 * north_tongue)
				var facies_envelope := smoothstep(-9.0, -6.0, world_x) * \
					(1.0 - smoothstep(4.0, 6.0, world_x))
				exposed_channel = clampf(facies_envelope * maxf(
					south_gully * 0.95, north_gully * 0.72), 0.0, 1.0)
			if sculpted_reference_bed:
				# W07 isolated candidate: broad sand fingers and adjacent submerged
				# gullies remain real bed relief, shared by fixed and coupled modes.
				var relief_envelope := smoothstep(-11.0, -7.0, world_x) * \
					(1.0 - smoothstep(5.0, 8.0, world_x))
				var lower_axis := 7.4 + 0.30 * world_x + \
					0.85 * sin(0.35 * world_x + 0.2)
				var upper_axis := -7.8 + 0.17 * world_x + \
					0.60 * sin(0.42 * world_x + 1.5)
				var lower_finger := exp(-pow((world_z - lower_axis) / 1.70, 2.0))
				var lower_gully := exp(-pow((world_z - lower_axis + 2.20) / 1.15, 2.0))
				var upper_finger := exp(-pow((world_z - upper_axis) / 1.35, 2.0))
				var upper_gully := exp(-pow((world_z - upper_axis - 2.10) / 1.10, 2.0))
				structured_relief += relief_envelope * (0.065 * lower_finger - \
					0.075 * lower_gully + 0.050 * upper_finger - \
					0.065 * upper_gully)
			if lobed_reference_bed:
				# Isolated W07/W13 scene-input candidate. Broad lobes taper into
				# the sea and join the right bank without a rectangular cut edge.
				var reach := smoothstep(-10.0, -3.5, world_x)
				var south_axis := 6.0 + 0.12 * world_x + \
					0.72 * sin(0.39 * world_x + 0.35)
				var north_axis := -6.1 + 0.09 * world_x + \
					0.58 * sin(0.47 * world_x + 1.1)
				var south_width := 2.30
				var north_width := 1.85
				if branched_reference_bed:
					# Resolved metre-scale bends and unequal shoulders alter the
					# authoritative contour, not a texture or screen-space mask.
					south_axis += 0.36 * sin(0.91 * world_x + 0.45) + \
						0.19 * sin(1.72 * world_x - 0.30)
					north_axis += 0.30 * sin(0.77 * world_x - 0.60) + \
						0.13 * sin(1.55 * world_x + 1.10)
					south_width *= 1.0 + 0.17 * sin(0.67 * world_x + 0.70)
					north_width *= 1.0 + 0.14 * sin(0.80 * world_x - 0.50)
				var south_bar := exp(-pow((world_z - south_axis) / south_width, 2.0))
				var north_bar := exp(-pow((world_z - north_axis) / north_width, 2.0))
				var south_trough := exp(-pow((world_z - south_axis + 3.20) / 1.50, 2.0))
				var north_trough := exp(-pow((world_z - north_axis - 2.75) / 1.35, 2.0))
				structured_relief += reach * (0.29 * south_bar + 0.21 * north_bar - \
					0.070 * south_trough - 0.055 * north_trough)
				if branched_reference_bed:
					var branch_envelope := smoothstep(-9.0, -5.5, world_x) * \
						(1.0 - smoothstep(1.0, 5.0, world_x))
					var branch_axis := 1.45 + 0.31 * world_x + \
						0.48 * sin(0.59 * world_x + 0.35)
					var branch_ridge := exp(-pow((world_z - branch_axis) / 0.92, 2.0))
					var branch_channel := exp(-pow((world_z - branch_axis - 1.80) / 0.74, 2.0))
					structured_relief += branch_envelope * \
						(0.115 * branch_ridge - 0.074 * branch_channel)
			if estuary_reference_bed:
				# Isolated W07/W13 input: a curved, finite inlet breaks the broad
				# right bank into several genuine wet/dry branches.
				var inlet_reach := smoothstep(-2.0, 2.0, world_x) * \
					(1.0 - smoothstep(11.5, 15.0, world_x))
				var inlet_axis := 0.2 + 0.24 * world_x + \
					0.75 * sin(0.32 * world_x + 0.7)
				var inlet_width := 2.2 + 0.4 * sin(0.26 * world_x + 1.1)
				var inlet := exp(-pow((world_z - inlet_axis) / inlet_width, 2.0))
				structured_relief -= 0.16 * inlet_reach * inlet
			if smooth_reference_shore or natural_reference_shore:
				# The repeated ridge should not move the wet/dry contour by metres.
				# Retain it in the submerged bed and on dry land away from sea level.
				var bed_without_ridge := 0.02 + shore + channel + island + steep_bank
				if sculpted_reference_bed or lobed_reference_bed:
					# Isolated relief candidates must suppress the repeating ridge
					# against their actual pre-ridge waterline, not the old base bed.
					bed_without_ridge += structured_relief
				ridge *= smoothstep(0.0,
					0.26 if structured_reference_bed else 0.06,
					absf(0.14 - bed_without_ridge))
			var sand_thickness := maxf(0.01, 0.52 + shore + ridge + channel +
				structured_relief + island + steep_bank)
			if test1_sand_forms:
				# Fixed scene input. The same authoritative heightfield is rendered and
				# later edited; no decorative mesh substitutes for sand volume.
				var tower_a_r := Vector2(world_x - 8.0, world_z + 4.0).length()
				var tower_b_r := Vector2(world_x - 10.0, world_z - 4.8).length()
				var broad_r := Vector2(world_x - 5.0, world_z - 1.4).length()
				sand_thickness += 3.1 * (1.0 - smoothstep(0.32, 1.55, tower_a_r))
				sand_thickness += 2.3 * (1.0 - smoothstep(0.45, 1.75, tower_b_r))
				sand_thickness += 0.72 * (1.0 - smoothstep(1.2, 3.8, broad_r))
			var bed_height := -0.50 + sand_thickness
			if structured_reference_bed:
				sand_thickness = maxf(0.03,
					sand_thickness * (1.0 - 0.90 * exposed_channel))
			domain.rock[i] = bed_height - sand_thickness if structured_reference_bed else -0.50
			domain.sand[i] = sand_thickness
			var depth := maxf(0.0, 0.14 - domain.bed_at(i))
			domain.water[i] = depth
			domain.wetness[i] = 0.80 if depth > 0.001 else 0.15
			domain.compaction[i] = 0.60
	return true


static func camera_index(camera_id: StringName) -> int:
	return CAMERA_IDS.find(camera_id)

extends SceneTree

const Domain = preload("res://scripts/simulation/sand_water_domain.gd")
const Fixture = preload("res://scripts/scenarios/water_visual_fixture.gd")
const Sampler = preload("res://scripts/visual/bed_display_sampler.gd")


func _init() -> void:
	var domain: SandWaterDomain = Domain.new(256, 0.125)
	if not Fixture.initialize(domain):
		push_error("fixture unavailable")
		quit(1)
		return
	var checked := 0
	for z in range(0, 256, 19):
		for x in range(0, 256, 17):
			var i := domain.index(x, z)
			var uv := Vector2((float(x) + 0.5) / 256.0,
				(float(z) + 0.5) / 256.0)
			var sampled := Sampler.sample_bed(domain.rock, domain.sand, 256, uv)
			var world_xz := uv * 32.0 - Vector2(16.0, 16.0)
			var world_sampled := Sampler.sample_world(domain.rock, domain.sand,
				256, 0.125, world_xz)
			if absf(sampled - domain.bed_at(i)) > 0.000001 or \
					absf(world_sampled - domain.bed_at(i)) > 0.000001:
				push_error("display bed differs at cell centre (%d,%d)" % [x, z])
				quit(1)
				return
			checked += 1
	print("PASS: W03 bed display sampler centres=%d" % checked)
	quit(0)

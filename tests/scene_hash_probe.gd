extends SceneTree

const Domain = preload("res://scripts/simulation/sand_water_domain.gd")
const Scenarios = preload("res://scripts/scenarios/standard_scenarios.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	for size in [64, 256]:
		for preset in 3:
			var domain = Domain.new(size, 0.125)
			if not Scenarios.initialize(domain, preset):
				printerr("FAIL: scenario initialization")
				quit(1)
				return
			print("SCENE_HASH size=%d preset=%d seed=%d hash=%d" % [
				size, preset + 1, Scenarios.SEEDS[preset],
				hash([domain.rock, domain.sand, domain.water, domain.wetness])])
	print("PASS: six fixed-input scenario hashes")
	quit(0)

extends "res://tools/physics_threading/cost_probe.gd"

# Separate observer control; copy into a frozen variant only between runs.
# Frame, actual input and terminal capture remain for the comparison.
func _run() -> void:
	detailed=false
	await super._run()

func _enable_gpu_times() -> void:
	preview.observe_gpu_wait_phases=false
	preview.solver.profile_passes=false
	preview.collision_proxy.profile_passes=false
	preview.collision_proxy.profile_latency_details=false

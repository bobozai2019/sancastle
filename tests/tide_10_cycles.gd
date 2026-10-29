extends SceneTree

const Domain = preload("res://scripts/simulation/sand_water_domain.gd")
const ShallowWater = preload("res://scripts/water/reference/shallow_water_solver.gd")
const SIZE := 64
const STEP := 1.0 / 30.0
const FREQUENCY_HZ := 0.25

var failures: Array[String] = []


func _init() -> void:
	for solver_name in ["virtual_pipe", "shallow_water"]:
		_run(solver_name)
	if failures.is_empty():
		print("PASS: configured tide cycles for both CPU solvers")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("FAIL: ten-cycle tide gate")
		quit(1)


func _run(solver_name: String) -> void:
	var cycles := int(OS.get_environment("SANDCASTLE_TIDE_CYCLES"))
	if cycles <= 0:
		cycles = 10
	var steps := roundi(float(cycles) / FREQUENCY_HZ / STEP)
	var domain = Domain.new(SIZE, 0.125)
	for y in SIZE:
		for x in SIZE:
			var i: int = domain.index(x, y)
			domain.rock[i] = 0.30 * float(x) / float(SIZE - 1)
			domain.water[i] = maxf(0.0, 0.15 - domain.rock[i])
	var initial: float = domain.total_water_m3()
	var solver = ShallowWater.new(domain) if solver_name == "shallow_water" else null
	var gauge := domain.index(8, 32)
	var was_wet: bool = domain.water[gauge] > 0.002
	var transitions := 0
	var gauge_min := INF
	var gauge_max := 0.0
	var wet_seen := PackedByteArray()
	var dry_seen := PackedByteArray()
	wet_seen.resize(SIZE - 2)
	dry_seen.resize(SIZE - 2)
	wet_seen.fill(0)
	dry_seen.fill(0)
	var start := Time.get_ticks_usec()
	for tick in steps:
		var sea_level := 0.12 + 0.16 * sin(float(tick) * STEP * TAU * FREQUENCY_HZ)
		if solver == null:
			domain.set_tide_boundary(sea_level)
			domain.step_water(STEP)
			domain.sim_tick += 1
		else:
			solver.set_tide_boundary(sea_level)
			solver.step(STEP)
			if solver.overload_events > 0:
				break
		var wet: bool = domain.water[gauge] > 0.002
		gauge_min = minf(gauge_min, domain.water[gauge])
		gauge_max = maxf(gauge_max, domain.water[gauge])
		if wet != was_wet:
			transitions += 1
			was_wet = wet
		for x in range(1, SIZE - 1):
			if domain.water[domain.index(x, 32)] > 0.002:
				wet_seen[x - 1] = 1
			else:
				dry_seen[x - 1] = 1
	var expected: float = initial + domain.water_source_m3 - domain.water_sink_m3
	var error_pct := absf(domain.total_water_m3() - expected) / maxf(maxf(absf(expected), absf(initial)), 0.000001) * 100.0
	var negatives: int = solver.negative_depth_events if solver != null else domain.clamped_water_events
	var elapsed_ms := float(Time.get_ticks_usec() - start) / 1000.0
	var overload: int = solver.overload_events if solver != null else 0
	var velocity_limits: int = solver.velocity_limit_events if solver != null else 0
	var transition_cells := 0
	for i in wet_seen.size():
		if wet_seen[i] == 1 and dry_seen[i] == 1:
			transition_cells += 1
	print("TIDE solver=%s cycles=%d completed_ticks=%d error_pct=%.6f wet_dry_transitions=%d transition_cells=%d gauge_min=%.4f gauge_max=%.4f negative_events=%d overload=%d velocity_limits=%d elapsed_ms=%.3f" % [
		solver_name, cycles, domain.sim_tick, error_pct, transitions, transition_cells, gauge_min, gauge_max, negatives, overload, velocity_limits, elapsed_ms])
	if solver != null:
		print("TIDE_LIMITS shallow=%d boundary=%d ocean=%d opposite=%d cross=%d first_tick=%d first_cell=%d max_raw_speed_mps=%.3f" % [
			solver.velocity_limit_shallow_events, solver.velocity_limit_boundary_events,
			solver.velocity_limit_ocean_edge_events, solver.velocity_limit_opposite_edge_events,
			solver.velocity_limit_cross_edge_events,
			solver.velocity_limit_first_tick, solver.velocity_limit_first_cell,
			solver.velocity_limit_max_raw_speed_mps])
	if solver != null and overload > 0:
		print("TIDE_OVERLOAD first_tick=%d requested_substeps=%d speed_mps=%.3f" % [
			solver.overload_first_tick, solver.overload_requested_substeps, solver.overload_speed_mps])
	if error_pct > 0.5 or negatives > 0 or transition_cells == 0 or overload > 0 or domain.nan_events > 0:
		failures.append("%s failed tide gate" % solver_name)

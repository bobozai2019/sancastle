extends SceneTree

const Domain = preload("res://scripts/simulation/sand_water_domain.gd")
const ShallowWater = preload("res://scripts/water/reference/shallow_water_solver.gd")
const SIZE := 64
const STEP := 1.0 / 30.0

var failures: Array[String] = []


func _init() -> void:
	var seconds := int(OS.get_environment("SANDCASTLE_CLOSED_SECONDS"))
	if seconds <= 0:
		seconds = 300
	var filter_solver := OS.get_environment("SANDCASTLE_CLOSED_SOLVER")
	var bed_mode := OS.get_environment("SANDCASTLE_CLOSED_BED")
	if bed_mode.is_empty():
		bed_mode = "uneven"
	if bed_mode not in ["flat", "uneven"]:
		push_error("unknown closed-water bed mode: " + bed_mode)
		quit(1)
		return
	for solver_name in ["virtual_pipe", "shallow_water"]:
		if not filter_solver.is_empty() and solver_name != filter_solver:
			continue
		_run(solver_name, seconds, bed_mode)
	if failures.is_empty():
		print("PASS: closed-water %d-second test" % seconds)
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("FAIL: closed-water %d-second test" % seconds)
		quit(1)


func _run(solver_name: String, seconds: int, bed_mode: String) -> void:
	var domain = Domain.new(SIZE, 0.125)
	for y in SIZE:
		for x in SIZE:
			var i: int = domain.index(x, y)
			domain.rock[i] = 0.0 if bed_mode == "flat" else 0.12 * float(x) / float(SIZE - 1) + 0.03 * sin(float(y) * TAU / float(SIZE - 1))
			domain.water[i] = 0.5 - domain.rock[i]
	var initial: float = domain.total_water_m3()
	var initial_depths: PackedFloat32Array = domain.water.duplicate()
	var solver = ShallowWater.new(domain) if solver_name == "shallow_water" else null
	var rows := PackedStringArray(["tick,sim_seconds,mass_m3,mass_error_pct,max_depth_drift_m,min_water_m,negative_events,velocity_limits"])
	var steps := seconds * 30
	var start := Time.get_ticks_usec()
	for tick in steps:
		if solver == null:
			domain.step_water(STEP)
			domain.sim_tick += 1
		else:
			solver.step(STEP)
			if solver.overload_events > 0:
				failures.append("%s overloaded at tick %d" % [solver_name, tick])
				break
		if (tick + 1) % 300 == 0 or tick == steps - 1:
			var minimum := INF
			var maximum_drift := 0.0
			for i in domain.water.size():
				var depth: float = domain.water[i]
				minimum = minf(minimum, depth)
				maximum_drift = maxf(maximum_drift, absf(depth - initial_depths[i]))
				if is_nan(depth) or is_inf(depth):
					failures.append("%s nonfinite depth at tick %d" % [solver_name, tick])
			var mass: float = domain.total_water_m3()
			var error_pct := absf(mass - initial) / initial * 100.0
			var negatives: int = solver.negative_depth_events if solver != null else domain.clamped_water_events
			var limits: int = solver.velocity_limit_events if solver != null else 0
			rows.append("%d,%.3f,%.9f,%.9f,%.9f,%.9f,%d,%d" % [
				tick + 1, float(tick + 1) * STEP, mass, error_pct,
				maximum_drift, minimum, negatives, limits])
			if minimum < -0.000001 or error_pct > 0.5 or negatives > 0 or maximum_drift > 0.001:
				failures.append("%s numerical gate failed at tick %d" % [solver_name, tick])
				break
	var elapsed_ms := float(Time.get_ticks_usec() - start) / 1000.0
	var output_path := "res://test_output/sandcastle_water_sand_coupling/验收/S2_closed_water_%ds_%s_%s.csv" % [seconds, bed_mode, solver_name]
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		failures.append("cannot write %s" % output_path)
	else:
		file.store_string("\n".join(rows) + "\n")
		file.close()
	print("CLOSED solver=%s bed=%s requested_seconds=%d completed_ticks=%d mass_error_pct=%.9f negative_events=%d velocity_limits=%d elapsed_ms=%.3f csv=%s" % [
		solver_name, bed_mode, seconds, domain.sim_tick,
		absf(domain.total_water_m3() - initial) / initial * 100.0,
		solver.negative_depth_events if solver != null else domain.clamped_water_events,
		solver.velocity_limit_events if solver != null else 0, elapsed_ms, output_path])

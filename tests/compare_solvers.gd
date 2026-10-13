extends SceneTree

const Domain = preload("res://scripts/simulation/sand_water_domain.gd")
const ShallowWater = preload("res://scripts/water/reference/shallow_water_solver.gd")
const SIZE := 64
const STEP := 1.0 / 30.0
const STEPS := 150
const CASES := ["flat_lake", "sloping_lake", "one_side_inlet", "curved_channel",
	"wall_opening", "dam_break", "tide_wet_dry"]

var rows: Array[String] = []
var failures: Array[String] = []


func _init() -> void:
	rows.append("case,solver,steps,mass_error_pct,min_water_m,downstream_water_m,arrival_tick,elapsed_ms,negative_events")
	var filter_case := OS.get_environment("SANDCASTLE_CASE")
	for case_name in CASES:
		if not filter_case.is_empty() and case_name != filter_case:
			continue
		for solver_name in ["virtual_pipe", "shallow_water"]:
			_run_case(case_name, solver_name)
	var output_name := "S2_solver_comparison_%s.csv" % filter_case if not filter_case.is_empty() else "S2_solver_comparison.csv"
	var file := FileAccess.open("res://test_output/sandcastle_water_sand_coupling/验收/" + output_name, FileAccess.WRITE)
	if file == null:
		failures.append("cannot save solver comparison CSV")
	else:
		file.store_string("\n".join(rows) + "\n")
		file.close()
	for row in rows:
		print(row)
	if failures.is_empty():
		var scenario_count := CASES.size() if filter_case.is_empty() else 1
		print("PASS: %d shared CPU solver scenarios recorded" % scenario_count)
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("FAIL: solver comparison")
		quit(1)


func _run_case(case_name: String, solver_name: String) -> void:
	var domain = Domain.new(SIZE, 0.125)
	_initialize_case(domain, case_name)
	var solver = ShallowWater.new(domain) if solver_name == "shallow_water" else null
	var target_y := 32
	if case_name == "curved_channel":
		var nx := 53.0 / float(SIZE - 1)
		target_y = roundi((0.5 + 0.12 * sin(nx * TAU * 1.5)) * float(SIZE - 1))
	var target_index: int = domain.index(53, target_y)
	var initial_water: float = domain.total_water_m3()
	var previous_target := 0.0
	var arrival := -1
	var time_start := Time.get_ticks_usec()
	for tick in STEPS:
		if case_name == "one_side_inlet":
			for y in SIZE:
				var i: int = domain.index(0, y)
				domain.water[i] += 0.001
				domain.water_source_m3 += 0.001 * domain.cell_area_m2
		elif case_name == "wall_opening" and tick == STEPS / 2:
			for y in range(29, 35):
				domain.obstacle[domain.index(SIZE / 2, y)] = 0.0
		elif case_name == "tide_wet_dry":
			var sea_level := 0.15 + 0.12 * sin(float(tick) * STEP * TAU * 0.8)
			if solver == null:
				domain.set_tide_boundary(sea_level)
			else:
				solver.set_tide_boundary(sea_level)
		if solver == null:
			domain.step_water(STEP)
		else:
			solver.step(STEP)
		var current_target: float = domain.water[target_index]
		if arrival < 0 and current_target > 0.005 and previous_target <= 0.005:
			arrival = tick
		previous_target = current_target
	var elapsed_ms := float(Time.get_ticks_usec() - time_start) / 1000.0
	var expected: float = initial_water + domain.water_source_m3 - domain.water_sink_m3
	var mass_error := absf(domain.total_water_m3() - expected) / maxf(maxf(absf(initial_water), absf(expected)), 0.000001) * 100.0
	var minimum := INF
	for value in domain.water:
		minimum = minf(minimum, value)
		if is_nan(value) or is_inf(value):
			failures.append("%s/%s nonfinite depth" % [case_name, solver_name])
	var negative_events: int = solver.negative_depth_events if solver != null else domain.clamped_water_events
	rows.append("%s,%s,%d,%.6f,%.7f,%.7f,%d,%.3f,%d" % [case_name, solver_name,
		STEPS, mass_error, minimum, domain.water[target_index], arrival,
		elapsed_ms, negative_events])
	if mass_error > 0.5 or minimum < -0.000001 or negative_events > 0:
		failures.append("%s/%s numerical gate failed" % [case_name, solver_name])
	if case_name == "sloping_lake" and domain.water[target_index] < 0.001:
		failures.append("%s sloping lake dried unexpectedly" % solver_name)


func _initialize_case(domain: SandWaterDomain, case_name: String) -> void:
	for y in SIZE:
		for x in SIZE:
			var i: int = domain.index(x, y)
			var nx := float(x) / float(SIZE - 1)
			var ny := float(y) / float(SIZE - 1)
			match case_name:
				"flat_lake": domain.water[i] = 0.30
				"sloping_lake":
					domain.rock[i] = 0.20 * nx + 0.04 * ny
					domain.water[i] = 0.50 - domain.rock[i]
				"one_side_inlet": domain.water[i] = 0.0
				"curved_channel":
					var center := 0.5 + 0.12 * sin(nx * TAU * 1.5)
					domain.rock[i] = 0.32 if absf(ny - center) > 0.10 else 0.0
					domain.water[i] = 0.40 - domain.rock[i] if x < 10 else 0.0
				"wall_opening":
					domain.obstacle[i] = 1.0 if x == SIZE / 2 else 0.0
					domain.water[i] = 0.40 if x < SIZE / 2 else 0.0
				"dam_break": domain.water[i] = 0.45 if x < SIZE / 2 else 0.0
				"tide_wet_dry":
					domain.rock[i] = 0.30 * nx
					domain.water[i] = maxf(0.0, 0.15 - domain.rock[i])

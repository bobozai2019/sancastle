extends SceneTree

const Domain = preload("res://scripts/simulation/sand_water_domain.gd")
const ShallowWater = preload("res://scripts/water/reference/shallow_water_solver.gd")
const SIZE := 64
const STEPS := 180
const STEP := 1.0 / 30.0

var rows := PackedStringArray(["solver,tick,seconds,wall_closed,front_mean_depth_m,upstream_mean_depth_m,downstream_mean_depth_m,backward_mean_flux_m3ps,mass_error_pct,negative_events"])
var failures: Array[String] = []


func _init() -> void:
	for solver_name in ["virtual_pipe", "shallow_water"]:
		_run(solver_name)
	var path := "res://test_output/sandcastle_water_sand_coupling/验收/S2_wall_reflection_curve.csv"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		failures.append("cannot write wall reflection CSV")
	else:
		file.store_string("\n".join(rows) + "\n")
		file.close()
	if failures.is_empty():
		print("PASS: wall reflection and opening curves recorded for both CPU solvers")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("FAIL: wall reflection curve")
		quit(1)


func _run(solver_name: String) -> void:
	var domain = Domain.new(SIZE, 0.125)
	for y in SIZE:
		for x in SIZE:
			var i: int = domain.index(x, y)
			domain.water[i] = 0.45 if x < 12 else 0.0
			if x == 32:
				domain.obstacle[i] = 1.0
	var solver = ShallowWater.new(domain) if solver_name == "shallow_water" else null
	var initial: float = domain.total_water_m3()
	var reflected_ticks := 0
	var max_front := 0.0
	var max_downstream_before_open := 0.0
	var final_downstream := 0.0
	for tick in STEPS:
		if tick == 90:
			for y in range(29, 35):
				domain.obstacle[domain.index(32, y)] = 0.0
		if solver == null:
			domain.step_water(STEP)
			domain.sim_tick += 1
		else:
			solver.step(STEP)
		var front := 0.0
		var upstream := 0.0
		var downstream := 0.0
		var backward := 0.0
		for y in range(24, 40):
			front += domain.water[domain.index(31, y)]
			upstream += domain.water[domain.index(27, y)]
			downstream += domain.water[domain.index(36, y)]
			var i: int = domain.index(27, y)
			backward += minf(0.0, domain.flux_right[i] - domain.flux_left[i])
		front /= 16.0
		upstream /= 16.0
		downstream /= 16.0
		final_downstream = downstream
		backward /= 16.0
		max_front = maxf(max_front, front)
		if tick < 90:
			max_downstream_before_open = maxf(max_downstream_before_open, downstream)
		if backward < -0.000001:
			reflected_ticks += 1
		var error_pct := absf(domain.total_water_m3() - initial) / initial * 100.0
		var negatives: int = solver.negative_depth_events if solver != null else domain.clamped_water_events
		rows.append("%s,%d,%.3f,%d,%.8f,%.8f,%.8f,%.9f,%.9f,%d" % [
			solver_name, tick + 1, float(tick + 1) * STEP, 1 if tick < 90 else 0,
			front, upstream, downstream, backward, error_pct, negatives])
		if error_pct > 0.5 or negatives > 0 or domain.nan_events > 0:
			failures.append("%s numerical failure at tick %d" % [solver_name, tick])
			break
	print("WALL solver=%s reflected_ticks=%d max_front_m=%.5f preopen_downstream_m=%.7f final_downstream_m=%.5f" % [
		solver_name, reflected_ticks, max_front, max_downstream_before_open, final_downstream])
	if max_downstream_before_open > 0.00001:
		failures.append("%s leaked through closed wall" % solver_name)

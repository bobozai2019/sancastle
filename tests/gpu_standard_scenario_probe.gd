extends SceneTree

const Domain = preload("res://scripts/simulation/sand_water_domain.gd")
const CpuSolver = preload("res://scripts/water/reference/shallow_water_solver.gd")
const GpuSolver = preload("res://scripts/simulation/gpu_shallow_solver.gd")
const Scenarios = preload("res://scripts/scenarios/standard_scenarios.gd")
const DELTA := 1.0 / 30.0

var size := 64
var preset := 0
var case_name := ""
var steps := 150
var tick_index := 0
var initial_domain: SandWaterDomain
var cpu_domain: SandWaterDomain
var cpu_solver: ShallowWaterReference
var gpu_solver: SandcastleGpuShallowSolver
var spirvs: Array[RDShaderSPIRV] = []
var expected_substeps := PackedInt32Array()
var expected_gauge := PackedFloat32Array()
var expected_front := PackedFloat32Array()
var expected_water := PackedFloat32Array()
var expected_source := PackedFloat32Array()
var expected_sink := PackedFloat32Array()
var tide_ready := false
var cfl_ready := false
var audit_ready := false
var gauge_ready := false
var front_ready := true
var cfl_data := PackedByteArray()
var cfl_revision := -1
var current_substeps := 0
var audit_result := {}
var gauge_depth := 0.0
var front_depth := 0.0
var preopen_max_downstream := 0.0
var final_readbacks := {}
var csv_rows := PackedStringArray([
	"tick,time_s,tide_m,substeps,gpu_source_m3,gpu_sink_m3,gpu_water_m3,gpu_gauge_m,min_depth_m,invalid_cells,negative_cells,cpu_source_m3,cpu_sink_m3,cpu_water_m3,cpu_gauge_m,max_depth_drift_m,gpu_front_gauge_m,cpu_front_gauge_m"])
var finished := false
var watchdog_started_ms := 0
var initial_water_m3 := 0.0
var initial_depths := PackedFloat32Array()
var maximum_closed_drift := 0.0
var closed_water_ready := true
var arrival_tick := -1
var max_gauge_error := 0.0
var max_volume_error := 0.0


func _init() -> void:
	call_deferred("_begin")


func _begin() -> void:
	var requested_size := int(OS.get_environment("SANDCASTLE_GPU_GRID"))
	if requested_size > 0:
		size = requested_size
	preset = int(OS.get_environment("SANDCASTLE_SCENARIO_PRESET"))
	case_name = OS.get_environment("SANDCASTLE_SCENARIO_CASE")
	var requested_steps := int(OS.get_environment("SANDCASTLE_GPU_STEPS"))
	if requested_steps > 0:
		steps = requested_steps
	if size not in [64, 256] or preset not in [0, 1, 2] or steps < 1 or \
			case_name not in ["", "flat_lake", "uneven_lake", "dam_break", "curved_channel", "one_side_inlet", "wall_opening"]:
		_fail("standard scenario probe arguments invalid")
		return
	for path in [
		"res://shaders/simulation/shallow_edge_flux.glsl",
		"res://shaders/simulation/shallow_drain_scale.glsl",
		"res://shaders/simulation/shallow_update_state.glsl",
		"res://shaders/simulation/shallow_tide_boundary.glsl",
		"res://shaders/simulation/shallow_cfl_tiles.glsl",
		"res://shaders/simulation/shallow_gauge_depth.glsl",
		"res://shaders/simulation/shallow_audit_tiles.glsl",
		"res://shaders/simulation/shallow_tool_patch.glsl"]:
		var shader_file: RDShaderFile = load(path)
		if shader_file == null or shader_file.get_spirv() == null:
			_fail("shader import missing: " + path)
			return
		spirvs.append(shader_file.get_spirv())
	initial_domain = Domain.new(size, 0.125)
	if not _initialize_domain(initial_domain):
		_fail("GPU scenario initialization failed")
		return
	initial_water_m3 = initial_domain.total_water_m3()
	initial_depths = initial_domain.water.duplicate()
	if size == 64:
		cpu_domain = Domain.new(size, 0.125)
		if not _initialize_domain(cpu_domain):
			_fail("CPU scenario initialization failed")
			return
		cpu_solver = CpuSolver.new(cpu_domain)
		for tick in steps:
			cpu_solver.max_substeps_used = 0
			if case_name.is_empty():
				cpu_solver.set_tide_boundary(_sea_level(tick))
			elif case_name == "one_side_inlet":
				for z in size:
					cpu_domain.water[cpu_domain.index(0, z)] += 0.001
					cpu_domain.water_source_m3 += 0.001 * cpu_domain.cell_area_m2
			elif case_name == "wall_opening" and tick == 75:
				for z in range(size / 2 - 3, size / 2 + 3):
					cpu_domain.obstacle[cpu_domain.index(size / 2, z)] = 0.0
			cpu_solver.step(DELTA)
			if cpu_solver.overload_events != 0 or cpu_solver.negative_depth_events != 0 or \
					cpu_domain.sim_tick != tick + 1:
				_fail("CPU scenario reference failed at tick %d" % tick)
				return
			expected_substeps.append(cpu_solver.max_substeps_used)
			expected_gauge.append(cpu_domain.water[_gauge_index()])
			expected_front.append(cpu_domain.water[cpu_domain.index(size / 2 - 4, size / 2)])
			expected_water.append(cpu_domain.total_water_m3())
			expected_source.append(cpu_domain.water_source_m3)
			expected_sink.append(cpu_domain.water_sink_m3)
	watchdog_started_ms = Time.get_ticks_msec()
	RenderingServer.call_on_render_thread(_render_setup)
	call_deferred("_watchdog")


func _initialize_domain(domain: SandWaterDomain) -> bool:
	if case_name.is_empty():
		return Scenarios.initialize(domain, preset)
	for z in size:
		for x in size:
			var i: int = domain.index(x, z)
			if case_name == "uneven_lake":
				domain.rock[i] = 0.12 * float(x) / float(size - 1) + \
					0.03 * sin(float(z) * TAU / float(size - 1))
			if case_name == "curved_channel":
				var nx := float(x) / float(size - 1)
				var nz := float(z) / float(size - 1)
				var center := 0.5 + 0.12 * sin(nx * TAU * 1.5)
				domain.rock[i] = 0.32 if absf(nz - center) > 0.10 else 0.0
				domain.water[i] = 0.40 - domain.rock[i] if x < 10 else 0.0
			elif case_name == "dam_break":
				domain.water[i] = 0.45 if x < size / 2 else 0.0
			elif case_name == "one_side_inlet":
				domain.water[i] = 0.0
			elif case_name == "wall_opening":
				domain.obstacle[i] = 1.0 if x == size / 2 else 0.0
				domain.water[i] = 0.40 if x < size / 2 else 0.0
			else:
				domain.water[i] = 0.5 - domain.rock[i]
	return true


func _is_still_water() -> bool:
	return case_name in ["flat_lake", "uneven_lake"]


func _sea_level(tick: int) -> float:
	if not case_name.is_empty():
		return 0.0
	return Scenarios.tide_level(float(tick) * DELTA)


func _gauge_x() -> int:
	if case_name in ["dam_break", "curved_channel", "wall_opening"]:
		return roundi(float(size - 1) * 53.0 / 63.0)
	return int(float(size - 1) * 0.12)


func _gauge_z() -> int:
	if case_name == "curved_channel":
		var nx := float(_gauge_x()) / float(size - 1)
		return roundi((0.5 + 0.12 * sin(nx * TAU * 1.5)) * float(size - 1))
	if preset == 1:
		var nx := float(_gauge_x()) / float(size - 1)
		return roundi((0.5 + 0.11 * sin(nx * TAU * 1.5)) * float(size - 1))
	return size / 2


func _gauge_index() -> int:
	return _gauge_z() * size + _gauge_x()


func _render_setup() -> void:
	gpu_solver = GpuSolver.new()
	if not gpu_solver.initialize(RenderingServer.get_rendering_device(), initial_domain,
			spirvs[0], spirvs[1], spirvs[2], spirvs[3], spirvs[4], spirvs[5], spirvs[6], spirvs[7]):
		call_deferred("_fail", "GPU standard scenario initialization failed")
		return
	_render_boundary()


func _render_boundary() -> void:
	if case_name == "wall_opening" and tick_index == 75:
		for z in range(size / 2 - 3, size / 2 + 3):
			initial_domain.obstacle[initial_domain.index(size / 2, z)] = 0.0
		if not gpu_solver.update_obstacles(initial_domain.obstacle):
			call_deferred("_fail", "GPU wall opening obstacle update failed")
			return
	if case_name.is_empty() or case_name == "one_side_inlet":
		var dispatched: bool = gpu_solver.dispatch_boundary_injection(0.001) if \
			case_name == "one_side_inlet" else gpu_solver.dispatch_tide_boundary(_sea_level(tick_index))
		if not dispatched:
			call_deferred("_fail", "GPU scenario boundary source failed at tick %d" % tick_index)
			return
		var ledger_error := gpu_solver.request_tide_ledger(_on_ledger)
		if ledger_error != OK:
			call_deferred("_fail", "GPU scenario ledger request failed %d" % ledger_error)
			return
	else:
		tide_ready = true
	var cfl_error := gpu_solver.request_cfl_tiles(_on_cfl)
	if cfl_error != OK:
		call_deferred("_fail", "GPU scenario CFL request failed %d" % cfl_error)


func _on_ledger(_source: float, _sink: float, _revision: int, valid: bool) -> void:
	call_deferred("_record_ledger", valid)


func _record_ledger(valid: bool) -> void:
	if finished:
		return
	if not valid:
		_fail("GPU scenario ledger invalid at tick %d" % tick_index)
		return
	tide_ready = true
	_maybe_advance()


func _on_cfl(data: PackedByteArray, revision: int) -> void:
	call_deferred("_record_cfl", data, revision)


func _record_cfl(data: PackedByteArray, revision: int) -> void:
	if finished:
		return
	var substeps := gpu_solver.substeps_from_cfl(DELTA, data)
	if substeps < 1 or substeps > gpu_solver.MAX_SUBSTEPS or \
			(cpu_domain != null and substeps != expected_substeps[tick_index]):
		_fail("GPU scenario CFL mismatch at tick %d: %d" % [tick_index, substeps])
		return
	cfl_data = data
	cfl_revision = revision
	current_substeps = substeps
	cfl_ready = true
	_maybe_advance()


func _maybe_advance() -> void:
	if tide_ready and cfl_ready:
		tide_ready = false
		cfl_ready = false
		RenderingServer.call_on_render_thread(_render_advance.bind(cfl_data, cfl_revision))


func _render_advance(data: PackedByteArray, revision: int) -> void:
	if not gpu_solver.dispatch_tick_with_cfl(DELTA, data, revision):
		call_deferred("_fail", "GPU scenario advance failed at tick %d" % tick_index)
		return
	var gauge_error := gpu_solver.request_gauge_depth(_gauge_x(), _gauge_z(), _on_gauge)
	var audit_error := gpu_solver.request_audit_tiles(_on_audit)
	if gauge_error != OK or audit_error != OK:
		call_deferred("_fail", "GPU scenario diagnostics request failed")
		return
	front_ready = true
	if case_name == "wall_opening":
		front_ready = false
		var front_error := gpu_solver.request_gauge_depth(size / 2 - 4,
			size / 2, _on_front_gauge)
		if front_error != OK:
			call_deferred("_fail", "GPU wall front gauge request failed")
			return
	closed_water_ready = true
	if _is_still_water() and ((tick_index + 1) % 300 == 0 or tick_index + 1 == steps):
		closed_water_ready = false
		var water_error := gpu_solver.request_data("water", _on_closed_water.bind(gpu_solver.state_revision))
		if water_error != OK:
			call_deferred("_fail", "GPU closed-water readback request failed")


func _on_closed_water(data: PackedByteArray, revision: int) -> void:
	call_deferred("_record_closed_water", data, revision)


func _record_closed_water(data: PackedByteArray, revision: int) -> void:
	if finished:
		return
	if revision != gpu_solver.state_revision or data.size() != size * size * 4:
		_fail("GPU closed-water readback revision/size invalid")
		return
	var water := data.to_float32_array()
	for i in water.size():
		if not is_finite(water[i]) or water[i] < -0.000001:
			_fail("GPU closed-water invalid depth")
			return
		maximum_closed_drift = maxf(maximum_closed_drift,
			absf(water[i] - initial_depths[i]))
	if maximum_closed_drift > 0.0001:
		_fail("GPU closed-water drift exceeded 0.0001 m at tick %d: %.8f" % [
			tick_index + 1, maximum_closed_drift])
		return
	closed_water_ready = true
	_maybe_finish_tick()


func _on_gauge(data: PackedByteArray, revision: int) -> void:
	call_deferred("_record_gauge", data, revision)


func _record_gauge(data: PackedByteArray, revision: int) -> void:
	if finished:
		return
	if data.size() != 4 or revision != gpu_solver.state_revision:
		_fail("GPU scenario gauge revision/bytes invalid")
		return
	gauge_depth = data.to_float32_array()[0]
	if not is_finite(gauge_depth) or gauge_depth < -0.000001:
		_fail("GPU scenario gauge negative/nonfinite")
		return
	gauge_ready = true
	_maybe_finish_tick()


func _on_front_gauge(data: PackedByteArray, revision: int) -> void:
	call_deferred("_record_front_gauge", data, revision)


func _record_front_gauge(data: PackedByteArray, revision: int) -> void:
	if finished:
		return
	if data.size() != 4 or revision != gpu_solver.state_revision:
		_fail("GPU wall front gauge revision/bytes invalid")
		return
	front_depth = data.to_float32_array()[0]
	if not is_finite(front_depth) or front_depth < -0.000001:
		_fail("GPU wall front gauge invalid")
		return
	front_ready = true
	_maybe_finish_tick()


func _on_audit(data: PackedByteArray, revision: int) -> void:
	call_deferred("_record_audit", data, revision)


func _record_audit(data: PackedByteArray, revision: int) -> void:
	if finished:
		return
	audit_result = gpu_solver.decode_audit_tiles(data)
	if revision != gpu_solver.state_revision or not audit_result.get("valid", false):
		_fail("GPU scenario audit revision/bytes invalid")
		return
	audit_ready = true
	_maybe_finish_tick()


func _maybe_finish_tick() -> void:
	if not audit_ready or not gauge_ready or not front_ready or not closed_water_ready:
		return
	audit_ready = false
	gauge_ready = false
	var volume: float = audit_result.water_m3
	if case_name in ["dam_break", "curved_channel"] and arrival_tick < 0 and gauge_depth > 0.005:
		arrival_tick = tick_index + 1
	if case_name == "wall_opening":
		if tick_index < 75:
			preopen_max_downstream = maxf(preopen_max_downstream, gauge_depth)
		elif arrival_tick < 0 and gauge_depth > 0.005:
			arrival_tick = tick_index + 1
	var closure := absf(volume - initial_water_m3 - gpu_solver.water_source_m3 +
		gpu_solver.water_sink_m3)
	var budget_scale := maxf(maxf(initial_water_m3, gpu_solver.water_source_m3), 0.001)
	if audit_result.minimum_depth_m < -0.000001 or audit_result.invalid_cells != 0 or \
			audit_result.negative_cells != 0 or closure > maxf(0.001, budget_scale * 0.005):
		_fail("GPU scenario audit failed tick=%d closure=%.7f" % [tick_index, closure])
		return
	if cpu_domain != null:
		max_gauge_error = maxf(max_gauge_error, absf(gauge_depth - expected_gauge[tick_index]))
		max_volume_error = maxf(max_volume_error, absf(volume - expected_water[tick_index]))
		if max_gauge_error > 0.0001 or max_volume_error > 0.001 or \
				(case_name == "wall_opening" and absf(front_depth - expected_front[tick_index]) > 0.0001) or \
				absf(gpu_solver.water_source_m3 - expected_source[tick_index]) > 0.0001 or \
				absf(gpu_solver.water_sink_m3 - expected_sink[tick_index]) > 0.0001:
			_fail("GPU/CPU scenario curve mismatch tick=%d gauge=%.7f volume=%.7f gpu_water=%.9f cpu_water=%.9f gpu_source=%.9f cpu_source=%.9f" % [
				tick_index, max_gauge_error, max_volume_error, volume,
				expected_water[tick_index], gpu_solver.water_source_m3,
				expected_source[tick_index]])
			return
	csv_rows.append("%d,%.6f,%.6f,%d,%.9f,%.9f,%.9f,%.9f,%.9f,%d,%d,%s,%s,%s,%s,%s,%s,%s" % [
		tick_index + 1, float(tick_index + 1) * DELTA, _sea_level(tick_index),
		current_substeps, gpu_solver.water_source_m3, gpu_solver.water_sink_m3,
		volume, gauge_depth, audit_result.minimum_depth_m,
		audit_result.invalid_cells, audit_result.negative_cells,
		"%.9f" % expected_source[tick_index] if cpu_domain != null else "",
		"%.9f" % expected_sink[tick_index] if cpu_domain != null else "",
		"%.9f" % expected_water[tick_index] if cpu_domain != null else "",
		"%.9f" % expected_gauge[tick_index] if cpu_domain != null else "",
		"%.9f" % maximum_closed_drift if _is_still_water() else "",
		"%.9f" % front_depth if case_name == "wall_opening" else "",
		"%.9f" % expected_front[tick_index] if cpu_domain != null and case_name == "wall_opening" else ""])
	tick_index += 1
	if tick_index < steps:
		RenderingServer.call_on_render_thread(_render_boundary)
	else:
		RenderingServer.call_on_render_thread(_render_read_final)


func _render_read_final() -> void:
	for field in ["water", "momentum_x", "momentum_z"]:
		var error: Error = gpu_solver.request_data(field, _on_final_data.bind(field))
		if error != OK:
			call_deferred("_fail", "GPU scenario final readback failed: %s" % field)
			return


func _on_final_data(data: PackedByteArray, field: String) -> void:
	call_deferred("_record_final_data", field, data)


func _record_final_data(field: String, data: PackedByteArray) -> void:
	if finished:
		return
	final_readbacks[field] = data
	if final_readbacks.size() != 3:
		return
	var water: PackedFloat32Array = final_readbacks.water.to_float32_array()
	var qx: PackedFloat32Array = final_readbacks.momentum_x.to_float32_array()
	var qz: PackedFloat32Array = final_readbacks.momentum_z.to_float32_array()
	if water.size() != size * size or qx.size() != water.size() or qz.size() != water.size():
		_fail("GPU scenario final state dimensions invalid")
		return
	var max_h_error := 0.0
	var max_q_error := 0.0
	for i in water.size():
		if not is_finite(water[i]) or water[i] < -0.000001 or \
				not is_finite(qx[i]) or not is_finite(qz[i]):
			_fail("GPU scenario final state nonfinite/negative")
			return
		if cpu_domain != null:
			max_h_error = maxf(max_h_error, absf(water[i] - cpu_domain.water[i]))
			max_q_error = maxf(max_q_error, maxf(absf(qx[i] - cpu_solver.momentum_x[i]),
				absf(qz[i] - cpu_solver.momentum_y[i])))
	if cpu_domain != null and (max_h_error > 0.0001 or max_q_error > 0.001):
		_fail("GPU/CPU scenario final grid mismatch h=%.7f q=%.7f" % [
			max_h_error, max_q_error])
		return
	if case_name == "one_side_inlet":
		var prescribed_source := 0.001 * float(size) * initial_domain.cell_area_m2 * float(steps)
		var actual_volume := 0.0
		for depth in water:
			actual_volume += depth * initial_domain.cell_area_m2
		if absf(gpu_solver.water_source_m3 - prescribed_source) > \
				maxf(0.0001, prescribed_source * 0.0001) or \
				gpu_solver.water_sink_m3 > 0.000001 or \
				absf(actual_volume - gpu_solver.water_source_m3) > prescribed_source * 0.005:
			_fail("GPU inlet source/closure mismatch prescribed=%.7f source=%.7f water=%.7f" % [
				prescribed_source, gpu_solver.water_source_m3, actual_volume])
			return
	var label: String = case_name if not case_name.is_empty() else Scenarios.NAMES[preset]
	if case_name in ["dam_break", "curved_channel", "wall_opening"] and (arrival_tick < 0 or \
			(size == 64 and arrival_tick > 150)):
		_fail("GPU %s downstream gauge did not arrive on time: %d" % [case_name, arrival_tick])
		return
	if case_name == "wall_opening" and (preopen_max_downstream > 0.000001 or \
			arrival_tick <= 75):
		_fail("GPU wall opening leaked before tick 75 or arrived too early: %.8f tick=%d" % [
			preopen_max_downstream, arrival_tick])
		return
	var path := "res://test_output/sandcastle_water_sand_coupling/验收/T03_gpu_standard_%s_%d_%d.csv" % [
		label, size, steps]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_fail("GPU scenario CSV unavailable")
		return
	file.store_string("\n".join(csv_rows) + "\n")
	file.close()
	print("PASS: GPU standard scenario %s grid=%d ticks=%d gauge_error=%.8f volume_error=%.8f final_h_error=%.8f final_q_error=%.8f max_closed_drift=%.8f arrival_tick=%d CSV=%s" % [
		label, size, steps, max_gauge_error,
		max_volume_error, max_h_error, max_q_error, maximum_closed_drift,
		arrival_tick, path])
	finished = true
	RenderingServer.call_on_render_thread(_release_success)


func _release_success() -> void:
	gpu_solver.release()
	call_deferred("_quit", 0)


func _watchdog() -> void:
	if finished:
		return
	if Time.get_ticks_msec() - watchdog_started_ms > 180000:
		_fail("GPU scenario callback timed out at tick %d" % tick_index)
		return
	await process_frame
	call_deferred("_watchdog")


func _fail(message: String) -> void:
	if finished:
		return
	finished = true
	printerr("FAIL: " + message)
	RenderingServer.call_on_render_thread(_release_failure)


func _release_failure() -> void:
	if gpu_solver != null:
		gpu_solver.release()
	call_deferred("_quit", 1)


func _quit(code: int) -> void:
	quit(code)

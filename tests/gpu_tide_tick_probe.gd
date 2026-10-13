extends SceneTree

const Domain = preload("res://scripts/simulation/sand_water_domain.gd")
const CpuSolver = preload("res://scripts/water/reference/shallow_water_solver.gd")
const GpuSolver = preload("res://scripts/simulation/gpu_shallow_solver.gd")

const DELTA := 1.0 / 30.0
const FREQUENCY_HZ := 0.25

var size := 64
var steps := 30
var compare_cpu := true
var tick_index := 0
var current_substeps := 0
var max_closure_error := 0.0
var initial_water_m3 := 0.0
var expected_substeps := PackedInt32Array()
var expected_source := PackedFloat32Array()
var expected_sink := PackedFloat32Array()
var expected_water := PackedFloat32Array()
var expected_gauge := PackedFloat32Array()
var cpu_gauge_transitions := 0
var last_cpu_wet := false
var gpu_gauge_transitions := 0
var last_gpu_wet := false
var gpu_wet_seen := false
var gpu_dry_seen := false
var last_gauge_depth := 0.0
var initial_domain: SandWaterDomain
var cpu_domain: SandWaterDomain
var cpu_solver: ShallowWaterReference
var gpu_solver: SandcastleGpuShallowSolver
var spirvs: Array[RDShaderSPIRV] = []
var readbacks := {}
var finished := false
var watchdog_started_ms := 0


func _init() -> void:
	call_deferred("_begin")


func _begin() -> void:
	var requested_size := int(OS.get_environment("SANDCASTLE_GPU_GRID"))
	if requested_size > 0:
		size = requested_size
	if size not in [64, 256]:
		_fail("GPU tide probe requires 64 or 256 grid")
		return
	compare_cpu = size == 64
	var requested_steps := int(OS.get_environment("SANDCASTLE_GPU_STEPS"))
	if requested_steps > 0:
		steps = requested_steps
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
	if compare_cpu:
		cpu_domain = Domain.new(size, 0.125)
	var domains: Array[SandWaterDomain] = [initial_domain]
	if compare_cpu:
		domains.append(cpu_domain)
	for domain in domains:
		for z in size:
			for x in size:
				var i: int = domain.index(x, z)
				domain.rock[i] = 0.30 * float(x) / float(size - 1)
				domain.water[i] = maxf(0.0, 0.15 - domain.rock[i])
	initial_water_m3 = initial_domain.total_water_m3()
	if compare_cpu:
		cpu_solver = CpuSolver.new(cpu_domain)
		last_cpu_wet = cpu_domain.water[cpu_domain.index(size / 2, size / 2)] > 0.002
	last_gpu_wet = initial_domain.water[initial_domain.index(size / 2, size / 2)] > 0.002
	gpu_wet_seen = last_gpu_wet
	gpu_dry_seen = not last_gpu_wet
	if compare_cpu:
		for tick in steps:
			cpu_solver.max_substeps_used = 0
			cpu_solver.set_tide_boundary(_sea_level(tick))
			cpu_solver.step(DELTA)
			expected_substeps.append(cpu_solver.max_substeps_used)
			expected_source.append(cpu_domain.water_source_m3)
			expected_sink.append(cpu_domain.water_sink_m3)
			expected_water.append(cpu_domain.total_water_m3())
			var gauge: float = cpu_domain.water[cpu_domain.index(size / 2, size / 2)]
			expected_gauge.append(gauge)
			var cpu_wet := gauge > 0.002
			if cpu_wet != last_cpu_wet:
				cpu_gauge_transitions += 1
				last_cpu_wet = cpu_wet
			if cpu_solver.negative_depth_events != 0 or cpu_solver.overload_events != 0 or \
					cpu_domain.sim_tick != tick + 1:
				_fail("CPU tide comparator failed at tick %d" % tick)
				return
	RenderingServer.call_on_render_thread(_render_setup)
	watchdog_started_ms = Time.get_ticks_msec()
	call_deferred("_watchdog")


func _sea_level(tick: int) -> float:
	return 0.12 + 0.16 * sin(float(tick) * DELTA * TAU * FREQUENCY_HZ)


func _render_setup() -> void:
	gpu_solver = GpuSolver.new()
	if not gpu_solver.initialize(RenderingServer.get_rendering_device(), initial_domain,
			spirvs[0], spirvs[1], spirvs[2], spirvs[3], spirvs[4], spirvs[5], spirvs[6], spirvs[7]):
		call_deferred("_fail", "GPU tide solver initialization failed")
		return
	_render_boundary()


func _render_boundary() -> void:
	if not gpu_solver.dispatch_tide_boundary(_sea_level(tick_index)):
		call_deferred("_fail", "GPU tide boundary failed at tick %d" % tick_index)
		return
	var error := gpu_solver.request_tide_ledger(_on_ledger)
	if error != OK:
		call_deferred("_fail", "GPU tide ledger readback failed %d" % error)


func _on_ledger(_source_m3: float, _sink_m3: float, _revision: int, valid: bool) -> void:
	call_deferred("_ledger_ready", valid)


func _ledger_ready(valid: bool) -> void:
	if finished:
		return
	if not valid or gpu_solver.tide_ledger_pending:
		_fail("GPU tide ledger invalid at tick %d" % tick_index)
		return
	RenderingServer.call_on_render_thread(_render_cfl)


func _render_cfl() -> void:
	var error := gpu_solver.request_cfl_tiles(_on_tiles)
	if error != OK:
		call_deferred("_fail", "GPU tide CFL readback failed %d" % error)


func _on_tiles(data: PackedByteArray, revision: int) -> void:
	call_deferred("_check_tiles", data, revision)


func _check_tiles(data: PackedByteArray, revision: int) -> void:
	if finished:
		return
	var count := gpu_solver.substeps_from_cfl(DELTA, data)
	current_substeps = count
	if count <= 0 or gpu_solver.overload_events != 0:
		_fail("GPU tide CFL overload at tick %d" % tick_index)
		return
	if compare_cpu and count != expected_substeps[tick_index]:
		_fail("GPU tide tick=%d CFL=%d CPU=%d" % [tick_index, count, expected_substeps[tick_index]])
		return
	RenderingServer.call_on_render_thread(_render_advance.bind(data, revision))


func _render_advance(data: PackedByteArray, revision: int) -> void:
	if not gpu_solver.dispatch_tick_with_cfl(DELTA, data, revision):
		call_deferred("_fail", "GPU tide advance failed at tick %d" % tick_index)
		return
	if compare_cpu:
		var ledger_error := maxf(absf(gpu_solver.water_source_m3 - expected_source[tick_index]),
			absf(gpu_solver.water_sink_m3 - expected_sink[tick_index]))
		if ledger_error > 0.0001:
			call_deferred("_fail", "GPU tide cumulative ledger drift at tick %d: %.7f" % [
				tick_index, ledger_error])
			return
	var gauge_error := gpu_solver.request_gauge_depth(size / 2, size / 2, _on_gauge)
	if gauge_error != OK:
		call_deferred("_fail", "GPU tide gauge request failed %d" % gauge_error)


func _on_gauge(data: PackedByteArray, revision: int) -> void:
	call_deferred("_record_gauge", data, revision)


func _record_gauge(data: PackedByteArray, revision: int) -> void:
	if finished:
		return
	if data.size() != 4 or revision != gpu_solver.state_revision:
		_fail("GPU tide gauge bytes/revision mismatch at tick %d" % tick_index)
		return
	var gauge := data.to_float32_array()[0]
	if not is_finite(gauge) or gauge < -0.000001 or \
			(compare_cpu and absf(gauge - expected_gauge[tick_index]) > 0.0001):
		_fail("GPU tide gauge mismatch tick=%d gpu=%.7f" % [tick_index, gauge])
		return
	var wet := gauge > 0.002
	gpu_wet_seen = gpu_wet_seen or wet
	gpu_dry_seen = gpu_dry_seen or not wet
	if wet != last_gpu_wet:
		gpu_gauge_transitions += 1
		last_gpu_wet = wet
	last_gauge_depth = gauge
	RenderingServer.call_on_render_thread(_render_audit)


func _render_audit() -> void:
	var error := gpu_solver.request_audit_tiles(_on_audit)
	if error != OK:
		call_deferred("_fail", "GPU tide audit request failed %d" % error)


func _on_audit(data: PackedByteArray, revision: int) -> void:
	call_deferred("_record_audit", data, revision)


func _record_audit(data: PackedByteArray, revision: int) -> void:
	if finished:
		return
	var audit := gpu_solver.decode_audit_tiles(data)
	if revision != gpu_solver.state_revision or not audit.get("valid", false):
		_fail("GPU tide audit bytes/revision mismatch at tick %d" % tick_index)
		return
	var volume: float = audit["water_m3"]
	var minimum_depth: float = audit["minimum_depth_m"]
	var invalid_cells: int = audit["invalid_cells"]
	var negative_cells: int = audit["negative_cells"]
	var closure_error := absf(volume - initial_water_m3 - \
		gpu_solver.water_source_m3 + gpu_solver.water_sink_m3)
	max_closure_error = maxf(max_closure_error, closure_error)
	var budget_scale := maxf(maxf(initial_water_m3,
		gpu_solver.water_source_m3), 0.001)
	if minimum_depth < -0.000001 or invalid_cells != 0 or negative_cells != 0 or \
			gpu_solver.nan_events != 0 or gpu_solver.overload_events != 0 or \
			(compare_cpu and absf(volume - expected_water[tick_index]) > 0.001) or \
			closure_error > maxf(0.001, budget_scale * 0.005):
		_fail("GPU tide audit tick=%d min=%.7f bad=%d negative=%d volume=%.7f closure=%.7f" % [
			tick_index, minimum_depth, invalid_cells, negative_cells, volume, closure_error])
		return
	print("TIDE_TICK,%d,%.6f,%.6f,%d,%.9f,%.9f,%s,%s,%s,%.9f,%.9f,%s,%.9f,%d,%d,%d,%d" % [
		tick_index + 1, float(tick_index + 1) * DELTA, _sea_level(tick_index),
		current_substeps, gpu_solver.water_source_m3, gpu_solver.water_sink_m3,
		"%.9f" % expected_source[tick_index] if compare_cpu else "",
		"%.9f" % expected_sink[tick_index] if compare_cpu else "",
		"%.9f" % expected_water[tick_index] if compare_cpu else "",
		volume, last_gauge_depth, "%.9f" % expected_gauge[tick_index] if compare_cpu else "", minimum_depth,
		invalid_cells, negative_cells, gpu_solver.nan_events, gpu_solver.overload_events])
	tick_index += 1
	if tick_index < steps:
		RenderingServer.call_on_render_thread(_render_boundary)
		return
	RenderingServer.call_on_render_thread(_render_read_final)


func _render_read_final() -> void:
	for field in ["water", "momentum_x", "momentum_z"]:
		var error := gpu_solver.request_data(field, _on_state.bind(field))
		if error != OK:
			call_deferred("_fail", "GPU tide state readback failed %d" % error)
			return


func _on_state(data: PackedByteArray, field: String) -> void:
	call_deferred("_record_state", field, data)


func _record_state(field: String, data: PackedByteArray) -> void:
	if finished:
		return
	readbacks[field] = data
	if readbacks.size() != 3:
		return
	var actual_h: PackedFloat32Array = readbacks["water"].to_float32_array()
	var actual_qx: PackedFloat32Array = readbacks["momentum_x"].to_float32_array()
	var actual_qz: PackedFloat32Array = readbacks["momentum_z"].to_float32_array()
	if actual_h.size() != size * size or actual_qx.size() != size * size or actual_qz.size() != size * size:
		_fail("GPU tide state dimensions mismatch")
		return
	var max_h_error := 0.0
	var max_q_error := 0.0
	var total_gpu := 0.0
	for i in size * size:
		if not is_finite(actual_h[i]) or actual_h[i] < -0.000001 or \
				not is_finite(actual_qx[i]) or not is_finite(actual_qz[i]):
			_fail("GPU tide nonfinite/negative final state")
			return
		if compare_cpu:
			max_h_error = maxf(max_h_error, absf(actual_h[i] - cpu_domain.water[i]))
			max_q_error = maxf(max_q_error, maxf(absf(actual_qx[i] - cpu_solver.momentum_x[i]),
				absf(actual_qz[i] - cpu_solver.momentum_y[i])))
		total_gpu += actual_h[i] * initial_domain.cell_area_m2
	var ledger_error := 0.0
	if compare_cpu:
		ledger_error = maxf(absf(gpu_solver.water_source_m3 - cpu_domain.water_source_m3),
			absf(gpu_solver.water_sink_m3 - cpu_domain.water_sink_m3))
	var closure_error := absf(total_gpu - initial_water_m3 - \
		gpu_solver.water_source_m3 + gpu_solver.water_sink_m3)
	var budget_scale := maxf(maxf(initial_water_m3,
		gpu_solver.water_source_m3), 0.001)
	if gpu_solver.water_source_m3 <= 0.0 or gpu_solver.water_sink_m3 <= 0.0 or \
			gpu_solver.nan_events != 0 or gpu_solver.overload_events != 0 or \
			(compare_cpu and (max_h_error > 0.0001 or max_q_error > 0.001 or \
			ledger_error > 0.0001 or gpu_gauge_transitions != cpu_gauge_transitions)) or \
			closure_error > maxf(0.001, budget_scale * 0.005) or \
			(steps >= 120 and (not gpu_wet_seen or not gpu_dry_seen or gpu_gauge_transitions == 0)):
		_fail("GPU tide mismatch h=%.7f q=%.7f ledger=%.7f closure=%.7f" % [
			max_h_error, max_q_error, ledger_error, closure_error])
		return
	print("PASS: GPU tide %d-square %d-tick source=%.6f sink=%.6f h=%.8f q=%.8f ledger_error=%.8f wet_dry_transitions=%d max_closure=%.8f final_closure=%.8f cpu_comparator=%s" % [
		size, steps, gpu_solver.water_source_m3, gpu_solver.water_sink_m3,
		max_h_error, max_q_error, ledger_error, gpu_gauge_transitions,
		max_closure_error, closure_error, str(compare_cpu)])
	finished = true
	RenderingServer.call_on_render_thread(_release_success)


func _release_success() -> void:
	gpu_solver.release()
	call_deferred("_finish", 0)


func _watchdog() -> void:
	if finished:
		return
	if Time.get_ticks_msec() - watchdog_started_ms > 540000:
		_fail("GPU tide callback timed out")
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
	call_deferred("_finish", 1)


func _finish(code: int) -> void:
	quit(code)

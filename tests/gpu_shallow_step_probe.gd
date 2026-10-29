extends SceneTree

const Domain = preload("res://scripts/simulation/sand_water_domain.gd")
const ShallowWater = preload("res://scripts/water/reference/shallow_water_solver.gd")
const GpuSolver = preload("res://scripts/simulation/gpu_shallow_solver.gd")

var case_name := "dam_break"
var steps := 1
var size := 64
var delta := 1.0 / 120.0
var initial_domain: SandWaterDomain
var cpu_domain: SandWaterDomain
var cpu_solver: ShallowWaterReference
var spirvs: Array[RDShaderSPIRV] = []
var gpu_solver: SandcastleGpuShallowSolver
var readbacks := {}
var finished := false
var frames_waited := 0


func _init() -> void:
	call_deferred("_begin")


func _begin() -> void:
	var requested := OS.get_environment("SANDCASTLE_STEP_CASE")
	if not requested.is_empty():
		case_name = requested
	if case_name not in ["dam_break", "sloping_lake", "wall", "isolated_pool", "tide_rise", "tide_fall"]:
		_fail("unknown step case")
		return
	if case_name == "isolated_pool":
		delta = 0.25  # Deliberately over CFL: tests integrated positive-outflow limiter.
	steps = maxi(1, int(OS.get_environment("SANDCASTLE_GPU_STEPS")))
	var requested_size := int(OS.get_environment("SANDCASTLE_GPU_GRID"))
	if requested_size > 0:
		size = requested_size
	if size not in [64, 256]:
		_fail("GPU step probe only supports 64 or 256 grid")
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
	cpu_domain = Domain.new(size, 0.125)
	_initialize_case(initial_domain)
	_initialize_case(cpu_domain)
	cpu_solver = ShallowWater.new(cpu_domain)
	if case_name.begins_with("tide_"):
		cpu_solver.set_tide_boundary(_tide_level())
	for tick in steps:
		if case_name == "isolated_pool":
			cpu_solver._step_once(delta)
			cpu_solver._limit_momentum()
			cpu_domain.sim_tick += 1
		else:
			cpu_solver.step(delta)
		if cpu_domain.sim_tick != tick + 1:
			_fail("CPU comparator stopped before requested steps")
			return
	if (case_name != "isolated_pool" and cpu_solver.max_substeps_used != 1) or cpu_solver.negative_depth_events != 0:
		_fail("CPU comparator did not use one clean substep")
		return
	RenderingServer.call_on_render_thread(_render_step)
	call_deferred("_watchdog")


func _initialize_case(domain: SandWaterDomain) -> void:
	for z in size:
		for x in size:
			var i: int = domain.index(x, z)
			domain.sediment[i] = 0.01
			domain.wetness[i] = 0.75
			domain.compaction[i] = 0.5
			match case_name:
				"dam_break":
					domain.water[i] = 0.45 if x < size / 2 else 0.0
				"sloping_lake":
					domain.rock[i] = 0.2 * float(x) / float(size - 1) + 0.04 * float(z) / float(size - 1)
					domain.water[i] = 0.5 - domain.rock[i]
				"wall":
					domain.water[i] = 0.45 if x < size / 2 else 0.0
					if x == size / 2:
						domain.obstacle[i] = 1.0
				"isolated_pool":
					domain.water[i] = 1.0 if x == size / 2 and z == size / 2 else 0.0
				"tide_rise", "tide_fall":
					domain.rock[i] = 0.04 * float(z) / float(size - 1)
					domain.water[i] = 0.10 if case_name == "tide_rise" else 0.20


func _tide_level() -> float:
	return 0.35 if case_name == "tide_rise" else 0.02


func _render_step() -> void:
	gpu_solver = GpuSolver.new()
	if not gpu_solver.initialize(RenderingServer.get_rendering_device(), initial_domain,
			spirvs[0], spirvs[1], spirvs[2], spirvs[3], spirvs[4], spirvs[5], spirvs[6], spirvs[7]):
		call_deferred("_fail", "GPU shallow solver initialization failed")
		return
	if case_name.begins_with("tide_") and not gpu_solver.dispatch_tide_boundary(_tide_level()):
		call_deferred("_fail", "GPU tide boundary dispatch failed")
		return
	for tick in steps:
		if not gpu_solver.dispatch_substep(delta):
			call_deferred("_fail", "GPU shallow substep dispatch failed at %d" % tick)
			return
	for field in ["water", "momentum_x", "momentum_z", "flux",
			"sediment", "wetness", "compaction"]:
		var error: Error = gpu_solver.request_data(field, _on_data.bind(field))
		if error != OK:
			call_deferred("_fail", "GPU %s readback failed %d" % [field, error])
			return
	if case_name.begins_with("tide_"):
		var tide_error: Error = gpu_solver.request_tide_ledger(_on_ledger)
		if tide_error != OK:
			call_deferred("_fail", "GPU tide ledger readback failed %d" % tide_error)


func _on_ledger(source_m3: float, sink_m3: float, revision: int, valid: bool) -> void:
	call_deferred("_record_ledger", source_m3, sink_m3, revision, valid)


func _record_ledger(source_m3: float, sink_m3: float, revision: int, valid: bool) -> void:
	if finished:
		return
	readbacks["tide_ledger"] = [source_m3, sink_m3, revision, valid]
	if readbacks.size() == 8:
		_verify()


func _on_data(data: PackedByteArray, field: String) -> void:
	call_deferred("_record", field, data)


func _record(field: String, data: PackedByteArray) -> void:
	if finished:
		return
	readbacks[field] = data
	if readbacks.size() == (8 if case_name.begins_with("tide_") else 7):
		_verify()


func _verify() -> void:
	var water: PackedByteArray = readbacks["water"]
	var qx: PackedByteArray = readbacks["momentum_x"]
	var qz: PackedByteArray = readbacks["momentum_z"]
	var flux: PackedByteArray = readbacks["flux"]
	if water.size() != size * size * 4 or qx.size() != water.size() or qz.size() != water.size() or flux.size() != size * size * 16:
		_fail("GPU state readback dimensions mismatch")
		return
	var actual_h := water.to_float32_array()
	var actual_qx := qx.to_float32_array()
	var actual_qz := qz.to_float32_array()
	var actual_flux := flux.to_float32_array()
	var sediment: PackedFloat32Array = readbacks["sediment"].to_float32_array()
	if sediment.size() != size * size:
		_fail("GPU sediment readback dimensions mismatch")
		return
	var wetness_image := Image.create_from_data(size, size, false,
		Image.FORMAT_RH, readbacks["wetness"])
	var compaction_image := Image.create_from_data(size, size, false,
		Image.FORMAT_RH, readbacks["compaction"])
	wetness_image.convert(Image.FORMAT_RF)
	compaction_image.convert(Image.FORMAT_RF)
	var wetness: PackedFloat32Array = wetness_image.get_data().to_float32_array()
	var compaction: PackedFloat32Array = compaction_image.get_data().to_float32_array()
	if wetness.size() != size * size or compaction.size() != size * size:
		_fail("GPU half-float state readback dimensions mismatch")
		return
	var max_h_error := 0.0
	var max_momentum_error := 0.0
	var max_flux_error := 0.0
	var gpu_total_water := 0.0
	for i in size * size:
		if absf(sediment[i] - initial_domain.sediment[i]) > 0.000001 or \
				absf(wetness[i] - initial_domain.wetness[i]) > 0.001 or \
				absf(compaction[i] - initial_domain.compaction[i]) > 0.001:
			_fail("GPU inert state drift at %d" % i)
			return
		if is_nan(actual_h[i]) or is_inf(actual_h[i]) or actual_h[i] < -0.000001:
			_fail("GPU water nonfinite or negative at %d" % i)
			return
		max_h_error = maxf(max_h_error, absf(actual_h[i] - cpu_domain.water[i]))
		max_momentum_error = maxf(max_momentum_error,
			maxf(absf(actual_qx[i] - cpu_solver.momentum_x[i]), absf(actual_qz[i] - cpu_solver.momentum_y[i])))
		var expected := [cpu_domain.flux_left[i], cpu_domain.flux_right[i],
			cpu_domain.flux_up[i], cpu_domain.flux_down[i]]
		for direction in 4:
			max_flux_error = maxf(max_flux_error, absf(actual_flux[i * 4 + direction] - expected[direction]))
		gpu_total_water += actual_h[i] * initial_domain.cell_area_m2
	var ledger_delta := cpu_domain.water_source_m3 - cpu_domain.water_sink_m3
	var conservation_error := absf(gpu_total_water - initial_domain.total_water_m3() - ledger_delta)
	if case_name.begins_with("tide_"):
		var tide_ledger: Array = readbacks["tide_ledger"]
		var gpu_tide_delta: float = tide_ledger[0] - tide_ledger[1]
		if not tide_ledger[3] or gpu_solver.tide_ledger_pending or \
				absf(tide_ledger[0] - cpu_domain.water_source_m3) > 0.0001 or \
				absf(tide_ledger[1] - cpu_domain.water_sink_m3) > 0.0001 or \
				absf(gpu_solver.water_source_m3 - tide_ledger[0]) > 0.0001 or \
				absf(gpu_solver.water_sink_m3 - tide_ledger[1]) > 0.0001 or \
				absf(gpu_tide_delta - ledger_delta) > 0.0001:
			_fail("GPU tide ledger mismatch %.7f vs %.7f" % [gpu_tide_delta, ledger_delta])
			return
	if max_h_error > 0.0001 or max_momentum_error > 0.001 or max_flux_error > 0.0001 or \
			absf(gpu_total_water - cpu_domain.total_water_m3()) > 0.0001 or conservation_error > 0.0001:
		_fail("CPU/GPU mismatch h=%.7f q=%.7f flux=%.7f mass=%.7f" % [
			max_h_error, max_momentum_error, max_flux_error,
			conservation_error])
		return
	if case_name == "isolated_pool":
		var center := (size / 2) * size + size / 2
		if actual_h[center] > 0.000001 or actual_h[center + 1] <= 0.0 or actual_h[center - 1] <= 0.0 or \
				actual_h[center + size] <= 0.0 or actual_h[center - size] <= 0.0:
			_fail("integrated positivity limiter did not drain equally to four neighbors")
			return
	print("PASS: GPU shallow %d-square %d-substep %s CPU agreement h=%.8f q=%.8f flux=%.8f" % [
		size, steps, case_name, max_h_error, max_momentum_error, max_flux_error])
	finished = true
	RenderingServer.call_on_render_thread(_release_success)


func _release_success() -> void:
	if gpu_solver != null:
		gpu_solver.release()
	call_deferred("_finish", 0)


func _watchdog() -> void:
	if finished:
		return
	frames_waited += 1
	if frames_waited > 300:
		_fail("GPU shallow callback timed out")
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

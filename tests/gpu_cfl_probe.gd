extends SceneTree

const Domain = preload("res://scripts/simulation/sand_water_domain.gd")
const CpuSolver = preload("res://scripts/water/reference/shallow_water_solver.gd")
const GpuSolver = preload("res://scripts/simulation/gpu_shallow_solver.gd")

const DELTA := 1.0 / 30.0

var size := 64
var steps := 1
var tick_index := 0
var expected_substeps := PackedInt32Array()
var initial_domain: SandWaterDomain
var cpu_domain: SandWaterDomain
var cpu_solver: ShallowWaterReference
var gpu_solver: SandcastleGpuShallowSolver
var spirvs: Array[RDShaderSPIRV] = []
var finished := false
var frames_waited := 0


func _init() -> void:
	call_deferred("_begin")


func _begin() -> void:
	var requested_size := int(OS.get_environment("SANDCASTLE_GPU_GRID"))
	if requested_size > 0:
		size = requested_size
	if size not in [64, 256]:
		_fail("CFL probe requires 64 or 256 grid")
		return
	steps = maxi(1, int(OS.get_environment("SANDCASTLE_GPU_STEPS")))
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
	for domain in [initial_domain, cpu_domain]:
		for z in size:
			for x in size:
				domain.water[domain.index(x, z)] = 0.45 if x < size / 2 else 0.0
	cpu_solver = CpuSolver.new(cpu_domain)
	for tick in steps:
		cpu_solver.max_substeps_used = 0
		cpu_solver.step(DELTA)
		expected_substeps.append(cpu_solver.max_substeps_used)
		if cpu_solver.negative_depth_events != 0 or cpu_solver.max_substeps_used < 2 or cpu_domain.sim_tick != tick + 1:
			_fail("CPU comparator did not require multiple clean substeps at tick %d" % tick)
			return
	RenderingServer.call_on_render_thread(_render_setup)
	call_deferred("_watchdog")


func _render_setup() -> void:
	gpu_solver = GpuSolver.new()
	if not gpu_solver.initialize(RenderingServer.get_rendering_device(), initial_domain,
			spirvs[0], spirvs[1], spirvs[2], spirvs[3], spirvs[4], spirvs[5], spirvs[6], spirvs[7]):
		call_deferred("_fail", "GPU CFL solver initialization failed")
		return
	var error := gpu_solver.request_cfl_tiles(_on_tiles)
	if error != OK:
		call_deferred("_fail", "GPU tile-max request failed %d" % error)


func _on_tiles(data: PackedByteArray, revision: int) -> void:
	call_deferred("_check_tiles", data, revision)


func _check_tiles(data: PackedByteArray, revision: int) -> void:
	if finished:
		return
	var substeps := gpu_solver.substeps_from_cfl(DELTA, data)
	if substeps != expected_substeps[tick_index]:
		_fail("GPU CFL tick=%d substeps=%d CPU=%d" % [
			tick_index, substeps, expected_substeps[tick_index]])
		return
	var oversized := PackedFloat32Array()
	oversized.resize(size * size / 64)
	oversized.fill(1000.0)
	if gpu_solver.substeps_from_cfl(DELTA, oversized.to_byte_array()) <= 64:
		_fail("GPU CFL overload input not rejected by bound")
		return
	RenderingServer.call_on_render_thread(_render_tick.bind(data, substeps, revision))


func _render_tick(data: PackedByteArray, substeps: int, revision: int) -> void:
	if gpu_solver.dispatch_tick_with_cfl(DELTA, data, revision - 1):
		call_deferred("_fail", "GPU CFL accepted stale state revision")
		return
	if not gpu_solver.dispatch_tick_with_cfl(DELTA, data, revision) or gpu_solver.max_substeps_used < substeps:
		call_deferred("_fail", "GPU CFL tick dispatch failed")
		return
	tick_index += 1
	if tick_index < steps:
		var next_error := gpu_solver.request_cfl_tiles(_on_tiles)
		if next_error != OK:
			call_deferred("_fail", "next GPU CFL tile-max request failed %d" % next_error)
		return
	for field in ["water", "momentum_x", "momentum_z"]:
		var error := gpu_solver.request_data(field, _on_state.bind(field))
		if error != OK:
			call_deferred("_fail", "GPU CFL readback failed %d" % error)
			return


func _on_state(data: PackedByteArray, field: String) -> void:
	call_deferred("_record_state", field, data)


var readbacks := {}


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
		_fail("GPU CFL state dimensions mismatch")
		return
	var max_h_error := 0.0
	var max_q_error := 0.0
	var total_gpu := 0.0
	for i in size * size:
		if not is_finite(actual_h[i]) or actual_h[i] < -0.000001:
			_fail("GPU CFL nonfinite/negative depth")
			return
		max_h_error = maxf(max_h_error, absf(actual_h[i] - cpu_domain.water[i]))
		max_q_error = maxf(max_q_error, maxf(absf(actual_qx[i] - cpu_solver.momentum_x[i]),
			absf(actual_qz[i] - cpu_solver.momentum_y[i])))
		total_gpu += actual_h[i] * initial_domain.cell_area_m2
	if max_h_error > 0.0001 or max_q_error > 0.001 or \
			absf(total_gpu - initial_domain.total_water_m3()) > 0.0001:
		_fail("GPU CFL CPU mismatch h=%.7f q=%.7f" % [max_h_error, max_q_error])
		return
	print("PASS: GPU CFL %d-square %d-tick substeps_max=%d h=%.8f q=%.8f tile_bytes=%d" % [
		size, steps, gpu_solver.max_substeps_used, max_h_error, max_q_error, size * size / 16])
	finished = true
	RenderingServer.call_on_render_thread(_release_success)


func _release_success() -> void:
	gpu_solver.release()
	call_deferred("_finish", 0)


func _watchdog() -> void:
	if finished:
		return
	frames_waited += 1
	if frames_waited > 300:
		_fail("GPU CFL callback timed out")
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

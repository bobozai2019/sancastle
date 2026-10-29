extends SceneTree

const Domain = preload("res://scripts/simulation/sand_water_domain.gd")
const Solver = preload("res://scripts/simulation/gpu_shallow_solver.gd")
const Coupler = preload("res://scripts/simulation/erosion/gpu_sediment_coupler.gd")
const SandAudit = preload("res://scripts/simulation/gpu_sand_audit.gd")
const GRID := 64
const CELL_M := 0.125
const DELTA_S := 1.0 / 120.0

var domain: SandWaterDomain
var solver: SandcastleGpuShallowSolver
var coupler: SandcastleGpuSedimentCoupler
var audit: SandcastleGpuSandAudit
var readbacks := {}
var before_boundary := {}
var after_boundary := {}
var finished := false
var started_ms := 0
var steps := 2
var boundary_between_steps := false


func _init() -> void:
	call_deferred("_begin")


func _begin() -> void:
	started_ms = Time.get_ticks_msec()
	var requested_steps := int(OS.get_environment("SANDCASTLE_SEDIMENT_STEPS"))
	if requested_steps > 0:
		steps = requested_steps
	boundary_between_steps = OS.get_environment("SANDCASTLE_SEDIMENT_BOUNDARY") == "1"
	domain = Domain.new(GRID, CELL_M)
	for z in GRID:
		for x in GRID:
			var i: int = domain.index(x, z)
			domain.water[i] = 0.45 if x < GRID / 2 else 0.10
			domain.sand[i] = 0.08 if x < GRID / 2 else 0.0
			# Dilute incoming load leaves capacity to erode; the downstream reach
			# stays overloaded. The old 0.015 load saturates the new capacity.
			domain.sediment[i] = 0.000015 if x < GRID / 2 else 0.010 if x >= 48 else 0.0
			domain.wetness[i] = 0.2
			domain.compaction[i] = 0.1
	RenderingServer.call_on_render_thread(_render_run)
	call_deferred("_watchdog")


func _render_run() -> void:
	var paths := [
		"res://shaders/simulation/shallow_edge_flux.glsl",
		"res://shaders/simulation/shallow_drain_scale.glsl",
		"res://shaders/simulation/shallow_update_state.glsl",
		"res://shaders/simulation/shallow_tide_boundary.glsl",
		"res://shaders/simulation/shallow_cfl_tiles.glsl",
		"res://shaders/simulation/shallow_gauge_depth.glsl",
		"res://shaders/simulation/shallow_audit_tiles.glsl",
		"res://shaders/simulation/shallow_tool_patch.glsl",
		"res://shaders/simulation/erosion/sediment_step.glsl",
		"res://shaders/simulation/erosion/copy_after_boundary.glsl",
		"res://shaders/simulation/shallow_sand_audit_tiles.glsl"]
	var spirvs: Array[RDShaderSPIRV] = []
	for path in paths:
		var file: RDShaderFile = load(path)
		if file == null or file.get_spirv() == null:
			call_deferred("_fail", "shader import missing: " + path)
			return
		spirvs.append(file.get_spirv())
	solver = Solver.new()
	if not solver.initialize(RenderingServer.get_rendering_device(), domain,
			spirvs[0], spirvs[1], spirvs[2], spirvs[3], spirvs[4], spirvs[5],
			spirvs[6], spirvs[7]):
		call_deferred("_fail", "GPU water solver initialization failed")
		return
	coupler = Coupler.new()
	if not coupler.initialize(solver, spirvs[8], spirvs[9]):
		call_deferred("_fail", "GPU sediment coupler initialization failed")
		return
	audit = SandAudit.new()
	if not audit.initialize(solver, spirvs[10]):
		call_deferred("_fail", "GPU sand audit initialization failed")
		return
	if boundary_between_steps:
		if steps != 2 or not solver.dispatch_substep(DELTA_S) or \
				not coupler.dispatch_after_water_substep(DELTA_S):
			call_deferred("_fail", "first coupled substep before boundary failed")
			return
		for field in ["sand", "sediment"]:
			if solver.request_data(field, _on_boundary_data.bind(field, false)) != OK:
				call_deferred("_fail", "pre-boundary readback failed: " + field)
				return
		return
	for step in steps:
		if not solver.dispatch_substep(DELTA_S) or not coupler.dispatch_after_water_substep(DELTA_S):
			call_deferred("_fail", "coupled substep dispatch failed at %d" % step)
			return
	_render_collect_final()


func _on_boundary_data(data: PackedByteArray, field: String, after: bool) -> void:
	call_deferred("_record_boundary_data", data, field, after)


func _record_boundary_data(data: PackedByteArray, field: String, after: bool) -> void:
	if finished:
		return
	var target: Dictionary = after_boundary if after else before_boundary
	target[field] = data.to_float32_array()
	if target.size() != 2:
		return
	if not after:
		RenderingServer.call_on_render_thread(_render_boundary_copy)
		return
	for key in ["sand", "sediment"]:
		var previous: PackedFloat32Array = before_boundary[key]
		var current: PackedFloat32Array = after_boundary[key]
		if previous.size() != GRID * GRID or current.size() != previous.size():
			_fail("boundary copy %s size mismatch" % key)
			return
		for i in previous.size():
			if current[i] != previous[i]:
				_fail("boundary copy changed %s at cell %d" % [key, i])
				return
	RenderingServer.call_on_render_thread(_render_second_step)


func _render_boundary_copy() -> void:
	if not solver.dispatch_boundary_injection(0.001) or \
			not coupler.dispatch_after_boundary():
		call_deferred("_fail", "boundary copy between coupled steps failed")
		return
	for field in ["sand", "sediment"]:
		if solver.request_data(field, _on_boundary_data.bind(field, true)) != OK:
			call_deferred("_fail", "post-boundary readback failed: " + field)
			return


func _render_second_step() -> void:
	if not solver.dispatch_substep(DELTA_S) or not coupler.dispatch_after_water_substep(DELTA_S):
		call_deferred("_fail", "second coupled substep after boundary failed")
		return
	_render_collect_final()


func _render_collect_final() -> void:
	for field in ["sand", "sediment", "water", "flux"]:
		var error: Error = solver.request_data(field, _on_data.bind(field))
		if error != OK:
			call_deferred("_fail", "readback failed: %s %d" % [field, error])
			return
	if audit.request(_on_audit) != OK:
		call_deferred("_fail", "GPU sand audit request failed")


func _on_data(data: PackedByteArray, field: String) -> void:
	call_deferred("_record_data", data, field)


func _record_data(data: PackedByteArray, field: String) -> void:
	if finished:
		return
	readbacks[field] = data.to_float32_array()
	if readbacks.size() == 5:
		_verify()


func _on_audit(data: PackedByteArray, _revision: int) -> void:
	call_deferred("_record_audit", data)


func _record_audit(data: PackedByteArray) -> void:
	if finished:
		return
	readbacks["audit"] = audit.decode(data)
	if readbacks.size() == 5:
		_verify()


func _verify() -> void:
	var area := CELL_M * CELL_M
	var initial_total := 0.0
	var final_total := 0.0
	var min_sand := INF
	var min_sediment := INF
	for i in GRID * GRID:
		initial_total += (domain.sand[i] + domain.sediment[i]) * area
		var bed: float = readbacks["sand"][i]
		var suspended: float = readbacks["sediment"][i]
		if not is_finite(bed) or not is_finite(suspended):
			_fail("nonfinite sand/sediment at %d" % i)
			return
		final_total += (bed + suspended) * area
		min_sand = minf(min_sand, bed)
		min_sediment = minf(min_sediment, suspended)
	var closure := absf(final_total - initial_total)
	var tile_audit: Dictionary = readbacks["audit"]
	if not tile_audit.get("valid", false) or tile_audit.invalid_cells != 0 or \
			tile_audit.negative_cells != 0 or \
			absf(tile_audit.sand_m3 + tile_audit.sediment_m3 - final_total) > 0.00001:
		_fail("nonzero-sediment GPU tile audit disagrees with full readback")
		return
	var closure_limit := maxf(0.000005, initial_total * 0.0001)
	if closure > closure_limit or min_sand < -0.000001 or min_sediment < -0.000001:
		_fail("sand mass or positivity failed: closure=%.9f min=%.9f/%.9f" % [
			closure, min_sand, min_sediment])
		return
	if steps > 2:
		print("PASS: GPU sediment conservative long run steps=%d closure=%.9f relative=%.9f min_sand=%.9f min_sediment=%.9f audit_suspended_m3=%.9f" % [
			steps, closure, closure / initial_total, min_sand, min_sediment,
			tile_audit.sediment_m3])
		_finish(0)
		return
	var donor: int = domain.index(GRID / 2 - 1, GRID / 2)
	var receiver: int = domain.index(GRID / 2, GRID / 2)
	var cross_flux: float = readbacks["flux"][donor * 4 + 1]
	var received: float = readbacks["sediment"][receiver]
	if cross_flux <= 0.0 or received <= 0.0 or domain.sediment[receiver] != 0.0:
		_fail("sediment did not cross the water front: flux=%.9f received=%.9f" % [
			cross_flux, received])
		return
	var eroded: float = domain.sand[donor] - readbacks["sand"][donor]
	if eroded <= 0.0:
		_fail("flowing donor did not erode: %.9f" % eroded)
		return
	var settling_cell: int = domain.index(48, GRID / 2)
	var deposited: float = readbacks["sand"][settling_cell] - domain.sand[settling_cell]
	if deposited <= 0.0:
		_fail("downstream low-speed cell did not deposit: %.9f" % deposited)
		return
	print("PASS: GPU sediment conservative water-flux transport and erosion " +
		"closure=%.9f min_sand=%.9f min_sediment=%.9f cross_flux=%.9f " % [
		closure, min_sand, min_sediment, cross_flux] +
		"received=%.9f eroded=%.9f deposited=%.9f audit_suspended_m3=%.9f boundary=%s copy_exact=%s" % [
			received, eroded, deposited, tile_audit.sediment_m3,
			str(boundary_between_steps), str(boundary_between_steps and after_boundary.size() == 2)])
	_finish(0)


func _watchdog() -> void:
	if finished:
		return
	if Time.get_ticks_msec() - started_ms > (120000 if steps > 3600 else 30000):
		_fail("GPU sediment probe timed out")
		return
	await process_frame
	call_deferred("_watchdog")


func _fail(message: String) -> void:
	if finished:
		return
	printerr("FAIL: " + message)
	_finish(1)


func _finish(code: int) -> void:
	finished = true
	RenderingServer.call_on_render_thread(_render_release)
	for frame in 3:
		await process_frame
	quit(code)


func _render_release() -> void:
	if audit != null:
		audit.release()
	if coupler != null:
		coupler.release()
	if solver != null:
		solver.release()

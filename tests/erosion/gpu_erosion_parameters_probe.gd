extends SceneTree

## T04 G01 parameter and unit checks for the erosion model.
##
## Three 64² cases, each varying one term of `sediment_step.glsl` while holding
## the rest fixed:
##   1. capacity  — erosion is driven by the capacity term, so zeroing the scale
##                  stops erosion entirely and doubling it erodes more
##   2. rates     — the erosion/deposition rates are per-second, so a shorter
##                  substep must not change the outcome of a fixed simulated span
##   3. dry bound — a bed with no standing water keeps its sand (all suspended
##                  load settles exponentially), so the pass cannot erode a dry cell
##
## Runs on the render thread so RenderingDevice readback is synchronous.

const Domain = preload("res://scripts/simulation/sand_water_domain.gd")
const Solver = preload("res://scripts/simulation/gpu_shallow_solver.gd")
const SedimentCoupler = preload("res://scripts/simulation/erosion/gpu_sediment_coupler.gd")

const GRID := 64
const CELL_M := 0.125
const SOLVER_SHADERS := [
	"res://shaders/simulation/shallow_edge_flux.glsl",
	"res://shaders/simulation/shallow_drain_scale.glsl",
	"res://shaders/simulation/shallow_update_state.glsl",
	"res://shaders/simulation/shallow_tide_boundary.glsl",
	"res://shaders/simulation/shallow_cfl_tiles.glsl",
	"res://shaders/simulation/shallow_gauge_depth.glsl",
	"res://shaders/simulation/shallow_audit_tiles.glsl",
	"res://shaders/simulation/shallow_tool_patch.glsl",
	"res://shaders/simulation/erosion/sediment_step.glsl",
	"res://shaders/simulation/erosion/copy_after_boundary.glsl"]

var finished := false
var started_ms := 0
var failures: Array[String] = []
var lines: Array[String] = []


func _init() -> void:
	call_deferred("_begin")


func _begin() -> void:
	started_ms = Time.get_ticks_msec()
	RenderingServer.call_on_render_thread(_render_run)
	call_deferred("_watchdog")


func _render_run() -> void:
	var spirvs: Array[RDShaderSPIRV] = []
	for path in SOLVER_SHADERS:
		var file: RDShaderFile = load(path)
		if file == null or file.get_spirv() == null:
			failures.append("shader import missing: " + path)
			break
		spirvs.append(file.get_spirv())
	if failures.is_empty():
		_run_capacity_case(spirvs)
	if failures.is_empty():
		_run_timestep_case(spirvs)
	if failures.is_empty():
		_run_dry_case(spirvs)
	call_deferred("_report")


## A flume: deep fast water over a sand bed, then a shallow still reach that can
## only deposit.
func _make_domain() -> SandWaterDomain:
	var domain := Domain.new(GRID, CELL_M)
	for z in GRID:
		for x in GRID:
			var i: int = domain.index(x, z)
			domain.rock[i] = 0.0
			domain.sand[i] = 0.30 if x < 4 * GRID / 5 else 0.05
			domain.water[i] = 0.40 if x < GRID / 2 else 0.02
			domain.wetness[i] = 0.0
			domain.compaction[i] = 0.0
			domain.sediment[i] = 0.0
	return domain


func _make(spirvs: Array[RDShaderSPIRV], domain: SandWaterDomain) -> Dictionary:
	var solver := Solver.new()
	if not solver.initialize(RenderingServer.get_rendering_device(), domain,
			spirvs[0], spirvs[1], spirvs[2], spirvs[3], spirvs[4], spirvs[5],
			spirvs[6], spirvs[7]):
		failures.append("solver initialize failed")
		return {}
	var sediment := SedimentCoupler.new()
	if not sediment.initialize(solver, spirvs[8], spirvs[9]):
		solver.release()
		failures.append("sediment coupler initialize failed")
		return {}
	return {"solver": solver, "sediment": sediment}


func _read(rig: Dictionary, field: String) -> PackedFloat32Array:
	var rid: RID = rig.solver.current_texture(field)
	if not rid.is_valid():
		failures.append("no texture for field " + field)
		return PackedFloat32Array()
	var data: PackedByteArray = RenderingServer.get_rendering_device().texture_get_data(rid, 0)
	if data.size() != GRID * GRID * 4:
		failures.append("unexpected readback size for %s: %d" % [field, data.size()])
		return PackedFloat32Array()
	return data.to_float32_array()


## Simulates `span_s` of physical time in `steps` coupled substeps and returns the
## total sand removed from the bed, plus the largest drop on any single cell.
func _simulate(domain: SandWaterDomain, spirvs: Array[RDShaderSPIRV], steps: int,
		span_s: float, capacity_scale: float, erosion_rate: float,
		deposition_rate: float) -> Dictionary:
	var rig := _make(spirvs, domain)
	if rig.is_empty():
		return {}
	rig.sediment.capacity_per_speed_s = capacity_scale
	rig.sediment.erosion_rate_per_s = erosion_rate
	rig.sediment.deposition_rate_per_s = deposition_rate
	var initial_water := 0.0
	for i in GRID * GRID:
		initial_water += domain.water[i] * CELL_M * CELL_M
	var delta_s := span_s / float(steps)
	for step in steps:
		if not rig.solver.dispatch_substep(delta_s) or \
				not rig.sediment.dispatch_after_water_substep(delta_s):
			failures.append("substep failed at %d" % step)
			break
	var result := {}
	if failures.is_empty():
		var sand := _read(rig, "sand")
		var sediment := _read(rig, "sediment")
		var water := _read(rig, "water")
		if sand.is_empty() or sediment.is_empty() or water.is_empty():
			_release(rig)
			return {}
		var eroded := 0.0
		var deposited := 0.0
		var final_water := 0.0
		for i in GRID * GRID:
			var change: float = sand[i] - domain.sand[i]
			if change < 0.0:
				eroded -= change * CELL_M * CELL_M
			else:
				deposited += change * CELL_M * CELL_M
			final_water += water[i] * CELL_M * CELL_M
		result = {"eroded": eroded, "deposited": deposited,
			"suspended": _total(sediment), "water": final_water,
			"initial_water": initial_water}
	_release(rig)
	return result


func _total(values: PackedFloat32Array) -> float:
	var sum := 0.0
	for value in values:
		sum += value * CELL_M * CELL_M
	return sum


func _release(rig: Dictionary) -> void:
	if rig.has("sediment"):
		rig.sediment.release()
	if rig.has("solver"):
		rig.solver.release()


## Case 1: the capacity term is what drives erosion. Zeroing its scale must stop
## erosion outright; doubling it must erode more than the baseline.
func _run_capacity_case(spirvs: Array[RDShaderSPIRV]) -> void:
	var rate := SedimentCoupler.EROSION_RATE_PER_S
	var deposit_rate := SedimentCoupler.DEPOSITION_RATE_PER_S
	var base := _simulate(_make_domain(), spirvs, 600, 5.0,
		SedimentCoupler.CAPACITY_PER_SPEED_S, rate, deposit_rate)
	if not failures.is_empty():
		return
	var doubled := _simulate(_make_domain(), spirvs, 600, 5.0,
		2.0 * SedimentCoupler.CAPACITY_PER_SPEED_S, rate, deposit_rate)
	if not failures.is_empty():
		return
	var zeroed := _simulate(_make_domain(), spirvs, 600, 5.0, 0.0, rate, deposit_rate)
	if not failures.is_empty():
		return
	if base.eroded <= 0.0:
		failures.append("baseline capacity scale eroded nothing: %.9f" % base.eroded)
	elif zeroed.eroded > 0.0000001:
		failures.append("zero capacity scale still eroded %.9f m3" % zeroed.eroded)
	elif doubled.eroded <= base.eroded:
		failures.append("doubling capacity did not erode more: %.9f vs %.9f" % [
			doubled.eroded, base.eroded])
	else:
		lines.append("CAPACITY_OK base_m3=%.9f doubled_m3=%.9f zeroed_m3=%.9f ratio=%.4f deposited_m3=%.9f" % [
			base.eroded, doubled.eroded, zeroed.eroded, doubled.eroded / base.eroded,
			base.deposited])


## Case 2: the rates are per second, so the same simulated span must give nearly
## the same result whether it is taken in 600 or 1200 substeps.
func _run_timestep_case(spirvs: Array[RDShaderSPIRV]) -> void:
	var scale := SedimentCoupler.CAPACITY_PER_SPEED_S
	var rate := SedimentCoupler.EROSION_RATE_PER_S
	var deposit_rate := SedimentCoupler.DEPOSITION_RATE_PER_S
	var coarse := _simulate(_make_domain(), spirvs, 600, 5.0, scale, rate, deposit_rate)
	if not failures.is_empty():
		return
	var fine := _simulate(_make_domain(), spirvs, 1200, 5.0, scale, rate, deposit_rate)
	if not failures.is_empty():
		return
	if coarse.eroded <= 0.0:
		failures.append("coarse span eroded nothing: %.9f" % coarse.eroded)
		return
	var coarse_eroded := float(coarse.eroded)
	var fine_eroded := float(fine.eroded)
	var relative: float = absf(fine_eroded - coarse_eroded) / coarse_eroded
	var water_relative: float = absf(float(fine.water) - float(coarse.water)) / \
		maxf(float(coarse.initial_water), 0.000001)
	## The water solver is explicit and first order, so halving the substep only
	## has to move the answer a few percent, not reproduce it exactly.
	if relative > 0.05:
		failures.append("erosion is not time-step consistent: %.9f vs %.9f (%.2f%%)" % [
			coarse.eroded, fine.eroded, 100.0 * relative])
	elif water_relative > 0.01:
		failures.append("water diverged between substep sizes: %.3f%%" % [
			100.0 * water_relative])
	else:
		lines.append("TIMESTEP_OK coarse_600_m3=%.9f fine_1200_m3=%.9f relative=%.5f water_relative=%.6f" % [
			coarse_eroded, fine_eroded, relative, water_relative])


## Case 3: with no standing water the pass must settle the suspended load instead
## of eroding, so a dry bed keeps its sand.
func _run_dry_case(spirvs: Array[RDShaderSPIRV]) -> void:
	var domain := _make_domain()
	for z in GRID:
		for x in GRID:
			var i: int = domain.index(x, z)
			domain.water[i] = 0.0
			domain.sediment[i] = 0.01
	var rig := _make(spirvs, domain)
	if rig.is_empty():
		return
	var before := _total(domain.sediment)
	for step in 300:
		if not rig.solver.dispatch_substep(1.0 / 120.0) or \
				not rig.sediment.dispatch_after_water_substep(1.0 / 120.0):
			failures.append("dry case substep failed at %d" % step)
			break
	if failures.is_empty():
		var sand := _read(rig, "sand")
		var sediment := _read(rig, "sediment")
		if sand.is_empty() or sediment.is_empty():
			_release(rig)
			return
		var eroded := 0.0
		for i in GRID * GRID:
			if sand[i] < domain.sand[i] - 0.0000001:
				eroded += (domain.sand[i] - sand[i]) * CELL_M * CELL_M
		var remaining := _total(sediment)
		if eroded > 0.0000001:
			failures.append("dry bed eroded %.9f m3" % eroded)
		elif absf(remaining - before * exp(-SedimentCoupler.DEPOSITION_RATE_PER_S * 2.5)) > 0.00001:
			failures.append("dry settling disagrees with exponential rate: %.9f of %.9f left" % [remaining, before])
		else:
			lines.append("DRY_OK eroded_m3=%.9f suspended_before_m3=%.9f suspended_after_m3=%.9f" % [
				eroded, before, remaining])
	_release(rig)


func _watchdog() -> void:
	if finished:
		return
	if Time.get_ticks_msec() - started_ms > 600000:
		printerr("FAIL: erosion parameter probe timed out")
		_finish(1)
		return
	await process_frame
	call_deferred("_watchdog")


func _report() -> void:
	if finished:
		return
	if not failures.is_empty():
		for failure in failures:
			printerr("FAIL: " + failure)
		_finish(1)
		return
	if lines.size() != 3:
		printerr("FAIL: expected 3 passing cases, got %d" % lines.size())
		_finish(1)
		return
	for line in lines:
		print(line)
	print("PASS: GPU erosion parameters grid=%d cases=%d" % [GRID, lines.size()])
	_finish(0)


func _finish(code: int) -> void:
	finished = true
	for frame in 3:
		await process_frame
	quit(code)

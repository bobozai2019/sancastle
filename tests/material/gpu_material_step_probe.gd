extends SceneTree

## T05 64² GPU probe for the material passes.
##
## Builds independent 64² domains on the main RenderingDevice and checks:
##   1. wetness   — soaks under standing water, drains continuously to the
##                  residual once the water is gone, stays inside [0, 1]
##   2. slope     — a steep dry pile slumps, settles onto the repose slope and
##                  stops, with the sand total unchanged to float precision
##   3. strength  — the erosion strength curve responds to compaction and wetness
##                  in the direction sediment_step.glsl assumes
##
## The mesh is 64² because ADR-010 allows the cheaper development size; the
## passes are grid-size agnostic and run at 256² in the preview.
##
## Everything runs on the render thread: RenderingDevice readback is synchronous
## there, so the probe does not need the async callback choreography the
## production preview uses.

const Domain = preload("res://scripts/simulation/sand_water_domain.gd")
const Solver = preload("res://scripts/simulation/gpu_shallow_solver.gd")
const SedimentCoupler = preload("res://scripts/simulation/erosion/gpu_sediment_coupler.gd")
const MaterialCoupler = preload("res://scripts/simulation/material/gpu_material_coupler.gd")

const GRID := 64
const CELL_M := 0.125
const DELTA_S := 1.0 / 120.0
const SOLVER_SHADERS := [
	"res://shaders/simulation/shallow_edge_flux.glsl",
	"res://shaders/simulation/shallow_drain_scale.glsl",
	"res://shaders/simulation/shallow_update_state.glsl",
	"res://shaders/simulation/shallow_tide_boundary.glsl",
	"res://shaders/simulation/shallow_cfl_tiles.glsl",
	"res://shaders/simulation/shallow_gauge_depth.glsl",
	"res://shaders/simulation/shallow_audit_tiles.glsl",
	"res://shaders/simulation/shallow_tool_patch.glsl"]
const EROSION_SHADERS := [
	"res://shaders/simulation/erosion/sediment_step.glsl",
	"res://shaders/simulation/erosion/copy_after_boundary.glsl"]
const MATERIAL_SHADERS := [
	"res://shaders/simulation/material/material_step.glsl",
	"res://shaders/simulation/material/slope_relax.glsl",
	"res://shaders/simulation/material/material_commit.glsl"]

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
	var material_spirvs: Array[RDShaderSPIRV] = []
	for path in SOLVER_SHADERS + EROSION_SHADERS:
		var file: RDShaderFile = load(path)
		if file == null or file.get_spirv() == null:
			failures.append("shader import missing: " + path)
			break
		spirvs.append(file.get_spirv())
	for path in MATERIAL_SHADERS:
		var file: RDShaderFile = load(path)
		if file == null or file.get_spirv() == null:
			failures.append("shader import missing: " + path)
			break
		material_spirvs.append(file.get_spirv())
	if failures.is_empty():
		_run_wetness_case(spirvs, material_spirvs)
	if failures.is_empty():
		_run_slope_case(spirvs, material_spirvs)
	if failures.is_empty():
		_run_strength_case(spirvs, material_spirvs)
	call_deferred("_report")


func _make(spirvs: Array[RDShaderSPIRV], material_spirvs: Array[RDShaderSPIRV],
		domain: SandWaterDomain) -> Dictionary:
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
	var material := MaterialCoupler.new()
	if not material.initialize(solver, sediment.dirty_max_texture, material_spirvs[0],
			material_spirvs[1], material_spirvs[2]):
		sediment.release()
		solver.release()
		failures.append("material coupler initialize failed")
		return {}
	return {"solver": solver, "sediment": sediment, "material": material}


func _release(rig: Dictionary) -> void:
	if rig.has("material"):
		rig.material.release()
	if rig.has("sediment"):
		rig.sediment.release()
	if rig.has("solver"):
		rig.solver.release()


## wetness/compaction are R16F and sand is R32F, so decode by byte width.
func _read(rig: Dictionary, field: String) -> PackedFloat32Array:
	var rid: RID = rig.solver.current_texture(field)
	if not rid.is_valid():
		failures.append("no texture for field " + field)
		return PackedFloat32Array()
	var data: PackedByteArray = RenderingServer.get_rendering_device().texture_get_data(rid, 0)
	if data.size() == GRID * GRID * 4:
		return data.to_float32_array()
	if data.size() == GRID * GRID * 2:
		var values := PackedFloat32Array()
		values.resize(GRID * GRID)
		for i in GRID * GRID:
			values[i] = data.decode_half(i * 2)
		return values
	failures.append("unexpected readback size for %s: %d" % [field, data.size()])
	return PackedFloat32Array()


## Case 1: wet west half, dry east half. The wet half must soak to saturation,
## the dry half must drain continuously towards the residual, and both fields
## must stay bounded and finite for 15 simulated seconds.
func _run_wetness_case(spirvs: Array[RDShaderSPIRV],
		material_spirvs: Array[RDShaderSPIRV]) -> void:
	var domain := Domain.new(GRID, CELL_M)
	for z in GRID:
		for x in GRID:
			var i: int = domain.index(x, z)
			domain.rock[i] = 0.0
			domain.sand[i] = 0.4
			domain.water[i] = 0.30 if x < GRID / 2 else 0.0
			domain.wetness[i] = 0.5 if x < GRID / 2 else 0.9
			domain.compaction[i] = 0.0
	var rig := _make(spirvs, material_spirvs, domain)
	if rig.is_empty():
		return
	var wet_cell: int = domain.index(GRID / 4, GRID / 2)
	var dry_cell: int = domain.index(GRID * 3 / 4, GRID / 2)
	var trail: Array[String] = []
	for step in 1800:
		if not rig.material.dispatch_after_erosion(DELTA_S):
			failures.append("wetness case dispatch failed at step %d" % step)
			break
		if step % 300 != 0:
			continue
		var wetness := _read(rig, "wetness")
		var compaction := _read(rig, "compaction")
		if wetness.is_empty() or compaction.is_empty():
			break
		trail.append("%.4f" % wetness[dry_cell])
		var bounded := true
		for i in GRID * GRID:
			if not is_finite(wetness[i]) or wetness[i] < 0.0 or wetness[i] > 1.0 or \
					not is_finite(compaction[i]) or compaction[i] < 0.0 or compaction[i] > 1.0:
				failures.append("wetness/compaction out of range at cell %d: %.6f/%.6f" % [
					i, wetness[i], compaction[i]])
				bounded = false
				break
		if not bounded:
			break
	if failures.is_empty():
		var wetness := _read(rig, "wetness")
		var compaction := _read(rig, "compaction")
		var soaked: float = wetness[wet_cell]
		var drained: float = wetness[dry_cell]
		var monotone := true
		for index in range(1, trail.size()):
			if float(trail[index]) > float(trail[index - 1]) + 0.0001:
				monotone = false
		if soaked < 0.99:
			failures.append("standing water did not soak the bed: wetness=%.6f" % soaked)
		elif drained > 0.5 or not monotone:
			failures.append("dry reach did not drain continuously: final=%.6f" % drained)
		elif drained < MaterialCoupler.RESIDUAL_WETNESS - 0.0001:
			failures.append("dry reach drained below the residual: %.6f" % drained)
		elif compaction[wet_cell] < 0.05 or compaction[dry_cell] >= compaction[wet_cell]:
			failures.append("compaction did not follow water exposure: wet=%.6f dry=%.6f" % [
				compaction[wet_cell], compaction[dry_cell]])
		else:
			lines.append("WETNESS_OK soaked=%.6f drained=%.6f residual=%.4f trail=%s compaction_wet=%.6f compaction_after_drain=%.6f" % [
				soaked, drained, MaterialCoupler.RESIDUAL_WETNESS, ",".join(trail),
				compaction[wet_cell], compaction[dry_cell]])
	_release(rig)


## Case 2: a dry sand pyramid on flat rock. It must slump, converge onto the
## repose slope, stop moving, and never change the sand total or go negative.
func _run_slope_case(spirvs: Array[RDShaderSPIRV],
		material_spirvs: Array[RDShaderSPIRV]) -> void:
	var domain := Domain.new(GRID, CELL_M)
	var centre := GRID / 2
	for z in GRID:
		for x in GRID:
			var i: int = domain.index(x, z)
			domain.rock[i] = 0.0
			domain.sand[i] = maxf(0.0, 1.6 - 0.2 * float(maxi(absi(x - centre), absi(z - centre))))
			domain.water[i] = 0.0
			domain.wetness[i] = 0.0
			domain.compaction[i] = 0.0
	var rig := _make(spirvs, material_spirvs, domain)
	if rig.is_empty():
		return
	var initial_total := 0.0
	for i in GRID * GRID:
		initial_total += domain.sand[i] * CELL_M * CELL_M
	var samples: Array[float] = []
	var max_drop_m := INF
	var closure := INF
	## The scheme relaxes slope by diffusing curvature, so a 23-cell pile needs
	## on the order of L^2/(2D) = 4000 substeps before the last millimetre goes.
	## Readback is synchronous, so only check every fourth substep.
	for step in 6000:
		if not rig.material.dispatch_after_erosion(DELTA_S):
			failures.append("slope case dispatch failed at step %d" % step)
			break
		if step % 4 != 0:
			continue
		var sand := _read(rig, "sand")
		if sand.is_empty():
			break
		var total := 0.0
		max_drop_m = 0.0
		var valid := true
		for z in GRID:
			for x in GRID:
				var i: int = domain.index(x, z)
				if not is_finite(sand[i]) or sand[i] < -0.000001:
					failures.append("slope case sand invalid at cell %d: %.9f" % [i, sand[i]])
					valid = false
					break
				total += sand[i] * CELL_M * CELL_M
				var here: float = domain.rock[i] + sand[i]
				if x + 1 < GRID:
					max_drop_m = maxf(max_drop_m, here - (domain.rock[domain.index(x + 1, z)]
						+ sand[domain.index(x + 1, z)]))
				if z + 1 < GRID:
					max_drop_m = maxf(max_drop_m, here - (domain.rock[domain.index(x, z + 1)]
						+ sand[domain.index(x, z + 1)]))
		if not valid:
			break
		closure = absf(total - initial_total)
		## Each edge moves the same depth on both sides, so the only drift is the
		## float32 rounding of the stored cells over 2400 substeps. Hold it to
		## 0.001% so a real leak cannot hide under the tolerance.
		if closure > maxf(0.00001, initial_total * 0.00001):
			failures.append("slope case lost sand: closure=%.12f m3 (%.4f ppm)" % [
				closure, 1000000.0 * closure / initial_total])
			break
		if step % 1500 == 0:
			samples.append(max_drop_m)
	## The pile is bone dry and no water is present, so compaction must not move:
	## compaction is driven by water only, never by slumping.
	var compaction := _read(rig, "compaction")
	_release(rig)
	if not failures.is_empty():
		return
	var max_compaction := 0.0
	for i in GRID * GRID:
		max_compaction = maxf(max_compaction, compaction[i])
	if max_compaction > 0.000001:
		failures.append("dry slumping compacted the sand: max=%.9f" % max_compaction)
		return
	var repose := MaterialCoupler.DRY_REPOSE_TAN * CELL_M
	var creep: float = samples[-2] - samples[-1] if samples.size() >= 2 else INF
	## A shared-edge exchange redistributes sand but cannot change a uniform
	## slope, so the settled surface lands a few percent above the nominal
	## repose tangent instead of exactly on it. Assert the band, and report the
	## exact offset so a regression that widens it is visible.
	if max_drop_m - repose > 0.1 * repose:
		failures.append("steep pile did not settle near the repose slope: max drop %.6f repose %.6f" % [
			max_drop_m, repose])
	elif creep > 0.0002:
		failures.append("slope kept creeping: %.6f m over the last 1500 substeps" % creep)
	else:
		lines.append("SLOPE_OK max_drop_m=%.6f repose_m=%.6f overshoot_permille=%.4f creep_last_1500_m=%.6f trail_m=%s sand_closure_m3=%.12f closure_ppm=%.4f" % [
			max_drop_m, repose, 1000.0 * (max_drop_m - repose) / repose, creep,
			",".join(PackedStringArray(samples.map(
				func(value: float) -> String: return "%.5f" % value))),
			closure, 1000000.0 * closure / initial_total])


## Case 3: erosion strength curve. sediment_step.glsl scales capacity by
## 1/strength with strength = mix(0.7, 1.8, compaction) * mix(1.0, 1.25, wetness),
## so a compacted or wet bed must erode less than a loose dry one under the same
## forcing.
func _run_strength_case(spirvs: Array[RDShaderSPIRV],
		material_spirvs: Array[RDShaderSPIRV]) -> void:
	var loose := _strength_erosion(spirvs, material_spirvs, 0.0, 0.0)
	if not failures.is_empty():
		return
	var compacted := _strength_erosion(spirvs, material_spirvs, 1.0, 0.0)
	if not failures.is_empty():
		return
	var wet := _strength_erosion(spirvs, material_spirvs, 0.0, 1.0)
	if not failures.is_empty():
		return
	if loose <= 0.0:
		failures.append("strength case produced no erosion at all: %.9f" % loose)
	elif compacted >= loose:
		failures.append("compaction did not reduce erosion: loose=%.9f compacted=%.9f" % [
			loose, compacted])
	elif wet >= loose:
		failures.append("wetness did not reduce erosion: loose=%.9f wet=%.9f" % [loose, wet])
	else:
		lines.append("STRENGTH_OK loose_m=%.9f compacted_m=%.9f wet_m=%.9f" % [
			loose, compacted, wet])


func _strength_erosion(spirvs: Array[RDShaderSPIRV],
		material_spirvs: Array[RDShaderSPIRV], compaction: float, wetness: float) -> float:
	var domain := Domain.new(GRID, CELL_M)
	for z in GRID:
		for x in GRID:
			var i: int = domain.index(x, z)
			domain.rock[i] = 0.0
			domain.sand[i] = 0.5
			domain.water[i] = 0.40 if x < GRID / 2 else 0.02
			domain.wetness[i] = wetness
			domain.compaction[i] = compaction
	var rig := _make(spirvs, material_spirvs, domain)
	if rig.is_empty():
		return -1.0
	for step in 400:
		if not rig.solver.dispatch_substep(DELTA_S) or \
				not rig.sediment.dispatch_after_water_substep(DELTA_S):
			failures.append("strength case substep failed at step %d" % step)
			break
	var eroded := -1.0
	if failures.is_empty():
		var sand := _read(rig, "sand")
		if not sand.is_empty():
			eroded = 0.0
			for i in GRID * GRID:
				if sand[i] < domain.sand[i]:
					eroded += (domain.sand[i] - sand[i]) * CELL_M * CELL_M
	_release(rig)
	return eroded


func _watchdog() -> void:
	if finished:
		return
	if Time.get_ticks_msec() - started_ms > 600000:
		printerr("FAIL: material probe timed out")
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
	print("PASS: GPU material passes grid=%d substep_s=%.6f cases=%d" % [
		GRID, DELTA_S, lines.size()])
	_finish(0)


func _finish(code: int) -> void:
	finished = true
	for frame in 3:
		await process_frame
	quit(code)

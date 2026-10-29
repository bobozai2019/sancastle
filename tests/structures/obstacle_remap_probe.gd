extends SceneTree

## T06 G04 obstacle/water remap probe, 64² on the main RenderingDevice.
##
##   1. block a band of a full-of-water domain: the remap must move the band's
##      water onto its open neighbours, changing neither the water nor the
##      suspended-sand total, and leaving no blocked cell holding water
##   2. a blocked pocket with no open neighbour cannot drain: the remap must keep
##      its load and report the tile instead of silently dropping it
##   3. re-running the remap on an already-remapped state must change nothing,
##      so structural events can dispatch it unconditionally
##
## Everything runs on the render thread, where RenderingDevice readback is
## synchronous.

const Domain = preload("res://scripts/simulation/sand_water_domain.gd")
const Solver = preload("res://scripts/simulation/gpu_shallow_solver.gd")
const Remap = preload("res://scripts/structures/gpu_obstacle_remap.gd")

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
	"res://shaders/simulation/shallow_tool_patch.glsl"]
const REMAP_SHADERS := [
	"res://shaders/simulation/structures/obstacle_remap.glsl",
	"res://shaders/simulation/structures/obstacle_commit.glsl"]

var failures: Array[String] = []
var lines: Array[String] = []
var finished := false
var started_ms := 0


func _init() -> void:
	call_deferred("_begin")


func _begin() -> void:
	started_ms = Time.get_ticks_msec()
	RenderingServer.call_on_render_thread(_render_run)
	call_deferred("_watchdog")


func _render_run() -> void:
	var spirvs: Array[RDShaderSPIRV] = []
	var remap_spirvs: Array[RDShaderSPIRV] = []
	for path in SOLVER_SHADERS:
		if not _load(path, spirvs):
			break
	for path in REMAP_SHADERS:
		if not _load(path, remap_spirvs):
			break
	if failures.is_empty():
		_run_band_case(spirvs, remap_spirvs)
	if failures.is_empty():
		_run_pocket_case(spirvs, remap_spirvs)
	if failures.is_empty():
		_run_idempotence_case(spirvs, remap_spirvs)
	call_deferred("_report")


func _load(path: String, target: Array[RDShaderSPIRV]) -> bool:
	var file: RDShaderFile = load(path)
	if file == null or file.get_spirv() == null:
		failures.append("shader import missing: " + path)
		return false
	target.append(file.get_spirv())
	return true


func _make(spirvs: Array[RDShaderSPIRV], remap_spirvs: Array[RDShaderSPIRV],
		domain: SandWaterDomain) -> Dictionary:
	var solver := Solver.new()
	if not solver.initialize(RenderingServer.get_rendering_device(), domain,
			spirvs[0], spirvs[1], spirvs[2], spirvs[3], spirvs[4], spirvs[5],
			spirvs[6], spirvs[7]):
		failures.append("solver initialize failed")
		return {}
	if not solver.update_obstacles(domain.obstacle):
		solver.release()
		failures.append("obstacle upload failed")
		return {}
	var remap := Remap.new()
	if not remap.initialize(solver, remap_spirvs[0], remap_spirvs[1]):
		solver.release()
		failures.append("obstacle remap initialize failed")
		return {}
	return {"solver": solver, "remap": remap}


func _release(rig: Dictionary) -> void:
	if rig.has("remap"):
		rig.remap.release()
	if rig.has("solver"):
		rig.solver.release()


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


func _total(values: PackedFloat32Array) -> float:
	var area := CELL_M * CELL_M
	var total := 0.0
	for value in values:
		total += value * area
	return total


func _flooded_domain() -> SandWaterDomain:
	var domain := Domain.new(GRID, CELL_M)
	for z in GRID:
		for x in GRID:
			var i: int = domain.index(x, z)
			domain.rock[i] = 0.0
			domain.sand[i] = 0.20
			domain.water[i] = 0.30
			domain.sediment[i] = 0.01
			domain.wetness[i] = 0.5
			domain.compaction[i] = 0.2
	return domain


## Case 1: a single-cell-thick band across the domain. Every blocked cell has open
## neighbours, so all of its water must be redistributed.
func _run_band_case(spirvs: Array[RDShaderSPIRV],
		remap_spirvs: Array[RDShaderSPIRV]) -> void:
	var domain := _flooded_domain()
	for z in GRID:
		domain.obstacle[domain.index(GRID / 2, z)] = 1.0
	var rig := _make(spirvs, remap_spirvs, domain)
	if rig.is_empty():
		return
	var water_before := _total(_read(rig, "water"))
	var sediment_before := _total(_read(rig, "sediment"))
	if not rig.remap.clear_tiles() or not rig.remap.dispatch():
		failures.append("band remap dispatch failed")
		_release(rig)
		return
	var water := _read(rig, "water")
	var sediment := _read(rig, "sediment")
	var water_after := _total(water)
	var sediment_after := _total(sediment)
	var blocked_water := 0.0
	var neighbours_raised := 0
	for i in GRID * GRID:
		if domain.obstacle[i] >= 0.5:
			blocked_water += water[i]
		elif water[i] > 0.3001:
			neighbours_raised += 1
	_release(rig)
	if absf(water_after - water_before) > 0.0000001:
		failures.append("band remap changed the water total by %.9f m3" % [
			water_after - water_before])
	elif absf(sediment_after - sediment_before) > 0.0000001:
		failures.append("band remap changed the suspended total by %.9f m3" % [
			sediment_after - sediment_before])
	elif blocked_water > 0.0000001:
		failures.append("blocked cells still hold %.9f m3 of water" % blocked_water)
	elif neighbours_raised < 2 * GRID:
		failures.append("only %d neighbours received water" % neighbours_raised)
	else:
		lines.append("BAND_OK water_before_m3=%.9f water_after_m3=%.9f blocked_water_m3=%.9f " % [
			water_before, water_after, blocked_water] +
			"suspended_before_m3=%.9f suspended_after_m3=%.9f neighbours_raised=%d" % [
				sediment_before, sediment_after, neighbours_raised])


## Case 2: a solid 3x3 block. Its centre has no open neighbour, so its water
## cannot drain and must be retained and reported rather than deleted.
func _run_pocket_case(spirvs: Array[RDShaderSPIRV],
		remap_spirvs: Array[RDShaderSPIRV]) -> void:
	var domain := _flooded_domain()
	var centre := GRID / 2
	for z in range(centre - 1, centre + 2):
		for x in range(centre - 1, centre + 2):
			domain.obstacle[domain.index(x, z)] = 1.0
	var rig := _make(spirvs, remap_spirvs, domain)
	if not rig.remap.clear_tiles() or not rig.remap.dispatch():
		failures.append("pocket remap dispatch failed")
		_release(rig)
		return
	var water := _read(rig, "water")
	var water_after := _total(water)
	var centre_water: float = water[domain.index(centre, centre)]
	var ring_water := 0.0
	for z in range(centre - 1, centre + 2):
		for x in range(centre - 1, centre + 2):
			if x == centre and z == centre:
				continue
			ring_water += water[domain.index(x, z)]
	var tiles_data: PackedByteArray = RenderingServer.get_rendering_device().texture_get_data(
		rig.remap.remap_tiles, 0)
	var reported_tiles: int = rig.remap.decode_tiles(tiles_data, 2)
	_release(rig)
	if absf(water_after - 0.30 * float(GRID * GRID) * CELL_M * CELL_M) > 0.0001:
		failures.append("pocket remap lost water: total %.9f" % water_after)
	elif ring_water > 0.0000001:
		failures.append("pocket ring still holds %.9f m3" % ring_water)
	elif absf(centre_water - 0.30) > 0.0001:
		failures.append("trapped centre water was dropped: %.9f" % centre_water)
	elif reported_tiles != 1:
		failures.append("trapped pocket not reported: %d tiles" % reported_tiles)
	else:
		lines.append("POCKET_OK total_m3=%.9f ring_water_m3=%.9f centre_water_m=%.6f reported_tiles=%d" % [
			water_after, ring_water, centre_water, reported_tiles])


## Case 3: the remap is idempotent, so an event can dispatch it unconditionally.
func _run_idempotence_case(spirvs: Array[RDShaderSPIRV],
		remap_spirvs: Array[RDShaderSPIRV]) -> void:
	var domain := _flooded_domain()
	for z in GRID:
		domain.obstacle[domain.index(GRID / 3, z)] = 1.0
		domain.obstacle[domain.index(2 * GRID / 3, z)] = 1.0
	var rig := _make(spirvs, remap_spirvs, domain)
	if not rig.remap.clear_tiles() or not rig.remap.dispatch():
		failures.append("idempotence first dispatch failed")
		_release(rig)
		return
	var first := _read(rig, "water")
	if not rig.remap.clear_tiles() or not rig.remap.dispatch():
		failures.append("idempotence second dispatch failed")
		_release(rig)
		return
	var second := _read(rig, "water")
	var tiles_data: PackedByteArray = RenderingServer.get_rendering_device().texture_get_data(
		rig.remap.remap_tiles, 0)
	var reported_tiles: int = rig.remap.decode_tiles(tiles_data)
	_release(rig)
	var worst := 0.0
	for i in GRID * GRID:
		worst = maxf(worst, absf(second[i] - first[i]))
	if worst > 0.0000001:
		failures.append("remap is not idempotent: max delta %.9f m" % worst)
	elif reported_tiles != 0:
		failures.append("a no-op remap reported %d changed tiles" % reported_tiles)
	else:
		lines.append("IDEMPOTENT_OK max_delta_m=%.9f reported_tiles=%d water_m3=%.9f" % [
			worst, reported_tiles, _total(second)])


func _watchdog() -> void:
	if finished:
		return
	if Time.get_ticks_msec() - started_ms > 600000:
		printerr("FAIL: obstacle remap probe timed out")
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
	print("PASS: GPU obstacle remap grid=%d cases=%d" % [GRID, lines.size()])
	_finish(0)


func _finish(code: int) -> void:
	finished = true
	for _frame in 3:
		await process_frame
	quit(code)

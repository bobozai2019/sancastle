extends SceneTree

## NUM-11: 100 structure destruction cycles.
##
## Each cycle builds a wall, undermines it, collapses it, relaxes the slope and
## rebuilds. Per `契约/场景与自动验收契约.md` NUM-11 the run checks that every
## event leaves the water and sand accounts closed, that no obstacle residue or
## stale generation event survives a rebuild, and it archives a per-cycle trend
## CSV.
##
## Structures here are packed sand and write no obstacle bit, so the obstacle
## check is an explicit "the mask is bit-identical to the starting mask" rather
## than a remap test. See the T06 report for what is still outstanding.

const Domain = preload("res://scripts/simulation/sand_water_domain.gd")
const Structure = preload("res://scripts/structures/structure_state.gd")
const Field = preload("res://scripts/structures/structure_field.gd")

const GRID := 64
const CELL_M := 0.125
const SUBSTEP_S := 1.0 / 120.0
const DAMAGE_RATE_PER_S := 4.0
const RELAX_RATE_PER_S := 15.0
const DRY_REPOSE_TAN := 0.674
## Just enough relaxation to exercise the post-collapse path each cycle. The
## full settle-to-repose behaviour is covered by `run_structure_tests.gd`; here
## it would dominate the runtime of a 100-cycle sweep.
const RELAX_SUBSTEPS := 100
const MAX_DAMAGE_SUBSTEPS := 6000
const CYCLES := 100

const OUTPUT_PATH := "res://test_output/sandcastle_water_sand_coupling/验收/T06_num11_structures_100_cycles.csv"

var failures: Array[String] = []
var rows: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var domain := Domain.new(GRID, CELL_M)
	for z in GRID:
		for x in GRID:
			var i: int = domain.index(x, z)
			domain.rock[i] = 0.0
			domain.sand[i] = 0.30
			domain.water[i] = 0.05 if x < GRID / 4 else 0.0
			domain.wetness[i] = 0.0
			domain.compaction[i] = 0.0
	var field := Field.new()

	## Baselines that no structure event may disturb.
	var water_before := _total(domain.water, domain)
	var obstacle_before := _obstacle_digest(domain)
	var area := domain.cell_size_m * domain.cell_size_m
	var restore_bed := 0.30 * float(GRID * GRID) * area
	var initial_sand_total := _total(domain.sand, domain)

	## A stale event from a generation that no longer exists must be ignored.
	var rebuilt := false
	var max_collapse_substeps := 0
	for cycle in CYCLES:
		if cycle == 50:
			field.rebuild()
			rebuilt = true
		var wall := Structure.new()
		wall.kind = Structure.Kind.WALL
		wall.name = "cycle_wall"
		wall.origin = Vector2i(20, 30)
		wall.size = Vector2i(10, 1)
		wall.height_m = 0.20
		wall.compaction = 0.2 + 0.7 * float(cycle % 10) / 9.0
		var booked := field.add(wall, domain)

		## A delivery from the previous generation must be silently dropped.
		var stale_generation := field.generation - 1
		field.apply_collapse(wall.id, stale_generation, domain)
		if wall.collapsed:
			failures.append("a stale generation event collapsed the wall in cycle %d" % cycle)
			break

		_undermine(domain, wall)
		var damage_substeps := 0
		for step in MAX_DAMAGE_SUBSTEPS:
			if not field.step(domain, SUBSTEP_S, DAMAGE_RATE_PER_S).is_empty():
				damage_substeps = step + 1
				break
		if damage_substeps == 0:
			failures.append("wall never collapsed in cycle %d" % cycle)
			break
		max_collapse_substeps = maxi(max_collapse_substeps, damage_substeps)
		_relax(domain, RELAX_SUBSTEPS)

		var sand_total := _total(domain.sand, domain)
		var closure := sand_total - (initial_sand_total + domain.sand_source_m3 -
			domain.sand_sink_m3 + domain.tool_inventory_m3)
		var water_now := _total(domain.water, domain)
		var water_delta := water_now - water_before
		var obstacle_now := _obstacle_digest(domain)

		rows.append("%d,%.6f,%.9f,%.9f,%.9f,%.9f,%.9f,%d,%d" % [cycle,
			float(damage_substeps + RELAX_SUBSTEPS) * SUBSTEP_S,
			booked, sand_total, closure, water_now, water_delta,
			obstacle_now, field.generation])

		if absf(closure) > 0.001:
			failures.append("cycle %d sand account did not close: %.9f m3" % [cycle, closure])
			break
		if absf(water_delta) > 0.000000001:
			failures.append("cycle %d changed the water account by %.9f m3" % [
				cycle, water_delta])
			break
		if obstacle_now != obstacle_before:
			failures.append("cycle %d left obstacle residue" % cycle)
			break

		## Restore the bed exactly and book the difference, so every cycle starts
		## from the same surface and the ledger still closes.
		var adjustment := restore_bed - sand_total
		if adjustment > 0.0:
			domain.sand_source_m3 += adjustment
		elif adjustment < 0.0:
			domain.sand_sink_m3 -= adjustment
		for i in GRID * GRID:
			domain.sand[i] = 0.30
			domain.compaction[i] = 0.0
		field.clear()

	if not failures.is_empty():
		for failure in failures:
			printerr("FAIL: " + failure)
		quit(1)
		return
	if not rebuilt:
		printerr("FAIL: the rebuild branch never ran")
		quit(1)
		return
	var header := "cycle,sim_time_s,booked_m3,sand_total_m3,sand_closure_m3," + \
		"water_total_m3,water_delta_m3,obstacle_digest,generation"
	var file := FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
	if file == null:
		printerr("FAIL: cannot open %s" % OUTPUT_PATH)
		quit(1)
		return
	file.store_line(header)
	for row in rows:
		file.store_line(row)
	file.close()
	var final_closure := _total(domain.sand, domain) - (initial_sand_total +
		domain.sand_source_m3 - domain.sand_sink_m3 + domain.tool_inventory_m3)
	print("PASS: T06 NUM-11 structures cycles=%d rows=%d final_sand_closure_m3=%.9f max_collapse_substeps=%d " % [
		CYCLES, rows.size(), final_closure, max_collapse_substeps] +
		"water_delta_m3=%.9f obstacle_digest=%d generation=%d CSV=%s" % [
			_total(domain.water, domain) - water_before, _obstacle_digest(domain),
			field.generation, OUTPUT_PATH])
	quit(0)


## Excavates the bed beside the wall and books the removed volume as a sand sink,
## so the ledger stays closed across the edit.
func _undermine(domain: SandWaterDomain, wall: SandcastleStructure) -> float:
	var removed := 0.0
	var area := domain.cell_size_m * domain.cell_size_m
	for z in range(wall.origin.y, wall.origin.y + wall.size.y):
		for x in range(wall.origin.x - 1, wall.origin.x + wall.size.x + 1):
			if x < 0 or x >= GRID or wall.contains(x, z):
				continue
			var cell := z * GRID + x
			removed += domain.sand[cell] * area
			domain.sand[cell] = 0.0
	domain.sand_sink_m3 += removed
	return removed


func _relax(domain: SandWaterDomain, substeps: int) -> void:
	var blend := clampf(RELAX_RATE_PER_S * SUBSTEP_S, 0.0, 1.0)
	var offsets: Array[Vector2i] = [Vector2i(-1, 0), Vector2i(1, 0),
		Vector2i(0, -1), Vector2i(0, 1)]
	var delta := PackedFloat32Array()
	delta.resize(GRID * GRID)
	for _step in substeps:
		delta.fill(0.0)
		for z in GRID:
			for x in GRID:
				var p := z * GRID + x
				var surface: float = domain.rock[p] + domain.sand[p]
				for offset in offsets:
					var nx: int = x + offset.x
					var nz: int = z + offset.y
					if nx < 0 or nz < 0 or nx >= GRID or nz >= GRID:
						continue
					var q := nz * GRID + nx
					var neighbour: float = domain.rock[q] + domain.sand[q]
					var p_is_donor := surface >= neighbour
					var donor := p if p_is_donor else q
					var receiver := q if p_is_donor else p
					var compaction: float = 0.5 * (domain.compaction[donor] +
						domain.compaction[receiver])
					var repose: float = (DRY_REPOSE_TAN + 0.3 * compaction) * CELL_M
					var excess: float = absf(surface - neighbour) - repose
					if excess <= 0.0:
						continue
					var donor_sand: float = domain.sand[donor]
					var moved: float = minf(excess * 0.5 * blend, donor_sand * 0.25)
					if moved <= 0.0:
						continue
					delta[p] += -moved if p_is_donor else moved
		for i in GRID * GRID:
			domain.sand[i] = maxf(domain.sand[i] + delta[i], 0.0)


func _total(values: PackedFloat32Array, domain: SandWaterDomain) -> float:
	var area := domain.cell_size_m * domain.cell_size_m
	var total := 0.0
	for value in values:
		total += value * area
	return total


## Order-independent digest of the binary obstacle mask, so any residue shows up.
func _obstacle_digest(domain: SandWaterDomain) -> int:
	var digest := 0
	for i in domain.obstacle.size():
		if domain.obstacle[i] >= 0.5:
			digest = (digest * 31 + i + 1) & 0x7fffffff
	return digest

extends SceneTree

## T06 structure tests on the CPU reference domain.
##
##   1. build/volume   — building a wall books exactly its volume, and the drawn
##                       surface `rock + sand` rises by the wall height
##   2. support/damage — an undermined wall accumulates damage, a fully
##                       buttressed one never does, and a compacted wall survives
##                       longer than a loose one under identical undermining
##   3. three walls    — NUM-10-style comparison: the same undermining collapses
##                       three walls in strength order, and the order is
##                       reproducible across two independent runs
##   4. sand account   — after collapse and relaxation the sand total matches the
##                       initial bed plus the booked structure source, so a
##                       collapse returns nothing and loses nothing
##
## Uses `SandWaterDomain` and the T05 slope relaxation, so a collapse actually
## slumps rather than only flipping a flag.

const Domain = preload("res://scripts/simulation/sand_water_domain.gd")
const Structure = preload("res://scripts/structures/structure_state.gd")
const Field = preload("res://scripts/structures/structure_field.gd")

const GRID := 64
const CELL_M := 0.125
const SUBSTEP_S := 1.0 / 120.0
const DAMAGE_RATE_PER_S := 4.0
## Slope relaxation constants mirrored from the T05 coupler so the probe can run
## the slump on the CPU without a rendering device.
const RELAX_RATE_PER_S := 15.0
const DRY_REPOSE_TAN := 0.674

var failures: Array[String] = []
var lines: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_case_build_volume()
	_case_support_and_strength()
	_case_three_wall_order()
	_case_sand_account()
	_case_tower_and_base()
	if failures.is_empty():
		for line in lines:
			print(line)
		print("PASS: T06 structures grid=%d cases=%d" % [GRID, lines.size()])
		quit(0)
		return
	for failure in failures:
		printerr("FAIL: " + failure)
	quit(1)


func _make_domain() -> SandWaterDomain:
	var domain := Domain.new(GRID, CELL_M)
	for z in GRID:
		for x in GRID:
			var i: int = domain.index(x, z)
			domain.rock[i] = 0.0
			domain.sand[i] = 0.30
			domain.water[i] = 0.0
			domain.wetness[i] = 0.0
			domain.compaction[i] = 0.0
	return domain


func _make_wall(id: int, x: int, z: int, length: int, height_m: float,
		compaction: float) -> SandcastleStructure:
	var wall := Structure.new()
	wall.id = id
	wall.kind = Structure.Kind.WALL
	wall.name = "wall%d" % id
	wall.origin = Vector2i(x, z)
	wall.size = Vector2i(length, 1)
	wall.height_m = height_m
	wall.compaction = compaction
	return wall


## Removes a band of bed sand beside every wall so their lateral support is gone.
func _undermine(domain: SandWaterDomain, field: SandcastleStructureField) -> void:
	for structure in field.structures:
		for z in range(structure.origin.y, structure.origin.y + structure.size.y):
			for x in range(structure.origin.x - 1, structure.origin.x + structure.size.x + 1):
				if x < 0 or x >= GRID or structure.contains(x, z):
					continue
				domain.sand[z * GRID + x] = 0.0


## Runs the T05 slope relaxation on the CPU: same shared-edge rule, same single
## edge cap, so a collapse slumps with the sand total untouched.
func _relax(domain: SandWaterDomain, substeps: int) -> void:
	var blend := clampf(RELAX_RATE_PER_S * SUBSTEP_S, 0.0, 1.0)
	var offsets: Array[Vector2i] = [Vector2i(-1, 0), Vector2i(1, 0),
		Vector2i(0, -1), Vector2i(0, 1)]
	for _step in substeps:
		var delta := PackedFloat32Array()
		delta.resize(GRID * GRID)
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
		## The single-edge cap already bounds a cell's total outflow by its own
		## stock, so this max is defensive and never binds.
		for i in GRID * GRID:
			domain.sand[i] = maxf(domain.sand[i] + delta[i], 0.0)


func _total_sand(domain: SandWaterDomain) -> float:
	var area := domain.cell_size_m * domain.cell_size_m
	var total := 0.0
	for value in domain.sand:
		total += value * area
	return total


## G01: the kind decides the profile. A tower tapers on both axes so it can be
## built taller than a wall of the same footprint; a base pad does not taper.
func _case_tower_and_base() -> void:
	var tower_domain := _make_domain()
	var tower_field := Field.new()
	var tower := Structure.new()
	tower.kind = Structure.Kind.TOWER
	tower.origin = Vector2i(28, 28)
	tower.size = Vector2i(9, 9)
	tower.height_m = 0.45
	tower.taper_slope_m = 0.11
	tower.compaction = 0.9
	tower_field.add(tower, tower_domain)
	var centre := tower.height_at(32, 32)
	## A 9-cell footprint reaches level 4, so the corner keeps 0.45 - 0.44.
	var corner := tower.height_at(28, 28)
	var corner_expected := 0.45 - 0.11 * 4.0
	if absf(centre - 0.45) > 0.000001 or absf(corner - corner_expected) > 0.000001:
		failures.append("tower profile is not a two-axis pyramid: centre=%.6f corner=%.6f" % [
			centre, corner])
		return
	if absf(tower.height_at(32, 28) - 0.01) > 0.000001:
		failures.append("tower did not taper along both axes: %.6f" % tower.height_at(32, 28))
		return

	var base_domain := _make_domain()
	var base_field := Field.new()
	var pad := Structure.new()
	pad.kind = Structure.Kind.BASE
	pad.origin = Vector2i(10, 40)
	pad.size = Vector2i(8, 6)
	pad.height_m = 0.12
	pad.compaction = 0.6
	base_field.add(pad, base_domain)
	for z in range(pad.origin.y, pad.origin.y + pad.size.y):
		for x in range(pad.origin.x, pad.origin.x + pad.size.x):
			if absf(pad.height_at(x, z) - 0.12) > 0.000001:
				failures.append("base pad tapered at (%d, %d): %.6f" % [
					x, z, pad.height_at(x, z)])
				return
	lines.append("KINDS_OK tower_centre=%.6f tower_corner=%.6f tower_off_axis=%.6f " % [
		centre, corner, tower.height_at(32, 28)] +
		"base_flat=%s" % str(is_equal_approx(pad.height_at(10, 40), 0.12)))


func _case_build_volume() -> void:
	var domain := _make_domain()
	var field := Field.new()
	var wall := _make_wall(1, 20, 30, 12, 0.25, 0.4)
	var bed_before := _total_sand(domain)
	var before_surface: float = domain.rock[30 * GRID + 20] + domain.sand[30 * GRID + 20]
	var booked := field.add(wall, domain)
	var after_surface: float = domain.rock[30 * GRID + 20] + domain.sand[30 * GRID + 20]
	var expected := float(wall.cell_count()) * wall.height_m * CELL_M * CELL_M
	if absf(booked - expected) > 0.0000001:
		failures.append("wall booked %.9f m3, expected %.9f" % [booked, expected])
		return
	if absf(after_surface - before_surface - wall.height_m) > 0.0000001:
		failures.append("wall did not raise the drawn surface by its height: %.9f" % [
			after_surface - before_surface - wall.height_m])
		return
	if absf(_total_sand(domain) - bed_before - booked) > 0.0000001:
		failures.append("heightfield total does not match the booked wall volume")
		return
	if absf(domain.sand_source_m3 - booked) > 0.0000001:
		failures.append("structure volume was not booked as an external sand source")
		return
	lines.append("BUILD_OK cells=%d booked_m3=%.9f surface_rise_m=%.6f source_m3=%.9f" % [
		wall.cell_count(), booked, after_surface - before_surface, domain.sand_source_m3])


func _case_support_and_strength() -> void:
	var domain := _make_domain()
	var field := Field.new()
	var loose := _make_wall(1, 20, 30, 10, 0.25, 0.0)
	field.add(loose, domain)
	if loose.support_fraction(domain) < 0.999:
		failures.append("an untouched wall is not fully supported: %.6f" % [
			loose.support_fraction(domain)])
		return
	var loose_strength := field.strength_of(loose, domain)
	if loose_strength < 0.699 or loose_strength > 0.701:
		failures.append("loose wall strength %.6f is outside the curve" % loose_strength)
		return
	field.step(domain, SUBSTEP_S, DAMAGE_RATE_PER_S)
	if loose.damage > 0.000001:
		failures.append("a fully supported wall took damage: %.9f" % loose.damage)
		return

	var sturdy_domain := _make_domain()
	var sturdy_field := Field.new()
	var sturdy := _make_wall(1, 20, 30, 10, 0.25, 0.95)
	sturdy_field.add(sturdy, sturdy_domain)
	_undermine(sturdy_domain, sturdy_field)
	if sturdy.support_fraction(sturdy_domain) >= 1.0:
		failures.append("undermining did not remove any support")
		return
	var sturdy_strength := sturdy_field.strength_of(sturdy, sturdy_domain)
	for _step in 200:
		sturdy_field.step(sturdy_domain, SUBSTEP_S, DAMAGE_RATE_PER_S)
	if sturdy.damage <= 0.0:
		failures.append("an undermined wall took no damage")
		return
	if sturdy_strength <= loose_strength:
		failures.append("compaction did not raise strength: %.6f vs %.6f" % [
			sturdy_strength, loose_strength])
		return
	## The same undermining must hurt the loose wall more than the sturdy one.
	var loose_domain := _make_domain()
	var loose_field := Field.new()
	var weak := _make_wall(1, 20, 30, 10, 0.25, 0.0)
	loose_field.add(weak, loose_domain)
	_undermine(loose_domain, loose_field)
	for _step in 200:
		loose_field.step(loose_domain, SUBSTEP_S, DAMAGE_RATE_PER_S)
	if weak.damage <= sturdy.damage:
		failures.append("loose wall took less damage than the compacted one: %.6f vs %.6f" % [
			weak.damage, sturdy.damage])
		return
	lines.append("SUPPORT_OK supported_wall_damage=%.9f undermined_loose_damage=%.6f " % [
		loose.damage, weak.damage] +
		"undermined_sturdy_damage=%.6f strength_loose=%.6f strength_sturdy=%.6f" % [
			sturdy.damage, loose_strength, sturdy_strength])


func _three_wall_run() -> Dictionary:
	var domain := _make_domain()
	var field := Field.new()
	var compactions := [0.05, 0.5, 0.95]
	for index in compactions.size():
		field.add(_make_wall(index + 1, 12 + index * 20, 30, 10, 0.25,
			compactions[index]), domain)
	_undermine(domain, field)
	var order := PackedInt32Array()
	var collapse_ticks := PackedInt32Array()
	for step in 6000:
		for id in field.step(domain, SUBSTEP_S, DAMAGE_RATE_PER_S):
			order.append(id)
			collapse_ticks.append(step)
		if order.size() == compactions.size():
			break
	return {"order": order, "ticks": collapse_ticks}


func _case_three_wall_order() -> void:
	var first := _three_wall_run()
	var second := _three_wall_run()
	var order: PackedInt32Array = first.order
	if order.size() != 3:
		failures.append("only %d of 3 walls collapsed" % order.size())
		return
	if order[0] != 1 or order[1] != 2 or order[2] != 3:
		failures.append("walls did not collapse weakest-first: %s" % order)
		return
	if first.ticks != second.ticks or order != second.order:
		failures.append("collapse order or ticks are not reproducible: %s/%s vs %s/%s" % [
			order, first.ticks, second.order, second.ticks])
		return
	lines.append("THREE_WALL_OK order=%s collapse_substeps=%s " % [
		order, first.ticks] + "compactions=0.050/0.500/0.950")


func _case_sand_account() -> void:
	var domain := _make_domain()
	var field := Field.new()
	var wall := _make_wall(1, 20, 30, 10, 0.25, 0.0)
	var booked := field.add(wall, domain)
	var expected_total := _total_sand(domain)
	_undermine(domain, field)
	var undermined_total := _total_sand(domain)
	for _step in 4000:
		field.step(domain, SUBSTEP_S, DAMAGE_RATE_PER_S)
		if wall.collapsed:
			break
	if not wall.collapsed:
		failures.append("wall never collapsed, cannot check the account")
		return
	var after_collapse := _total_sand(domain)
	_relax(domain, 3000)
	var after_relax := _total_sand(domain)
	## Collapse itself must not move sand; only the undermining edit and the
	## relaxation may, and the relaxation is conservative.
	if absf(after_collapse - undermined_total) > 0.0000001:
		failures.append("collapse changed the sand total by %.9f m3" % [
			after_collapse - undermined_total])
		return
	if absf(after_relax - after_collapse) > 0.0001:
		failures.append("relaxation changed the sand total by %.9f m3" % [
			after_relax - after_collapse])
		return
	var loose_cells := 0
	for cell in wall.cells(GRID):
		if domain.compaction[cell] < 0.001:
			loose_cells += 1
	if loose_cells != wall.cell_count():
		failures.append("collapse did not loosen every wall cell: %d of %d" % [
			loose_cells, wall.cell_count()])
		return
	lines.append("ACCOUNT_OK booked_m3=%.9f undermined_m3=%.9f collapse_delta_m3=%.9f " % [
		booked, undermined_total - expected_total, after_collapse - undermined_total] +
		"relax_delta_m3=%.9f loosened_cells=%d" % [
			after_relax - after_collapse, loose_cells])

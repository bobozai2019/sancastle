class_name SandcastleStructure
extends RefCounted

## A parametric sand structure: a wall, tower or base pad, expressed as a raised
## band of sand over a rectangular footprint.
##
## ADR-002 keeps the first version on a heightmap, so a structure is not a
## separate solid: it is packed sand standing on the bed. That has two useful
## consequences the rest of T06 leans on:
##
##   * building one adds its volume to `sand` and to `sand_source_m3`, and
##     collapsing one does not remove anything - it only loosens the sand, so the
##     slope relaxation pass turns it into a natural talus with the sand account
##     untouched by construction.
##   * no obstacle bit is written, so no water volume has to be remapped on a
##     structural event. (The contract's "do not change the obstacle mask without
##     remapping water" rule is therefore not triggered.)
##
## Support is a purely local, state-driven quantity: a cell is supported by a
## neighbour that is either part of the same structure or whose surface is still
## close to the structure's base. There is no countdown anywhere.

enum Kind { WALL, TOWER, BASE }

const SUPPORT_TOLERANCE_M := 0.02

var id := 0
var kind := Kind.WALL
var name := ""
var origin := Vector2i.ZERO
var size := Vector2i(1, 1)
var height_m := 0.0
## Height shed per cell across the footprint's thin axis. A wall is built as a
## truncated pyramid rather than a vertical slab: a slab far steeper than the
## angle of repose would be flattened by the slope relaxation on the first
## substep, so it would never stand long enough to be undermined.
var taper_slope_m := 0.10
var compaction := 0.5
## Impermeable structures also set the obstacle bit over their footprint. That is
## the one structure event that changes the water's effective area, so it must go
## through `obstacle_remap` or it would swallow water.
var blocks_water := false
var damage := 0.0
var collapsed := false
var built_volume_m3 := 0.0


func cell_count() -> int:
	return size.x * size.y


## Volume the footprint would hold at the current profile, in cubic metres. Used
## to decide whether the bucket can pay for the build before it is applied.
func volume_m3(cell_size_m: float) -> float:
	var area := cell_size_m * cell_size_m
	var total := 0.0
	for z in range(origin.y, origin.y + size.y):
		for x in range(origin.x, origin.x + size.x):
			total += height_at(x, z) * area
	return total


func contains(x: int, z: int) -> bool:
	return x >= origin.x and x < origin.x + size.x and \
		z >= origin.y and z < origin.y + size.y


## How far a cell sits from the footprint centre, in cells, along the axes the
## kind tapers across:
##   WALL  tapers across the thin axis only - its length axis stays flat, which
##         is stable because a constant height has no slope.
##   TOWER tapers across both axes, so it is a pyramid that can be built taller
##         than a wall of the same footprint.
##   BASE  does not taper at all: it is a flat pad.
func taper_level(x: int, z: int) -> float:
	if kind == Kind.BASE:
		return 0.0
	var level_x := absf(float(x) - (float(origin.x) + (float(size.x) - 1.0) * 0.5))
	var level_z := absf(float(z) - (float(origin.y) + (float(size.y) - 1.0) * 0.5))
	if kind == Kind.TOWER:
		return maxf(level_x, level_z)
	return level_x if size.x <= size.y else level_z


## Structural height this cell carries, before the bed is considered.
func height_at(x: int, z: int) -> float:
	if collapsed or not contains(x, z):
		return 0.0
	return maxf(0.0, height_m - taper_slope_m * taper_level(x, z))


func cells(grid_size: int) -> PackedInt32Array:
	var result := PackedInt32Array()
	for z in range(origin.y, mini(origin.y + size.y, grid_size)):
		for x in range(origin.x, mini(origin.x + size.x, grid_size)):
			result.append(z * grid_size + x)
	return result


## Surface the structure currently contributes to a cell it owns. Zero once it
## has collapsed, because the sand is then loose fill rather than structure.
func surface_at(x: int, z: int) -> float:
	return height_at(x, z)


## Adds the structure to the heightfield, so `rock + sand` keeps matching the
## drawn surface and the sand ledger closes.
##
## `funded_by_bucket` decides where the sand comes from. False books it as an
## external source, which is what the tests and any pre-placed scenery use. True
## spends the player's tool inventory instead, so a structure built from dug sand
## is the same transaction as a `place_sand` command and cannot manufacture mass.
func build(domain: SandWaterDomain, funded_by_bucket := false) -> float:
	if built_volume_m3 > 0.0:
		return 0.0
	var area := domain.cell_size_m * domain.cell_size_m
	var volume := 0.0
	for cell in cells(domain.grid_size):
		var x := cell % domain.grid_size
		var z := cell / domain.grid_size
		var height := height_at(x, z)
		domain.sand[cell] += height
		domain.compaction[cell] = clampf(compaction, 0.0, 1.0)
		volume += height * area
	built_volume_m3 = volume
	if funded_by_bucket:
		domain.tool_inventory_m3 -= built_volume_m3
	else:
		domain.sand_source_m3 += built_volume_m3
	return built_volume_m3


## Fraction of the structure's boundary that is still buttressed by either its own
## cells or bed that has not dropped away from its base. 1 means fully supported.
func support_fraction(domain: SandWaterDomain) -> float:
	if collapsed:
		return 0.0
	var supported := 0
	var total := 0
	for z in range(origin.y, origin.y + size.y):
		for x in range(origin.x, origin.x + size.x):
			if x < 0 or z < 0 or x >= domain.grid_size or z >= domain.grid_size:
				continue
			for offset in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
				var nx: int = x + offset.x
				var nz: int = z + offset.y
				if nx < 0 or nz < 0 or nx >= domain.grid_size or nz >= domain.grid_size:
					continue
				total += 1
				var neighbour := nz * domain.grid_size + nx
				if contains(nx, nz):
					supported += 1
					continue
				var neighbour_surface: float = domain.rock[neighbour] + domain.sand[neighbour]
				var base: float = domain.rock[z * domain.grid_size + x] + \
					domain.sand[z * domain.grid_size + x] - height_at(x, z)
				if neighbour_surface >= base - SUPPORT_TOLERANCE_M:
					supported += 1
	if total == 0:
		return 1.0
	return float(supported) / float(total)


## Damage accrues whenever support is missing, scaled by the same material
## strength the erosion pass uses, so a compacted or damp wall survives longer.
## A wall that is fully supported never accumulates damage.
func accumulate_damage(domain: SandWaterDomain, delta_s: float,
		damage_rate_per_s: float, strength: float) -> void:
	if collapsed or damage_rate_per_s <= 0.0 or delta_s <= 0.0:
		return
	var missing := 1.0 - clampf(support_fraction(domain), 0.0, 1.0)
	if missing <= 0.0:
		return
	damage += missing * damage_rate_per_s * delta_s / maxf(strength, 0.000001)


## Topology, bookkeeping and accumulated damage, for the checkpoint's `structures`
## array. The sand itself travels in the `sand` field, so this carries only what
## the heightfield cannot: identity, footprint, profile, damage and the ledger
## entry that funded it.
func to_dict() -> Dictionary:
	return {"id": id, "kind": kind, "name": name, "origin": origin, "size": size,
		"height_m": height_m, "taper_slope_m": taper_slope_m,
		"compaction": compaction, "blocks_water": blocks_water, "damage": damage,
		"collapsed": collapsed, "built_volume_m3": built_volume_m3}


static func from_dict(data: Dictionary) -> SandcastleStructure:
	var structure := SandcastleStructure.new()
	structure.id = int(data.get("id", 0))
	structure.kind = int(data.get("kind", Kind.WALL))
	structure.name = str(data.get("name", ""))
	structure.origin = data.get("origin", Vector2i.ZERO)
	structure.size = data.get("size", Vector2i(1, 1))
	structure.height_m = float(data.get("height_m", 0.0))
	structure.taper_slope_m = float(data.get("taper_slope_m", 0.10))
	structure.compaction = float(data.get("compaction", 0.5))
	structure.blocks_water = bool(data.get("blocks_water", false))
	structure.damage = float(data.get("damage", 0.0))
	structure.collapsed = bool(data.get("collapsed", false))
	structure.built_volume_m3 = float(data.get("built_volume_m3", 0.0))
	return structure


## Collapse loosens the structure in place: the sand is already in the
## heightfield, so this only drops compaction to a loose value. The T05 slope
## relaxation then slumps it, which conserves sand by construction.
func collapse(domain: SandWaterDomain, loose_compaction: float = 0.0) -> bool:
	if collapsed:
		return false
	collapsed = true
	damage = 1.0
	for cell in cells(domain.grid_size):
		domain.compaction[cell] = clampf(loose_compaction, 0.0, 1.0)
	return true

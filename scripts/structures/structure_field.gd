class_name SandcastleStructureField
extends RefCounted

## Owns the structures of one domain and drives their damage each step.
##
## The field adds no new physics: it reuses the T05 strength curve for how long
## a wall resists losing support, and the T05 conservative slope relaxation for
## what happens once it lets go. Everything here is a deterministic function of
## the shared state, so a replay reproduces the same collapse ticks.

const LOOSE_COMPACTION := 0.0

var structures: Array[SandcastleStructure] = []
## Bumped whenever the field is rebuilt. Events carrying an older generation are
## rejected, which is the CPU-reference analogue of the preview's rule that a
## callback from a replaced scene must not touch the live one.
var generation := 1
## Compaction each structure was built with, so strength keeps using the built
## value after a collapse zeroes the live field.
var _built_compaction: Dictionary = {}


## Returns the booked volume, or 0.0 when the build was refused. With
## `funded_by_bucket` the build is refused unless the inventory already covers it,
## so a player cannot conjure sand by placing a structure.
func add(structure: SandcastleStructure, domain: SandWaterDomain,
		funded_by_bucket := false) -> float:
	if funded_by_bucket:
		var required := structure.volume_m3(domain.cell_size_m)
		if domain.tool_inventory_m3 + 0.000001 < required:
			return 0.0
	structure.id = structures.size() + 1
	structures.append(structure)
	_built_compaction[structure.id] = clampf(structure.compaction, 0.0, 1.0)
	return structure.build(domain, funded_by_bucket)


## Drops every structure without invalidating anything. Used between test cycles,
## where the heightfield is restored by the caller.
func clear() -> void:
	structures.clear()
	_built_compaction.clear()


## Same, but also invalidates outstanding references: events carrying the old
## generation are then rejected. This is the CPU-reference analogue of the
## preview's rule that a callback from a replaced scene must not touch the live
## one.
func rebuild() -> void:
	clear()
	generation += 1


## Applies an externally delivered collapse, but only when the event belongs to
## the current generation. Returns true when the event took effect.
func apply_collapse(structure_id: int, event_generation: int,
		domain: SandWaterDomain) -> bool:
	if event_generation != generation:
		return false
	var structure := find(structure_id)
	if structure == null:
		return false
	return structure.collapse(domain, LOOSE_COMPACTION)


## Strength uses the erosion pass's curve, but with the structure's built
## compaction rather than the live field, which collapse overwrites.
func strength_of(structure: SandcastleStructure, domain: SandWaterDomain) -> float:
	var compaction: float = _built_compaction.get(structure.id, structure.compaction)
	var wetness := 0.0
	var cells := structure.cells(domain.grid_size)
	if not cells.is_empty():
		var total := 0.0
		for cell in cells:
			total += domain.wetness[cell]
		wetness = total / float(cells.size())
	return lerpf(0.7, 1.8, clampf(compaction, 0.0, 1.0)) * lerpf(1.0, 1.25, wetness)


## One damage step for every standing structure. Returns the ids that collapsed
## during this step, in structure order, so a caller can log the order.
func step(domain: SandWaterDomain, delta_s: float,
		damage_rate_per_s: float) -> PackedInt32Array:
	var collapsed_now := PackedInt32Array()
	for structure in structures:
		if structure.collapsed:
			continue
		structure.accumulate_damage(domain, delta_s, damage_rate_per_s,
			strength_of(structure, domain))
		if structure.damage >= 1.0:
			structure.collapse(domain, LOOSE_COMPACTION)
			collapsed_now.append(structure.id)
	return collapsed_now


func find(id: int) -> SandcastleStructure:
	for structure in structures:
		if structure.id == id:
			return structure
	return null


## The domain's obstacle mask implied by the field: 1 over the footprint of every
## impermeable structure that has not collapsed, 0 elsewhere. Collapsing one clears
## its bits, which only ever opens area up, so no water has to be remapped back.
func obstacle_mask(grid_size: int) -> PackedFloat32Array:
	var mask := PackedFloat32Array()
	mask.resize(grid_size * grid_size)
	mask.fill(0.0)
	for structure in structures:
		if not structure.blocks_water or structure.collapsed:
			continue
		for cell in structure.cells(grid_size):
			mask[cell] = 1.0
	return mask


## True when the field contains at least one impermeable, standing structure.
func has_impermeable() -> bool:
	for structure in structures:
		if structure.blocks_water and not structure.collapsed:
			return true
	return false


## Checkpoint payload: the topology plus the compaction each structure was built
## with. The `sand` and `compaction` fields already carry the heightfield, so a
## restore only needs this to recover the support graph.
func to_dict() -> Dictionary:
	var entries: Array[Dictionary] = []
	for structure in structures:
		entries.append(structure.to_dict())
	var built: Dictionary = {}
	for key in _built_compaction:
		built[str(key)] = _built_compaction[key]
	return {"generation": generation, "structures": entries, "built_compaction": built}


func restore(data: Dictionary) -> bool:
	structures.clear()
	_built_compaction.clear()
	var entries: Variant = data.get("structures", [])
	if typeof(entries) != TYPE_ARRAY:
		return false
	for entry in entries:
		if typeof(entry) != TYPE_DICTIONARY:
			return false
		structures.append(SandcastleStructure.from_dict(entry))
	var built: Variant = data.get("built_compaction", {})
	if typeof(built) == TYPE_DICTIONARY:
		for key in built:
			_built_compaction[int(key)] = float(built[key])
	generation = maxi(generation, int(data.get("generation", 1)))
	return true


## Patch records for `SandcastleGpuShallowSolver.dispatch_tool_patch`:
## `(cell_index, sand_m, compaction, 0)` per owned cell, already ascending.
##
## This is the whole GPU integration for sand structures: building pushes the
## raised, compacted cells, and collapsing pushes the same cells back with
## compaction dropped. No new GPU pass and no obstacle bit, so the drawn mesh,
## the collision proxy and the water solver all follow from the same heightfield.
func patch_for(structure: SandcastleStructure, domain: SandWaterDomain) -> Dictionary:
	var indices := structure.cells(domain.grid_size)
	var stream := StreamPeerBuffer.new()
	stream.big_endian = false
	for index in indices:
		stream.put_32(index)
		stream.put_float(domain.sand[index])
		stream.put_float(domain.compaction[index])
		stream.put_float(0.0)
	return {"count": indices.size(), "data": stream.data_array,
		"dirty_cells": indices}

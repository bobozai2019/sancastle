extends RefCounted

## Independent float64 oracle for conservative_displacement_v1.
## Input and output are isolated data; this does not modify a live Domain or RD.
static func build(fields: Dictionary, size: int, cell_size: float) -> Dictionary:
	var count := size * size
	if size < 2 or not is_finite(cell_size) or cell_size <= 0.0:
		return {"ok": false, "error": "invalid_layout"}
	for key in ["old_bed", "new_bed", "water", "sediment", "momentum_x", "momentum_z", "obstacle"]:
		if not fields.has(key) or fields[key].size() != count:
			return {"ok": false, "error": "invalid_field", "field": key}
		for value in fields[key]:
			if not is_finite(value) or (key in ["water", "sediment"] and value < 0.0):
				return {"ok": false, "error": "invalid_state", "field": key}
	var result := {}
	for key in ["water", "sediment", "momentum_x", "momentum_z"]:
		result[key] = PackedFloat64Array(Array(fields[key]))
	var labels := PackedInt32Array()
	labels.resize(count)
	labels.fill(-1)
	var components := []
	var area := cell_size * cell_size
	var moved_total := 0.0
	var retained_total := 0.0
	var lost_x := 0.0
	var lost_z := 0.0
	for seed in count:
		if labels[seed] != -1 or fields.water[seed] <= 0.001 or fields.obstacle[seed] >= 0.5:
			continue
		var members := PackedInt32Array([seed])
		labels[seed] = components.size()
		var head := 0
		while head < members.size():
			var i := members[head]
			head += 1
			var neighbors := PackedInt32Array()
			if i % size > 0: neighbors.append(i - 1)
			if i % size < size - 1: neighbors.append(i + 1)
			if i >= size: neighbors.append(i - size)
			if i < count - size: neighbors.append(i + size)
			for j in neighbors:
				if labels[j] == -1 and fields.water[j] > 0.001 and fields.obstacle[j] < 0.5:
					labels[j] = components.size()
					members.append(j)
		members.sort()
		var eta_max := -INF
		for i in members: eta_max = maxf(eta_max, fields.old_bed[i] + fields.water[i])
		var donors := {}
		var receivers := {}
		var demand := 0.0
		var capacity := 0.0
		for i in members:
			var rise: float = fields.new_bed[i] - fields.old_bed[i]
			if rise > 0.0:
				var depth := minf(fields.water[i], rise)
				donors[i] = depth
				demand += depth * area
			else:
				var room := maxf(0.0, eta_max + 0.02 - fields.new_bed[i] - fields.water[i]) * area
				if room > 0.0:
					receivers[i] = room
					capacity += room
		var moved := minf(demand, capacity)
		var fraction := moved / demand if demand > 0.0 else 0.0
		var sediment_moved := 0.0
		var qx_moved := 0.0
		var qz_moved := 0.0
		for i in donors:
			var depth: float = donors[i] * fraction
			var proportion: float = depth / fields.water[i]
			result.water[i] -= depth
			var sed: float = fields.sediment[i] * proportion
			var qx: float = fields.momentum_x[i] * proportion
			var qz: float = fields.momentum_z[i] * proportion
			result.sediment[i] -= sed
			result.momentum_x[i] -= qx
			result.momentum_z[i] -= qz
			sediment_moved += sed * area
			qx_moved += qx * area
			qz_moved += qz * area
			if result.water[i] <= 0.001:
				lost_x += result.momentum_x[i] * area
				lost_z += result.momentum_z[i] * area
				result.momentum_x[i] = 0.0
				result.momentum_z[i] = 0.0
		for i in receivers:
			var share: float = receivers[i] / capacity
			result.water[i] += moved * share / area
			result.sediment[i] += sediment_moved * share / area
			result.momentum_x[i] += qx_moved * share / area
			result.momentum_z[i] += qz_moved * share / area
		components.append({"seed": seed, "cells": members.size(), "demand_m3": demand,
			"capacity_m3": capacity, "moved_m3": moved, "retained_m3": demand - moved,
			"capacity_status": 1 if capacity < demand else 0, "eta_limit_m": eta_max + 0.02})
		moved_total += moved
		retained_total += demand - moved
	result.ok = true
	result.components = components
	result.labels = labels
	result.displaced_water_m3 = moved_total
	result.retained_water_m3 = retained_total
	result.dry_momentum_loss = PackedFloat64Array([lost_x, lost_z])
	result.scope = "float64 policy oracle; not GPU candidate or R32F residual settlement"
	return result


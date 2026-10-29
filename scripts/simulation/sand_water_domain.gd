class_name SandWaterDomain
extends RefCounted

## Deterministic CPU reference for the water/sand state contract.
## Scalar fields store heights in metres. Flux stores volume flow in m³/s.

const EPSILON := 0.000001
const MAX_BRUSH_RADIUS_M := 4.0
const COMMAND_KINDS := [&"remove_sand", &"place_sand", &"smooth", &"compact", &"debug_add_sand"]

var grid_size: int
var cell_size_m: float
var cell_area_m2: float
var sim_tick: int = 0
var generation: int = 1
var domain_id: StringName = &"main_beach"
var tool_inventory_m3: float = 0.0

var rock := PackedFloat32Array()
var sand := PackedFloat32Array()
var water := PackedFloat32Array()
var sediment := PackedFloat32Array()
var wetness := PackedFloat32Array()
var compaction := PackedFloat32Array()
var obstacle := PackedFloat32Array()
var flux_left := PackedFloat32Array()
var flux_right := PackedFloat32Array()
var flux_up := PackedFloat32Array()
var flux_down := PackedFloat32Array()

var water_source_m3: float = 0.0
var water_sink_m3: float = 0.0
var sand_source_m3: float = 0.0
var sand_sink_m3: float = 0.0
var clamped_water_events: int = 0
var clamped_sand_events: int = 0
var nan_events: int = 0


func _init(size: int = 64, p_cell_size_m: float = 0.125) -> void:
	grid_size = maxi(size, 2)
	cell_size_m = maxf(p_cell_size_m, 0.001)
	cell_area_m2 = cell_size_m * cell_size_m
	var count := grid_size * grid_size
	for field in [rock, sand, water, sediment, wetness, compaction, obstacle,
			flux_left, flux_right, flux_up, flux_down]:
		field.resize(count)
		field.fill(0.0)


func index(x: int, y: int) -> int:
	return y * grid_size + x


func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < grid_size and y < grid_size


func bed_at(i: int) -> float:
	# Through T04, sand is reference-density thickness and geometry thickness.
	# T05 may introduce a density curve only with explicit volume remapping.
	return rock[i] + sand[i]


func surface_at(i: int) -> float:
	return bed_at(i) + water[i]


func total_water_m3() -> float:
	var total := 0.0
	for value in water:
		total += value * cell_area_m2
	return total


func total_sand_m3(include_inventory: bool = true) -> float:
	var total := tool_inventory_m3 if include_inventory else 0.0
	for i in sand.size():
		total += (sand[i] + sediment[i]) * cell_area_m2
	return total


func initialize_beach(seed_value: int = 1) -> void:
	seed(seed_value)
	for y in grid_size:
		for x in grid_size:
			var i := index(x, y)
			var nx := float(x) / float(grid_size - 1)
			var ny := float(y) / float(grid_size - 1)
			rock[i] = -0.35 + nx * 0.45
			sand[i] = 0.42 + 0.035 * sin(ny * TAU * 2.0) + randf_range(-0.004, 0.004)
			water[i] = maxf(0.0, 0.16 - bed_at(i))
			wetness[i] = clampf(water[i] * 8.0, 0.0, 1.0)


func apply_tool(command: Dictionary) -> Dictionary:
	var validation := _validate_command(command)
	if not validation.is_empty():
		return _command_result(command, &"rejected", 0.0, PackedInt32Array(), validation)
	var kind: StringName = command["kind"]
	var position: Vector3 = command["position_m"]
	var radius: float = command["radius_m"]
	var strength: float = command["strength"]
	var amount: float = command.get("amount_m3", 0.0) * strength
	var start_xz := Vector2(position.x, position.z)
	var end_position: Vector3 = command.get("end_position_m", position)
	var end_xz := Vector2(end_position.x, end_position.z)
	var cells := _brush_cells(start_xz, radius, end_xz)
	if cells.is_empty():
		return _command_result(command, &"rejected", 0.0, PackedInt32Array(), &"out_of_domain")
	var changed := PackedInt32Array()
	var sand_delta := 0.0
	match kind:
		&"remove_sand":
			var removed := _remove_sand(cells, amount)
			tool_inventory_m3 += removed
			sand_delta = removed
			changed = _cell_ids(cells)
		&"place_sand":
			if tool_inventory_m3 + EPSILON < amount:
				return _command_result(command, &"rejected", 0.0, PackedInt32Array(), &"insufficient_sand")
			var placed := _place_sand(cells, amount)
			tool_inventory_m3 -= placed
			sand_delta = -placed
			changed = _cell_ids(cells)
		&"debug_add_sand":
			var added := _place_sand(cells, amount)
			sand_source_m3 += added
			sand_delta = -added
			changed = _cell_ids(cells)
		&"smooth":
			_smooth_cells(cells, strength)
			changed = _cell_ids(cells)
		&"compact":
			for entry in cells:
				var i: int = entry[0]
				compaction[i] = clampf(compaction[i] + 0.2 * strength * entry[1], 0.0, 1.0)
			changed = _cell_ids(cells)
	return _command_result(command, &"applied", sand_delta, changed, StringName())


func step(delta: float, enable_erosion: bool = true) -> void:
	if delta <= 0.0:
		return
	step_water(delta)
	step_post_water(delta, enable_erosion)
	sim_tick += 1
	_audit_finite()


func step_post_water(delta: float, enable_erosion: bool = true) -> void:
	if enable_erosion:
		step_erosion(delta)
	step_moisture(delta)


func step_water(delta: float, gravity_factor: float = 2.4) -> void:
	flux_left.fill(0.0)
	flux_right.fill(0.0)
	flux_up.fill(0.0)
	flux_down.fill(0.0)
	var requested := PackedFloat32Array()
	requested.resize(water.size())
	requested.fill(0.0)
	for y in grid_size:
		for x in grid_size:
			var i := index(x, y)
			if obstacle[i] >= 0.5 or water[i] <= EPSILON:
				continue
			var surface := surface_at(i)
			for direction in 4:
				var nx := x + (1 if direction == 1 else -1 if direction == 0 else 0)
				var ny := y + (1 if direction == 3 else -1 if direction == 2 else 0)
				if not in_bounds(nx, ny):
					continue
				var ni := index(nx, ny)
				if obstacle[ni] >= 0.5:
					continue
				var difference := surface - surface_at(ni)
				if difference <= 0.0:
					continue
				var rate := difference * gravity_factor * cell_area_m2
				match direction:
					0: flux_left[i] = rate
					1: flux_right[i] = rate
					2: flux_up[i] = rate
					3: flux_down[i] = rate
				requested[i] += rate
	var scale := PackedFloat32Array()
	scale.resize(water.size())
	scale.fill(1.0)
	for i in water.size():
		if requested[i] * delta > water[i] * cell_area_m2:
			scale[i] = water[i] * cell_area_m2 / maxf(requested[i] * delta, EPSILON)
	var delta_water := PackedFloat32Array()
	var delta_sediment := PackedFloat32Array()
	delta_water.resize(water.size())
	delta_sediment.resize(sediment.size())
	delta_water.fill(0.0)
	delta_sediment.fill(0.0)
	for y in grid_size:
		for x in grid_size:
			var i := index(x, y)
			var rates := [flux_left[i], flux_right[i], flux_up[i], flux_down[i]]
			for direction in 4:
				var rate: float = rates[direction] * scale[i]
				if rate <= 0.0:
					continue
				var nx := x + (1 if direction == 1 else -1 if direction == 0 else 0)
				var ny := y + (1 if direction == 3 else -1 if direction == 2 else 0)
				var ni := index(nx, ny)
				var transfer := rate * delta / cell_area_m2
				delta_water[i] -= transfer
				delta_water[ni] += transfer
				# Use the same outgoing water flux and the upstream sand concentration.
				var transported := transfer * sediment[i] / maxf(water[i], EPSILON)
				delta_sediment[i] -= transported
				delta_sediment[ni] += transported
				match direction:
					0: flux_left[i] = rate
					1: flux_right[i] = rate
					2: flux_up[i] = rate
					3: flux_down[i] = rate
	for i in water.size():
		water[i] += delta_water[i]
		sediment[i] += delta_sediment[i]
		if water[i] < -EPSILON:
			clamped_water_events += 1
		water[i] = maxf(water[i], 0.0)
		if sediment[i] < -EPSILON:
			clamped_sand_events += 1
		sediment[i] = maxf(sediment[i], 0.0)


func step_erosion(delta: float) -> void:
	var sand_delta := PackedFloat32Array()
	var sediment_delta := PackedFloat32Array()
	sand_delta.resize(sand.size())
	sediment_delta.resize(sediment.size())
	sand_delta.fill(0.0)
	sediment_delta.fill(0.0)
	for i in sand.size():
		if water[i] <= 0.002 or obstacle[i] >= 0.5:
			continue
		var flow_speed := (flux_left[i] + flux_right[i] + flux_up[i] + flux_down[i]) / cell_area_m2
		var strength := lerpf(0.7, 1.8, compaction[i]) * lerpf(1.0, 1.25, wetness[i])
		var capacity := maxf(0.0, flow_speed * water[i] * 0.08 / strength)
		if sediment[i] < capacity:
			var eroded := minf(sand[i], (capacity - sediment[i]) * 0.35 * delta)
			sand_delta[i] -= eroded
			sediment_delta[i] += eroded
		else:
			var deposited := minf(sediment[i], (sediment[i] - capacity) * 0.45 * delta)
			sand_delta[i] += deposited
			sediment_delta[i] -= deposited
	for i in sand.size():
		sand[i] += sand_delta[i]
		sediment[i] += sediment_delta[i]
		if sand[i] < -EPSILON or sediment[i] < -EPSILON:
			clamped_sand_events += 1
		sand[i] = maxf(sand[i], 0.0)
		sediment[i] = maxf(sediment[i], 0.0)


func step_moisture(delta: float, dry_rate: float = 0.012) -> void:
	for i in wetness.size():
		if water[i] > 0.001:
			wetness[i] = minf(1.0, wetness[i] + delta * 2.0)
		else:
			wetness[i] = maxf(0.0, wetness[i] - delta * dry_rate)


func relax_slopes(max_height_difference: float = 0.12, rate: float = 0.2) -> void:
	var changes := PackedFloat32Array()
	changes.resize(sand.size())
	changes.fill(0.0)
	for y in grid_size:
		for x in grid_size:
			var i := index(x, y)
			for offset: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
				var nx: int = x + offset.x
				var ny: int = y + offset.y
				if not in_bounds(nx, ny):
					continue
				var ni := index(nx, ny)
				var difference := bed_at(i) - bed_at(ni)
				var allowed := max_height_difference * lerpf(0.75, 1.45, compaction[i])
				if absf(difference) <= allowed:
					continue
				var high := i if difference > 0.0 else ni
				var low := ni if difference > 0.0 else i
				var moved := minf(sand[high], (absf(difference) - allowed) * rate)
				changes[high] -= moved
				changes[low] += moved
	for i in sand.size():
		sand[i] = maxf(0.0, sand[i] + changes[i])


func set_tide_boundary(level_m: float) -> void:
	for y in grid_size:
		var i := index(0, y)
		var old := water[i]
		water[i] = maxf(0.0, level_m - bed_at(i))
		_record_water_source_delta((water[i] - old) * cell_area_m2)


func snapshot() -> Dictionary:
	return {
		"format_version": 1, "sim_tick": sim_tick, "generation": generation,
		"domain_id": domain_id, "grid_size": grid_size, "cell_size_m": cell_size_m,
		"rock": rock.duplicate(), "sand": sand.duplicate(), "water": water.duplicate(),
		"sediment": sediment.duplicate(), "wetness": wetness.duplicate(),
		"compaction": compaction.duplicate(), "obstacle": obstacle.duplicate(),
		"flux_left": flux_left.duplicate(), "flux_right": flux_right.duplicate(),
		"flux_up": flux_up.duplicate(), "flux_down": flux_down.duplicate(),
		"tool_inventory_m3": tool_inventory_m3,
		"water_source_m3": water_source_m3, "water_sink_m3": water_sink_m3,
		"sand_source_m3": sand_source_m3, "sand_sink_m3": sand_sink_m3
	}


func restore(data: Dictionary) -> bool:
	if data.get("format_version", 0) != 1 or data.get("grid_size", 0) != grid_size:
		return false
	for key in [&"rock", &"sand", &"water", &"sediment", &"wetness", &"compaction", &"obstacle",
			&"flux_left", &"flux_right", &"flux_up", &"flux_down"]:
		if not data.has(key) or data[key].size() != grid_size * grid_size:
			return false
		set(key, data[key].duplicate())
	sim_tick = data["sim_tick"]
	domain_id = data.get("domain_id", &"main_beach")
	tool_inventory_m3 = data.get("tool_inventory_m3", 0.0)
	water_source_m3 = data.get("water_source_m3", 0.0)
	water_sink_m3 = data.get("water_sink_m3", 0.0)
	sand_source_m3 = data.get("sand_source_m3", 0.0)
	sand_sink_m3 = data.get("sand_sink_m3", 0.0)
	generation += 1
	return true


func _validate_command(command: Dictionary) -> StringName:
	for key in [&"command_id", &"kind", &"position_m", &"radius_m", &"strength"]:
		if not command.has(key):
			return &"invalid_command"
	if StringName(command["kind"]) not in COMMAND_KINDS:
		return &"invalid_command"
	if not command["position_m"] is Vector3 or command["radius_m"] <= 0.0 or command["radius_m"] > MAX_BRUSH_RADIUS_M:
		return &"invalid_command"
	if command.get("shape", &"circle") not in [&"circle", &"swept_segment"]:
		return &"invalid_command"
	if command.get("shape", &"circle") == &"swept_segment" and not command.get("end_position_m") is Vector3:
		return &"invalid_command"
	if command["strength"] < 0.0 or command["strength"] > 1.0:
		return &"invalid_command"
	if command["kind"] in [&"remove_sand", &"place_sand", &"debug_add_sand"] and command.get("amount_m3", 0.0) <= 0.0:
		return &"invalid_command"
	return StringName()


func _brush_cells(position_xz: Vector2, radius_m: float, end_xz: Vector2 = Vector2.INF) -> Array:
	var cells: Array = []
	var half_extent := grid_size * cell_size_m * 0.5
	if end_xz == Vector2.INF:
		end_xz = position_xz
	var segment := end_xz - position_xz
	var segment_length_squared := segment.length_squared()
	# Only cells inside the capsule's bounding box can pass the distance test.
	# Keep one extra cell on each side for float rounding at the boundary.
	var first_x := clampi(floori((minf(position_xz.x, end_xz.x) - radius_m +
		half_extent) / cell_size_m - 0.5) - 1, 0, grid_size - 1)
	var last_x := clampi(ceili((maxf(position_xz.x, end_xz.x) + radius_m +
		half_extent) / cell_size_m - 0.5) + 1, 0, grid_size - 1)
	var first_y := clampi(floori((minf(position_xz.y, end_xz.y) - radius_m +
		half_extent) / cell_size_m - 0.5) - 1, 0, grid_size - 1)
	var last_y := clampi(ceili((maxf(position_xz.y, end_xz.y) + radius_m +
		half_extent) / cell_size_m - 0.5) + 1, 0, grid_size - 1)
	for y in range(first_y, last_y + 1):
		for x in range(first_x, last_x + 1):
			var cell_position := Vector2((x + 0.5) * cell_size_m - half_extent, (y + 0.5) * cell_size_m - half_extent)
			var closest := position_xz
			if segment_length_squared > EPSILON:
				var t := clampf((cell_position - position_xz).dot(segment) / segment_length_squared, 0.0, 1.0)
				closest += segment * t
			var distance := cell_position.distance_to(closest)
			if distance <= radius_m:
				cells.append([index(x, y), maxf(0.001, 1.0 - distance / radius_m)])
	return cells


func _remove_sand(cells: Array, requested_m3: float) -> float:
	var weights := 0.0
	for entry in cells:
		weights += entry[1]
	var remaining := requested_m3
	var removed := 0.0
	for _iteration in 4:
		if remaining <= EPSILON:
			break
		var active_weight := 0.0
		for entry in cells:
			if sand[entry[0]] * cell_area_m2 > EPSILON:
				active_weight += entry[1]
		if active_weight <= EPSILON:
			break
		var pass_removed := 0.0
		for entry in cells:
			var i: int = entry[0]
			var available := sand[i] * cell_area_m2
			var take := minf(available, remaining * entry[1] / active_weight)
			sand[i] -= take / cell_area_m2
			pass_removed += take
		removed += pass_removed
		remaining -= pass_removed
	return removed


func _place_sand(cells: Array, amount_m3: float) -> float:
	var weights := 0.0
	for entry in cells:
		weights += entry[1]
	if weights <= EPSILON:
		return 0.0
	for entry in cells:
		sand[entry[0]] += (amount_m3 * entry[1] / weights) / cell_area_m2
	return amount_m3


func _smooth_cells(cells: Array, strength: float) -> void:
	var before_total := 0.0
	var target := 0.0
	var weights := 0.0
	for entry in cells:
		var i: int = entry[0]
		before_total += sand[i]
		target += sand[i] * entry[1]
		weights += entry[1]
	if weights <= EPSILON:
		return
	target /= weights
	for entry in cells:
		var i: int = entry[0]
		sand[i] = lerpf(sand[i], target, strength * entry[1])
	var after_total := 0.0
	for entry in cells:
		after_total += sand[entry[0]]
	var correction := (before_total - after_total) / float(cells.size())
	for entry in cells:
		sand[entry[0]] = maxf(0.0, sand[entry[0]] + correction)


func _cell_ids(cells: Array) -> PackedInt32Array:
	var ids := PackedInt32Array()
	for entry in cells:
		ids.append(entry[0])
	return ids


func _command_result(command: Dictionary, status: StringName, sand_delta: float,
		dirty: PackedInt32Array, error: StringName) -> Dictionary:
	var dirty_chunks := PackedInt32Array()
	var chunks_per_row := ceili(float(grid_size) / 32.0)
	for i in dirty:
		var x := i % grid_size
		var y := i / grid_size
		var chunk_id := (y / 32) * chunks_per_row + x / 32
		if not dirty_chunks.has(chunk_id):
			dirty_chunks.append(chunk_id)
	dirty_chunks.sort()
	return {"command_id": command.get("command_id", -1), "status": status,
		"applied_tick": sim_tick if status == &"applied" else null,
		"sand_delta_m3": sand_delta, "dirty_cells": dirty,
		"dirty_chunks": dirty_chunks, "error_code": error}


func _record_water_source_delta(delta_m3: float) -> void:
	if delta_m3 >= 0.0:
		water_source_m3 += delta_m3
	else:
		water_sink_m3 -= delta_m3


func _audit_finite() -> void:
	for field in [sand, water, sediment, wetness, compaction]:
		for value in field:
			if is_nan(value) or is_inf(value):
				nan_events += 1

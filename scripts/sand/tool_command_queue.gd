class_name ToolCommandQueue
extends RefCounted

## Orders user edits at fixed simulation ticks and keeps bounded snapshots for undo.

const MAX_UNDO := 32
const REPLAY_FORMAT_VERSION := 1

var domain: SandWaterDomain
var pending: Array[Dictionary] = []
var applied_log: Array[Dictionary] = []
var undo_stack: Array[Dictionary] = []
var redo_stack: Array[Dictionary] = []
var last_command_id := 0


func _init(p_domain: SandWaterDomain) -> void:
	domain = p_domain


func submit(command: Dictionary) -> StringName:
	for field in [&"domain_id", &"sim_tick", &"command_id", &"kind", &"shape",
			&"transform", &"radius_m", &"strength", &"seed"]:
		if not command.has(field):
			return &"invalid_command"
	if command["domain_id"] != domain.domain_id:
		return &"out_of_domain"
	if command.has("generation"):
		if typeof(command["generation"]) != TYPE_INT:
			return &"invalid_command"
		if command["generation"] != domain.generation:
			return &"inactive_generation"
	if typeof(command["sim_tick"]) != TYPE_INT or typeof(command["command_id"]) != TYPE_INT or typeof(command["seed"]) != TYPE_INT:
		return &"invalid_command"
	if typeof(command["radius_m"]) not in [TYPE_FLOAT, TYPE_INT] or typeof(command["strength"]) not in [TYPE_FLOAT, TYPE_INT]:
		return &"invalid_command"
	if command["sim_tick"] < domain.sim_tick:
		return &"stale_tick"
	if command["command_id"] <= last_command_id:
		return &"invalid_command"
	if command["shape"] not in [&"circle", &"swept_segment"]:
		return &"invalid_command"
	if StringName(command["kind"]) not in domain.COMMAND_KINDS:
		return &"invalid_command"
	if not command["transform"] is Dictionary or not command["transform"].has("position_m"):
		return &"invalid_command"
	if not command["transform"]["position_m"] is Vector3:
		return &"invalid_command"
	if command["shape"] == &"swept_segment" and not command["transform"].get("end_position_m") is Vector3:
		return &"invalid_command"
	if command["radius_m"] <= 0.0 or command["radius_m"] > domain.MAX_BRUSH_RADIUS_M:
		return &"invalid_command"
	if command["strength"] < 0.0 or command["strength"] > 1.0:
		return &"invalid_command"
	if command["kind"] in [&"remove_sand", &"place_sand", &"debug_add_sand"]:
		if typeof(command.get("amount_m3", null)) not in [TYPE_FLOAT, TYPE_INT] or command["amount_m3"] <= 0.0:
			return &"invalid_command"
	last_command_id = command["command_id"]
	pending.append(command.duplicate(true))
	pending.sort_custom(_before)
	return StringName()


func apply_due_commands(tick: int) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	while not pending.is_empty() and pending[0]["sim_tick"] <= tick:
		var command: Dictionary = pending.pop_front()
		var snapshot_before := domain.snapshot()
		var result: Dictionary = domain.apply_tool(_normalize(command))
		if result["status"] == &"applied":
			var max_cell_delta_m := 0.0
			var prior_sand: PackedFloat32Array = snapshot_before["sand"]
			for index in result.get("dirty_cells", PackedInt32Array()):
				max_cell_delta_m = maxf(max_cell_delta_m,
					absf(domain.sand[index] - prior_sand[index]))
			result["max_cell_delta_m"] = max_cell_delta_m
		results.append(result)
		if result["status"] == &"applied":
			redo_stack.clear()
			applied_log.append(command.duplicate(true))
			undo_stack.append(snapshot_before)
			if undo_stack.size() > MAX_UNDO:
				undo_stack.pop_front()
	return results


func build_gpu_patch_batch(results: Array[Dictionary]) -> Dictionary:
	## T03: the CPU command queue resolves volume redistribution and ordering.
	## Upload one final value per dirty cell, sorted by cell index, to both GPU
	## ping-pong copies. This shadow is valid until GPU erosion edits sand in T04.
	var touched := {}
	for result in results:
		if result.get("status") != &"applied":
			continue
		for index in result.get("dirty_cells", PackedInt32Array()):
			touched[index] = true
	var indices := PackedInt32Array()
	for index in touched.keys():
		indices.append(index)
	indices.sort()
	var stream := StreamPeerBuffer.new()
	stream.big_endian = false
	for index in indices:
		stream.put_32(index)
		stream.put_float(domain.sand[index])
		stream.put_float(domain.compaction[index])
		stream.put_float(0.0)
	return {"count": indices.size(), "data": stream.data_array,
		"dirty_cells": indices}


func undo_last() -> bool:
	if undo_stack.is_empty() or applied_log.is_empty():
		return false
	var previous: Dictionary = undo_stack.back()
	if previous["sim_tick"] != domain.sim_tick:
		return false
	if not domain.restore(previous):
		return false
	undo_stack.pop_back()
	redo_stack.append(applied_log.pop_back())
	return true


func redo_last() -> bool:
	if redo_stack.is_empty():
		return false
	var command: Dictionary = redo_stack.back()
	if command["sim_tick"] != domain.sim_tick:
		return false
	var previous := domain.snapshot()
	var result: Dictionary = domain.apply_tool(_normalize(command))
	if result["status"] != &"applied":
		return false
	redo_stack.pop_back()
	applied_log.append(command)
	undo_stack.append(previous)
	if undo_stack.size() > MAX_UNDO:
		undo_stack.pop_front()
	return true


func _normalize(command: Dictionary) -> Dictionary:
	return {"command_id": command["command_id"],
		"kind": command["kind"], "shape": command["shape"],
		"position_m": command["transform"]["position_m"],
		"end_position_m": command["transform"].get("end_position_m", command["transform"]["position_m"]),
		"radius_m": command["radius_m"], "strength": command["strength"],
		"amount_m3": command.get("amount_m3", 0.0), "seed": command["seed"]}


func save_replay(path: String) -> Error:
	var commands := []
	for command in applied_log:
		var position: Vector3 = command["transform"]["position_m"]
		var encoded := {
			"sim_tick": command["sim_tick"], "command_id": command["command_id"],
			"kind": String(command["kind"]), "shape": String(command["shape"]),
			"position_m": [position.x, position.y, position.z],
			"radius_m": command["radius_m"], "strength": command["strength"],
			"amount_m3": command.get("amount_m3", 0.0), "seed": command["seed"]
		}
		if command["shape"] == &"swept_segment":
			var end: Vector3 = command["transform"]["end_position_m"]
			encoded["end_position_m"] = [end.x, end.y, end.z]
		commands.append(encoded)
	var document := {"format_version": REPLAY_FORMAT_VERSION,
		"domain_id": String(domain.domain_id), "grid_size": domain.grid_size,
		"cell_size_m": domain.cell_size_m, "commands": commands}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(document, "  ") + "\n")
	file.close()
	return OK


func load_replay(path: String) -> StringName:
	if not pending.is_empty() or not applied_log.is_empty() or last_command_id != 0:
		return &"invalid_command"
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return &"invalid_command"
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary or parsed.get("format_version") != REPLAY_FORMAT_VERSION:
		return &"invalid_command"
	if parsed.get("domain_id") != String(domain.domain_id) or parsed.get("grid_size") != domain.grid_size or not is_equal_approx(parsed.get("cell_size_m", -1.0), domain.cell_size_m):
		return &"out_of_domain"
	if not parsed.get("commands") is Array:
		return &"invalid_command"
	var staging = get_script().new(domain)
	for encoded in parsed["commands"]:
		if not encoded is Dictionary or not encoded.get("position_m") is Array or encoded["position_m"].size() != 3:
			return &"invalid_command"
		var p: Array = encoded["position_m"]
		var transform := {"position_m": Vector3(float(p[0]), float(p[1]), float(p[2]))}
		if encoded.get("shape") == "swept_segment":
			if not encoded.get("end_position_m") is Array or encoded["end_position_m"].size() != 3:
				return &"invalid_command"
			var e: Array = encoded["end_position_m"]
			transform["end_position_m"] = Vector3(float(e[0]), float(e[1]), float(e[2]))
		var command := {"domain_id": domain.domain_id,
			"sim_tick": int(encoded.get("sim_tick", -1)),
			"command_id": int(encoded.get("command_id", -1)),
			"kind": StringName(encoded.get("kind", "")),
			"shape": StringName(encoded.get("shape", "")),
			"transform": transform,
			"radius_m": float(encoded.get("radius_m", -1.0)),
			"strength": float(encoded.get("strength", -1.0)),
			"amount_m3": float(encoded.get("amount_m3", 0.0)),
			"seed": int(encoded.get("seed", 0))}
		var error: StringName = staging.submit(command)
		if not error.is_empty():
			return error
	pending = staging.pending
	last_command_id = staging.last_command_id
	return StringName()


func _before(a: Dictionary, b: Dictionary) -> bool:
	if a["sim_tick"] == b["sim_tick"]:
		return a["command_id"] < b["command_id"]
	return a["sim_tick"] < b["sim_tick"]

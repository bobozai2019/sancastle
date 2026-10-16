extends "res://scripts/sand/tool_command_queue.gd"

const BrushProtocol = preload("res://scripts/simulation/brushes/brush_protocol.gd")
var _sample_stroke := -1
var _sample_generation := -1
var _sample_highwater := -1

func submit(command: Dictionary) -> StringName:
	if not command.has("schema_version"): return super.submit(command)
	var error := BrushProtocol.command_error(command)
	if not error.is_empty(): return error
	if command.domain_id != domain.domain_id: return &"out_of_domain"
	if command.generation != domain.generation: return &"inactive_generation"
	if command.sim_tick < domain.sim_tick: return &"stale_tick"
	if command.command_id <= last_command_id: return &"invalid_command"
	var same_stroke: bool = command.stroke_id == _sample_stroke and command.generation == _sample_generation
	if same_stroke and command.sample_index <= _sample_highwater: return &"invalid_command"
	if not same_stroke:
		for item in pending:
			if item.get("schema_version") == 2 and item.stroke_id != command.stroke_id: return &"backend_unavailable"
	_sample_stroke = command.stroke_id; _sample_generation = command.generation; _sample_highwater = command.sample_index
	last_command_id = command.command_id
	pending.append(command.duplicate(true))
	pending.sort_custom(_before)
	return &""

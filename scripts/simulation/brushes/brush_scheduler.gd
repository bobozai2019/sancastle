extends "res://scripts/simulation/edit_validation/gpu_edit_scheduler.gd"

const BrushProtocol = preload("res://scripts/simulation/brushes/brush_protocol.gd")

func submit(command: Dictionary, policy: int = -1, speed: float = NAN) -> StringName:
	if not command.has("schema_version"): return super.submit(command, policy, speed)
	var error := BrushProtocol.command_error(command)
	if not error.is_empty(): return error
	if not accepting or lab.closed or not lab.ready_for_ticks or generation != lab.generation or not lab.last_error.is_empty(): return &"backend_unavailable"
	if not _external_sand(): return &"invalid_command"
	# Until the real render-thread backend and matching baseline are available,
	# fail admission. A resource/protocol implementation alone cannot edit sand.
	if not ("shape_backend_ready" in lab) or not lab.shape_backend_ready: return &"backend_unavailable"
	if command.baseline_token != lab.shape_baseline_token or command.stroke_id != lab.shape_stroke_id: return &"invalid_baseline"
	if not lab.shape_accepting: return &"backend_unavailable"
	if lab.command_queue.pending.size() >= MAX_PENDING: return &"backend_unavailable"
	if policy >= 0 and policy != command.water_policy: return &"invalid_command"
	if not is_nan(speed) and speed != command.speed_m_s: return &"invalid_command"
	error = lab.command_queue.submit(command)
	if not error.is_empty(): return error
	reservations[command.command_id] = 0.0
	policies[command.command_id] = {"policy": command.water_policy, "speed": command.speed_m_s}
	max_pending = maxi(max_pending, lab.command_queue.pending.size())
	_record(admissions, {"id":command.command_id,"tick":command.sim_tick,"generation":generation,"reserve":0.0,"backend":"brush_v2","at_us":Time.get_ticks_usec()})
	return &""

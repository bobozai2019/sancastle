extends RefCounted

const Spec = preload("res://scripts/sand/brushes/brush_spec.gd")
const SPACING := 0.125
const MAX_POINTS := 256
const MAX_SEGMENT := 2.0
const MAX_PER_FRAME := 8
const MIN_MOVE := 0.000001
const CORNER_COS := 0.9998476951563913 # one degree

var state: StringName = &"idle"
var brush_id: StringName
var stroke_id := 0
var generation := 0
var _params: Dictionary = {}
var params: Dictionary:
	get: return _params.duplicate(true)
var outstanding := 0
var peak_buffer_points := 0
var last_error: StringName
var _segments: Array[Dictionary] = []
var _anchor_valid := false
var _last_hit := Vector2.ZERO
var _last_sample := Vector2.ZERO
var _direction := Vector2.ZERO
var _carry := 0.0
var _subpath := 0
var _sample_index := 0
var _frame := -1
var _submitted_this_frame := 0
var _admitted: Dictionary = {}

func begin_stroke(id: StringName, values: Dictionary, start: Vector2, identity: int, token: int) -> StringName:
	if state not in [&"idle", &"settled"] or outstanding > 0: return &"backend_unavailable"
	var error := Spec.parameter_error(id, values)
	if not error.is_empty(): return error
	if not start.is_finite() or identity <= 0 or token <= 0: return &"invalid_command"
	brush_id = id; _params = values.duplicate(true); stroke_id = identity; generation = token
	_segments.clear(); _sample_index = 0; _subpath = 0; _carry = 0.0; _direction = Vector2.ZERO
	_admitted.clear()
	_last_hit = start; _last_sample = start; _anchor_valid = true
	outstanding = 0; peak_buffer_points = 0; last_error = &""; state = &"capturing"
	_frame = -1; _submitted_this_frame = 0
	if id == &"castle_v1": _emit(start, start)
	return &""

func _emit(start: Vector2, finish: Vector2) -> void:
	_segments.append({"start": start, "end": finish, "subpath": _subpath})
	_last_sample = finish
	peak_buffer_points = maxi(peak_buffer_points, _segments.size())

func append_path_sample(position: Vector2, valid: bool = true) -> StringName:
	if state != &"capturing": return &"backend_unavailable"
	if not valid: interrupt_subpath(); return &"invalid_placement"
	if not position.is_finite(): return &"invalid_command"
	if brush_id == &"castle_v1": return &""
	if not _anchor_valid:
		_last_hit = position; _last_sample = position; _carry = 0.0; _direction = Vector2.ZERO; _anchor_valid = true
		return &""
	var displacement := position - _last_hit
	var distance := displacement.length()
	if distance < MIN_MOVE: return &""
	var direction := displacement / distance
	var corner := _direction.length_squared() > 0.0 and _direction.dot(direction) < CORNER_COS
	var required := int(floor((distance + (0.0 if corner else _carry)) / SPACING)) + (1 if corner and _carry > MIN_MOVE else 0)
	# Reserve the accepted tail so normal release can always flush it.
	if _segments.size() + required + 1 > MAX_POINTS:
		last_error = &"stroke_buffer_full"
		end_stroke(true)
		return last_error
	if corner:
		if _last_sample.distance_to(_last_hit) >= MIN_MOVE: _emit(_last_sample, _last_hit)
		_carry = 0.0
	var cursor := _last_hit
	var remaining := distance
	var next_distance := SPACING - _carry
	while remaining + 1e-10 >= next_distance:
		cursor += direction * next_distance
		_emit(_last_sample, cursor)
		remaining = maxf(0.0, remaining - next_distance)
		_carry = 0.0; next_distance = SPACING
	_carry += remaining
	_last_hit = position; _direction = direction
	return &""

func interrupt_subpath() -> void:
	if brush_id != &"castle_v1" and _anchor_valid and _last_sample.distance_to(_last_hit) >= MIN_MOVE:
		_emit(_last_sample, _last_hit)
	_anchor_valid = false; _carry = 0.0; _direction = Vector2.ZERO; _subpath += 1

func end_stroke(normal: bool = true) -> void:
	if state not in [&"capturing", &"draining"]: return
	# Normal release flushes the tail once. Cancellation also clears queued
	# segments after release/backpressure, while admitted work still settles.
	if state == &"draining" and normal: return
	if normal:
		if brush_id != &"castle_v1": interrupt_subpath()
	else:
		_segments.clear(); _anchor_valid = false; _carry = 0.0
	state = &"draining"
	_finish_if_drained()

func begin_frame(identity: int) -> void:
	if identity != _frame: _frame = identity; _submitted_this_frame = 0

func peek_segment() -> Dictionary:
	if _segments.is_empty() or _submitted_this_frame >= MAX_PER_FRAME: return {}
	var first: Dictionary = _segments[0]
	var start: Vector2 = first.start
	var finish: Vector2 = first.end
	var direction := (finish - start).normalized()
	var count := 1
	if brush_id == &"wall_v1":
		while count < _segments.size():
			var next: Dictionary = _segments[count]
			var next_start: Vector2 = next.start
			var next_finish: Vector2 = next.end
			var next_direction := (next_finish - next_start).normalized()
			if next.subpath != first.subpath or next_start.distance_to(finish) > MIN_MOVE or direction.dot(next_direction) < 1.0 - 1e-10 or start.distance_to(next_finish) > MAX_SEGMENT + 1e-10: break
			finish = next_finish; count += 1
	return {"start_xz_m": start, "end_xz_m": finish, "take_count": count, "sample_index": _sample_index, "subpath": first.subpath}

func acknowledge_admission(segment: Dictionary, command_id: int) -> void:
	# Caller invokes only after the shared queue accepts this exact segment.
	var current := peek_segment()
	if current.is_empty() or current != segment or command_id <= 0 or _admitted.has(command_id): return
	for i in int(segment.take_count): _segments.pop_front()
	_admitted[command_id] = true
	outstanding = _admitted.size(); _sample_index += 1; _submitted_this_frame += 1

func settle_command(command_id: int, token: int) -> void:
	if token != generation or not _admitted.has(command_id): return
	_admitted.erase(command_id)
	outstanding = _admitted.size()
	_finish_if_drained()

func _finish_if_drained() -> void:
	if state == &"draining" and _segments.is_empty() and outstanding == 0: state = &"settled"

func buffer_points() -> int:
	return _segments.size()

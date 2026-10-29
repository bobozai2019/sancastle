extends "res://scripts/visual/test1_beach_edit_worker_entry.gd"

# Diagnostic only. A mutex protects events from render/worker/main threads.
var trace_mutex := Mutex.new()
var trace_events: Array[Dictionary] = []
var trace_output := ""

func _create_solver() -> SandcastleGpuShallowSolver:
	var result := preload("res://tests/edit_validation/baseline_trace_solver.gd").new()
	result.record = event
	result.output = trace_output
	return result

func _render_setup(domain: SandWaterDomain, token: int) -> void:
	# Exact CPU initialization bytes consumed by solver.initialize, before ticks.
	var file := FileAccess.open(trace_output.path_join("initial_domain.bin"), FileAccess.WRITE)
	file.store_var(domain.snapshot(), false)
	event("initial_domain_saved", null, {"tick": domain.sim_tick, "generation": token})
	super._render_setup(domain, token)

func event(stage: String, ids: Variant = null, detail: Variant = null) -> void:
	var row := {"us": Time.get_ticks_usec(), "stage": stage,
		"ids": ids, "detail": detail}
	trace_mutex.lock()
	trace_events.append(row)
	trace_mutex.unlock()

func take_events() -> Array[Dictionary]:
	trace_mutex.lock()
	var rows := trace_events.duplicate(true)
	trace_mutex.unlock()
	return rows

func _request_shadow_sync(reason: String) -> void:
	event("sync_request", null, {"reason": reason, "revision": solver.state_revision})
	super._request_shadow_sync(reason)

func _render_shadow_sync(revision: int, token: int, full: bool) -> void:
	event("sync_render_request", null, {"revision": revision, "generation": token, "full": full})
	super._render_shadow_sync(revision, token, full)

func _on_shadow_field(data: PackedByteArray, field: String, revision: int, token: int) -> void:
	event("sync_callback", null, {"field": field, "bytes": data.size(), "revision": revision})
	super._on_shadow_field(data, field, revision, token)

func _worker_validate_sand(data: PackedByteArray, revision: int, token: int) -> void:
	event("decode_validate_begin", null, revision)
	super._worker_validate_sand(data, revision, token)
	event("decode_validate_end", null, revision)

func _resume_shadow_sync(reason: String) -> void:
	event("shadow_publish", null, {"reason": reason, "revision": shadow_sand_revision})
	super._resume_shadow_sync(reason)

func _on_sand_prefetch(data: PackedByteArray, revision: int, token: int) -> void:
	event("prefetch_callback", null, {"revision": revision, "bytes": data.size()})
	super._on_sand_prefetch(data, revision, token)

func _record_sand_prefetch(data: PackedByteArray, revision: int, token: int) -> void:
	event("prefetch_decode_begin", null, revision)
	super._record_sand_prefetch(data, revision, token)
	event("prefetch_decode_end", null, {"revision": revision, "hits": sand_prefetch_hits})

func _apply_due_tool_commands() -> Dictionary:
	var ids := []
	for command in command_queue.pending:
		if command.sim_tick <= completed_ticks:
			ids.append(command.command_id)
	if not ids.is_empty():
		event("cpu_tool_begin", ids)
	var patch := super._apply_due_tool_commands()
	if not ids.is_empty():
		event("cpu_tool_end", ids, {"cells": patch.count, "chunks": Array(patch.chunks)})
	return patch

func _record_tool_revisions(ids: PackedInt32Array, chunks: PackedInt32Array, revision: int, token: int) -> void:
	if not ids.is_empty():
		event("collision_publish_begin", Array(ids), revision)
	super._record_tool_revisions(ids, chunks, revision, token)
	if not ids.is_empty():
		event("collision_publish_end", Array(ids), revision)

func _tick_finished(substeps: int, source_m3: float, sink_m3: float, token: int) -> void:
	super._tick_finished(substeps, source_m3, sink_m3, token)
	if token == generation and not closing:
		event("tick_completed_callback", null, {"tick": completed_ticks,
			"revision": solver.state_revision, "substeps": substeps})

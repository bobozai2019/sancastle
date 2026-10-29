extends "res://tests/edit_validation/water_transaction_probe.gd"

var raw := PackedByteArray()
var stage := {}
var stage_done := false

func _write(ok: bool, error := "") -> void:
	var f := FileAccess.open(output.path_join("transaction_lock_probe.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify({"pass": ok, "rows": rows, "error": error,
		"scope": "actual GPU pending/unsettled/published phases; backend locks, not input/scheduler acceptance"}, "\t"))

func _raw_ready(data: PackedByteArray) -> void: call_deferred("_record_raw", data)
func _record_raw(data: PackedByteArray) -> void: raw = data

func _attempt_writes(data: PackedByteArray) -> Dictionary:
	var patch := PackedByteArray(); patch.resize(16); patch.fill(0)
	patch.encode_float(4, 0.2)
	var obstacles := PackedFloat32Array(); obstacles.resize(lab.profile.grid_size * lab.profile.grid_size); obstacles.fill(0.0)
	var cfl := PackedFloat32Array(); cfl.resize(lab.profile.grid_size * lab.profile.grid_size / 64); cfl.fill(1.5)
	var rev: int = lab.solver.state_revision
	var index: int = lab.solver.current_index
	var attempts := {"absolute_patch": lab.solver.dispatch_tool_patch(patch, 1),
		"obstacles": lab.solver.update_obstacles(obstacles),
		"tide": lab.solver.dispatch_tide_boundary(0.12), "wave": lab.solver.dispatch_wave_boundary(0.12, 0.01),
		"injection": lab.solver.dispatch_boundary_injection(0.001),
		"substep": lab.solver.dispatch_substep(1.0 / 600.0),
		"cfl_tick": lab.solver.dispatch_tick_with_cfl(1.0 / 30.0, cfl.to_byte_array(), rev),
		"second_edit": lab.solver.dispatch_sand_command(data, _raw_ready)}
	var denied := true
	for value in attempts.values(): denied = denied and not value
	lab.solver.publish_sand()
	return {"attempts": attempts, "all_denied": denied,
		"revision_unchanged": lab.solver.state_revision == rev,
		"index_unchanged": lab.solver.current_index == index}

func _dispatch(data: PackedByteArray) -> void:
	stage = {"dispatch": lab.solver.dispatch_sand_command(data, _raw_ready),
		"receipt_pending": lab.solver.receipt_pending}
	stage.pending = _attempt_writes(data)
	call_deferred("_stage_finished")

func _unsettled(data: PackedByteArray) -> void:
	stage.unsettled = _attempt_writes(data)
	stage.bad_ticket_denied = not lab.solver.authorize_publication(999, lab.solver.state_revision, lab.generation)
	stage.bad_revision_denied = not lab.solver.authorize_publication(1, lab.solver.state_revision + 1, lab.generation)
	stage.bad_generation_denied = not lab.solver.authorize_publication(1, lab.solver.state_revision, lab.generation + 1)
	call_deferred("_stage_finished")

func _publish() -> void:
	stage.authorized = lab.solver.authorize_publication(1, lab.solver.state_revision, lab.generation)
	stage.duplicate_authorization_denied = not lab.solver.authorize_publication(1, lab.solver.state_revision, lab.generation)
	lab._publish_render()
	stage.unlocked = not lab.solver.receipt_pending and not lab.solver.publication_pending
	call_deferred("_stage_finished")

func _stage_finished() -> void: stage_done = true

func _run() -> void:
	for size in [64,256]:
		lab = load("res://tests/edit_validation/edit_gpu_water_" + ("numeric" if size == 64 else "brush") + "_lab.tscn").instantiate()
		root.add_child(lab)
		while not lab.ready_for_ticks and lab.last_error.is_empty(): await process_frame
		var prefix := str(size)
		var before: Dictionary = await _snapshot(prefix + "_before")
		var stock: float = lab.domain.tool_inventory_m3
		var command := _command(1,0.48)
		var data := Protocol.encode(command, 1, lab.solver.state_revision, size, 0.125, 3, stock, 0.5)
		raw.clear(); stage.clear(); stage_done = false
		RenderingServer.call_on_render_thread(_dispatch.bind(data))
		while not stage_done or raw.is_empty(): await process_frame
		_save(prefix + "_receipt.bin",raw)
		var receipt := Protocol.decode_receipt(raw)
		stage_done = false
		RenderingServer.call_on_render_thread(_unsettled.bind(data))
		while not stage_done: await process_frame
		var unpublished: Dictionary = await _snapshot(prefix + "_unsettled")
		var hidden: bool = before.published_sand == unpublished.published_sand and before.published_water == unpublished.published_water
		var unsettled_stock: bool = stock == lab.domain.tool_inventory_m3
		lab.domain.tool_inventory_m3 -= receipt.actual_sand_m3
		stage_done = false
		RenderingServer.call_on_render_thread(_publish)
		while not stage_done: await process_frame
		var published: Dictionary = await _snapshot(prefix + "_published")
		var visible: bool = published.published_sand == published.sand and published.published_water == published.water
		await lab.advance_ticks(3)
		var ok: bool = receipt.get("status") == 1 and stage.dispatch and stage.receipt_pending and stage.pending.all_denied and stage.pending.revision_unchanged and stage.pending.index_unchanged and stage.unsettled.all_denied and stage.unsettled.revision_unchanged and stage.unsettled.index_unchanged and stage.bad_ticket_denied and stage.bad_revision_denied and stage.bad_generation_denied and stage.authorized and stage.duplicate_authorization_denied and stage.unlocked and hidden and unsettled_stock and visible and lab.last_error.is_empty() and lab.completed_ticks == 3
		rows.append({"grid": size,"pass":ok,"stage":stage.duplicate(true),"unsettled_display_hidden":hidden,"stock_unchanged_before_settlement":unsettled_stock,"published_complete":visible,"ticks_after_unlock":lab.completed_ticks})
		_write(false,"running")
		await lab.shutdown();lab.queue_free();await process_frame;lab=null
	var ok := rows.size() == 2
	for row in rows: ok = ok and row.pass
	_write(ok);finished=true;print("TRANSACTION_LOCK_COMPLETE pass=%s rows=%d" % [str(ok),rows.size()]);quit(0 if ok else 1)

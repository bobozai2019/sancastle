extends SceneTree

const FIELDS := ["rock", "sand", "water", "momentum_x", "momentum_z", "sediment",
	"wetness", "compaction", "obstacle", "flux", "published_sand"]
var output := ""
var lab: Node3D
var fields := {}
var late_callbacks := 0
var local_dispatch := false

func _unexpected_late_callback(_data: PackedByteArray) -> void:
	late_callbacks += 1

func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--local-dispatch": local_dispatch = true
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	call_deferred("_run")

func _read() -> void:
	for field in FIELDS:
		if field == "published_sand":
			lab.solver.rd.texture_get_data_async(lab.solver.published_sand, 0, _on_data.bind(field))
		else:
			lab.solver.request_data(field, _on_data.bind(field))

func _on_data(data: PackedByteArray, field: String) -> void:
	call_deferred("_record", data, field)

func _record(data: PackedByteArray, field: String) -> void:
	fields[field] = data

func _snapshot(prefix: String) -> Dictionary:
	fields.clear()
	RenderingServer.call_on_render_thread(_read)
	while fields.size() != FIELDS.size(): await process_frame
	for field in fields:
		var file := FileAccess.open(output.path_join(prefix + "_" + field + ".bin"), FileAccess.WRITE)
		file.store_buffer(fields[field])
	return fields.duplicate(true)

func _inject() -> void:
	lab.solver.inject_receipt_failure_once = true

func _run() -> void:
	if output.is_empty():
		quit(1)
		return
	root.size = Vector2i(960, 540)
	lab = load("res://tests/edit_validation/edit_gpu_receipt_failure.tscn").instantiate()
	lab.local_dispatch = local_dispatch
	root.add_child(lab)
	while not lab.ready_for_ticks and lab.last_error.is_empty(): await process_frame
	var before: Dictionary = await _snapshot("before")
	var revision: int = lab.solver.state_revision
	var stock: float = lab.domain.tool_inventory_m3
	var command := {"domain_id": lab.domain.domain_id, "generation": lab.generation,
		"sim_tick": 0, "command_id": 1, "kind": &"remove_sand", "shape": &"circle",
		"transform": {"position_m": Vector3.ZERO}, "radius_m": 0.75,
		"strength": 1.0, "amount_m3": 0.02, "seed": 101}
	RenderingServer.call_on_render_thread(_inject)
	await lab.apply_gpu_command(command)
	var after: Dictionary = await _snapshot("after")
	var same := true
	for field in FIELDS: same = same and before[field] == after[field]
	command.command_id = 2
	var blocked: Dictionary = await lab.apply_gpu_command(command)
	var ok: bool = (same and lab.last_error == "GPU command dispatch failed" and not lab.ready_for_ticks and
		lab.solver.state_revision == revision and lab.domain.tool_inventory_m3 == stock and
		lab.reserved_m3 == 0.0 and blocked.get("error") == "backend_unavailable")
	var file := FileAccess.open(output.path_join("receipt_failure_probe.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass": ok, "authority_and_display_unchanged": same,
		"revision_unchanged": lab.solver.state_revision == revision, "stock_unchanged": lab.domain.tool_inventory_m3 == stock,
		"reservation_released": lab.reserved_m3 == 0.0, "quarantined": not lab.ready_for_ticks,
		"next_command": blocked, "injection": "after GPU conditional commit, before issuing receipt readback"}, "\t"))
	var released_backend = lab.solver
	await lab.shutdown()
	var late_data := PackedByteArray()
	late_data.resize(128)
	late_data.fill(0)
	released_backend._receipt_ready(late_data, _unexpected_late_callback, released_backend.active_ticket, 1, revision)
	var late_ok: bool = late_callbacks == 0
	file = FileAccess.open(output.path_join("late_callback_probe.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass": late_ok, "callbacks": late_callbacks,
		"scope": "synthetic receipt callback after backend.release; not live pending-exit coverage"}, "\t"))
	ok = ok and late_ok
	lab.queue_free()
	await process_frame
	print("RECEIPT_FAILURE_COMPLETE pass=" + str(ok))
	quit(0 if ok else 1)

extends SceneTree

const Protocol = preload("res://scripts/simulation/edit_validation/edit_protocol.gd")
const Domain = preload("res://scripts/simulation/sand_water_domain.gd")
const Queue = preload("res://scripts/sand/tool_command_queue.gd")
var output := ""
var lab: Node3D
var rows := []
var started := 0
var finished := false

func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			output = arg.trim_prefix("--output=")
	started = Time.get_ticks_msec()
	call_deferred("_watchdog")
	call_deferred("_run")

func _watchdog() -> void:
	while not finished:
		if Time.get_ticks_msec() - started > 120000:
			printerr("GPU_BRUSH_TIMEOUT")
			quit(1)
			return
		await process_frame

func _save(prefix: String, fields: Dictionary) -> void:
	for field in fields:
		var file := FileAccess.open(output.path_join(prefix + "_" + field + ".bin"), FileAccess.WRITE)
		file.store_buffer(fields[field])

func _run() -> void:
	if output.is_empty():
		quit(1)
		return
	root.size = Vector2i(960, 540)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	lab = load("res://tests/edit_validation/edit_gpu_brush_lab.tscn").instantiate()
	root.add_child(lab)
	while not lab.ready_for_ticks and lab.last_error.is_empty():
		await process_frame
	if not lab.last_error.is_empty():
		printerr(lab.last_error)
		quit(1)
		return
	var reference := Domain.new(256, 0.125)
	reference.restore(lab.domain.snapshot())
	# restore advances ephemeral generation; bind reference commands to this lab.
	reference.generation = lab.generation
	var queue := Queue.new(reference)
	var before: Dictionary = await lab.snapshot_state()
	_save("initial", before)
	var inputs := [
		{"kind": &"remove_sand", "amount": 0.01, "strength": 1.0, "shape": &"circle"},
		{"kind": &"place_sand", "amount": 0.01, "strength": 1.0, "shape": &"circle"},
		{"kind": &"remove_sand", "amount": 0.01, "strength": 0.0, "shape": &"circle"},
		{"kind": &"remove_sand", "amount": 0.015, "strength": 0.5, "shape": &"swept_segment"},
		{"kind": &"place_sand", "amount": 10.0, "strength": 1.0, "shape": &"circle"}]
	for index in inputs.size():
		var input: Dictionary = inputs[index]
		var command := {"domain_id": lab.domain.domain_id, "generation": lab.generation,
			"sim_tick": 0, "command_id": index + 1, "kind": input.kind, "shape": input.shape,
			"transform": {"position_m": Vector3(0.25, 0.0, -0.5)},
			"radius_m": 0.75, "strength": input.strength, "amount_m3": input.amount, "seed": 101}
		if input.shape == &"swept_segment":
			command.transform.end_position_m = Vector3(2.0, 0.0, 0.5)
		var cpu_admission: StringName = queue.submit(command)
		var cpu_results: Array[Dictionary] = queue.apply_due_commands(0)
		if not cpu_admission.is_empty() or cpu_results.is_empty():
			rows.append({"pass": false, "error": "CPU reference admission: " + String(cpu_admission)})
			break
		var command_file := FileAccess.open(output.path_join("command_%02d_wire.bin" % index), FileAccess.WRITE)
		command_file.store_buffer(Protocol.encode(command, lab.ticket_id + 1, lab.solver.state_revision, 256, 0.125, 0, lab.domain.tool_inventory_m3))
		command_file = FileAccess.open(output.path_join("command_%02d_cpu_sand.bin" % index), FileAccess.WRITE)
		command_file.store_buffer(reference.sand.to_byte_array())
		var gpu: Dictionary = await lab.apply_gpu_command(command)
		if not lab.last_error.is_empty():
			printerr(lab.last_error)
			break
		var after: Dictionary = await lab.snapshot_state()
		_save("command_%02d" % index, after)
		var file := FileAccess.open(output.path_join("receipt_%02d.bin" % index), FileAccess.WRITE)
		file.store_buffer(lab.raw_receipt)
		var sand: PackedFloat32Array = after.sand.to_float32_array()
		var old_sand: PackedFloat32Array = before.sand.to_float32_array()
		var max_difference := 0.0
		var within_budget := true
		var actual := 0.0
		for i in sand.size():
			var difference := absf(sand[i] - reference.sand[i])
			max_difference = maxf(max_difference, difference)
			within_budget = within_budget and difference <= Protocol.cell_budget(old_sand[i], reference.sand[i]) and sand[i] >= 0.0 and is_finite(sand[i])
			actual += (sand[i] - old_sand[i]) * 0.015625
		var immutable := true
		for field in before:
			if field != "sand":
				immutable = immutable and before[field] == after[field]
		var budget := Protocol.volume_budget(old_sand, sand, 0.015625)
		var status_matches: bool = (gpu.get("status", -1) == 1) == (cpu_results[0].status == &"applied")
		var receipt_closure: bool = absf(absf(actual) - float(gpu.get("actual_sand_m3", 0.0))) <= budget.reduction_m3
		var inventory_difference: float = absf(lab.domain.tool_inventory_m3 - reference.tool_inventory_m3)
		var settled_inventory: float = lab.domain.tool_inventory_m3
		lab._settle_receipt(lab.raw_receipt, lab.generation)
		var duplicate_ignored: bool = lab.domain.tool_inventory_m3 == settled_inventory
		var publish_order: bool = gpu.get("status", -1) != 1 or lab.publish_us >= lab.settle_us
		var pass_row: bool = cpu_admission.is_empty() and status_matches and within_budget and immutable and receipt_closure and inventory_difference <= budget.edit_m3 * (index + 1) and duplicate_ignored and publish_order
		rows.append({"command": command, "gpu": gpu, "cpu": cpu_results[0], "pass": pass_row,
			"max_sand_difference_m": max_difference, "legacy_fields_immutable": immutable,
			"actual_field_delta_m3": actual, "receipt_closure": receipt_closure,
			"inventory_difference_m3": inventory_difference, "budget": budget,
			"duplicate_receipt_ignored": duplicate_ignored, "settle_us": lab.settle_us,
			"publish_render_us": lab.publish_us, "settle_before_publish": publish_order,
			"readback_hotpath_bytes": lab.raw_receipt.size()})
		before = after
	var ok: bool = rows.size() == inputs.size() and lab.last_error.is_empty()
	for row in rows:
		ok = ok and row.pass
	var file := FileAccess.open(output.path_join("gpu_brush_probe.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass": ok, "rows": rows, "purpose": "first full-domain GPU brush smoke, not G2 complete or cost acceptance",
		"error": lab.last_error, "effective_profile": lab.effective_profile,
		"shader_metadata": lab.shader_metadata, "ignored_receipts": lab.ignored_receipts}, "\t"))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("after.png"))
	await lab.shutdown()
	lab.queue_free()
	await process_frame
	finished = true
	print("GPU_BRUSH_COMPLETE pass=" + str(ok))
	quit(0 if ok else 1)

extends SceneTree

var source: Node3D
var reference: Node3D
var bytes := PackedByteArray()
var started_ms := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	started_ms = Time.get_ticks_msec()
	var scene: PackedScene = load("res://scenes/gpu_water_preview.tscn")
	if scene == null:
		_fail("checkpoint scene unavailable")
		return
	source = scene.instantiate()
	source.checkpoint_interval_ticks = 5
	root.add_child(source)
	while not source.checkpoint_capture_pending:
		if not source.last_error.is_empty() or Time.get_ticks_msec() - started_ms > 10000:
			_fail("checkpoint capture did not start: " + source.last_error)
			return
		await process_frame
	source.playing = false
	var edit_error: StringName = source._submit_brush(&"remove_sand", 0.02,
		Vector3.ZERO, Vector3.ZERO, &"circle")
	if not edit_error.is_empty() or source.command_queue.applied_log.size() != 1:
		_fail("edit was not applied while checkpoint readback was pending")
		return
	while source.checkpoints.is_empty():
		if not source.last_error.is_empty() or Time.get_ticks_msec() - started_ms > 10000:
			_fail("checkpoint capture stalled: " + source.last_error)
			return
		await process_frame
	var checkpoint: Dictionary = source.checkpoints[0]
	if checkpoint.tick != 5 or checkpoint.fields.size() != 3 or \
			checkpoint.shadow["sim_tick"] != 5 or \
			checkpoint.shadow["water"] != checkpoint.fields["water"] or \
			checkpoint.command_ids.size() != 0:
		_fail("checkpoint tick or CPU/GPU fields invalid")
		return
	while source.command_queue.pending.size() > 0 or source.tick_pending:
		if not source.last_error.is_empty() or Time.get_ticks_msec() - started_ms > 15000:
			_fail("queued edit did not resume: " + source.last_error)
			return
		await process_frame
	if source.command_queue.applied_log.size() != 1 or \
			source.shadow_domain.sand == checkpoint.shadow["sand"]:
		_fail("queued edit was not applied after checkpoint")
		return
	source.playing = true
	reference = scene.instantiate()
	reference.replay_target_tick = 5
	reference.visible = false
	reference.set_process_unhandled_input(false)
	root.add_child(reference)
	reference.get_node("GpuOverviewCamera").current = false
	source.get_node("GpuOverviewCamera").current = true
	while not reference.replay_ready:
		if not reference.last_error.is_empty() or Time.get_ticks_msec() - started_ms > 15000:
			_fail("checkpoint reference stalled: " + reference.last_error)
			return
		await process_frame
	var maximum := 0.0
	for field in ["water", "momentum_x", "momentum_z"]:
		bytes = PackedByteArray()
		RenderingServer.call_on_render_thread(_read_field.bind(field))
		while bytes.is_empty():
			if Time.get_ticks_msec() - started_ms > 20000:
				_fail("checkpoint reference readback stalled")
				return
			await process_frame
		var actual := bytes.to_float32_array()
		var expected: PackedFloat32Array = checkpoint.fields[field]
		if actual.size() != expected.size():
			_fail("checkpoint field size mismatch: " + field)
			return
		for i in actual.size():
			maximum = maxf(maximum, absf(actual[i] - expected[i]))
	if maximum > 0.000001 or source.completed_ticks <= 5:
		_fail("checkpoint mismatch or source did not resume: %.8f" % maximum)
		return
	print("PASS: GPU checkpoint tick=5 exact water+momentum readback, CPU shadow aligned, overlapping edit applied; max_error=%.8f" % maximum)
	source.queue_free()
	reference.queue_free()
	quit(0)


func _read_field(field: String) -> void:
	var error: Error = reference.solver.request_data(field, _on_data)
	if error != OK:
		call_deferred("_fail", "checkpoint reference readback error: %d" % error)


func _on_data(data: PackedByteArray) -> void:
	call_deferred("_record_data", data)


func _record_data(data: PackedByteArray) -> void:
	bytes = data


func _fail(message: String) -> void:
	printerr("FAIL: " + message)
	if source != null:
		source.queue_free()
	if reference != null:
		reference.queue_free()
	quit(1)

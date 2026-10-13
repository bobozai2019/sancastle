extends SceneTree

const SCENE := preload("res://scenes/components/water_visual/reference_coupled.tscn")
const FIELD_SIZES := {
	"rock": 256 * 256 * 4,
	"sand": 256 * 256 * 4,
	"water": 256 * 256 * 4,
	"momentum_x": 256 * 256 * 4,
	"momentum_z": 256 * 256 * 4,
	"sediment": 256 * 256 * 4,
	"wetness": 256 * 256 * 2,
	"compaction": 256 * 256 * 2,
	"obstacle": 256 * 256,
	"flux": 256 * 256 * 16,
	"foam_history": 256 * 256 * 8,
}

var output_dir := ""
var run_id := ""
var target_tick := 90
var worker_handoff := false
var ledger_ring := false
var ledger_batch_ticks := 0
var batch_bookkeeping := false
var auto_checkpoint_tick := 0
var fixed_substeps := 0
var fixed_cfl_audit := false
var save_fields: Array[String] = []
var readbacks := {}


func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			output_dir = arg.trim_prefix("--output=")
		elif arg.begins_with("--run-id="):
			run_id = arg.trim_prefix("--run-id=")
		elif arg.begins_with("--tick="):
			target_tick = int(arg.trim_prefix("--tick="))
		elif arg == "--worker-handoff":
			worker_handoff = true
		elif arg == "--ledger-ring":
			ledger_ring = true
		elif arg.begins_with("--ledger-batch="):
			ledger_batch_ticks = int(arg.trim_prefix("--ledger-batch="))
		elif arg == "--batch-bookkeeping":
			batch_bookkeeping = true
		elif arg.begins_with("--auto-checkpoint="):
			auto_checkpoint_tick = int(arg.trim_prefix("--auto-checkpoint="))
		elif arg.begins_with("--fixed-substeps="):
			fixed_substeps = int(arg.trim_prefix("--fixed-substeps="))
		elif arg == "--fixed-cfl-audit":
			fixed_cfl_audit = true
		elif arg.begins_with("--save-fields="):
			for name in arg.trim_prefix("--save-fields=").split(","):
				save_fields.append(name)
	call_deferred("_run")


func _run() -> void:
	if output_dir.is_empty() or run_id.is_empty() or target_tick < 8 or \
			ledger_batch_ticks < 0 or (ledger_batch_ticks > 0 and ledger_ring) or \
			(batch_bookkeeping and ledger_batch_ticks < 1) or \
			(auto_checkpoint_tick > 0 and not batch_bookkeeping) or \
			(fixed_substeps > 0 and not batch_bookkeeping) or \
			(fixed_cfl_audit and fixed_substeps < 1) or \
			fixed_substeps < 0 or fixed_substeps > 64 or \
			not DirAccess.dir_exists_absolute(output_dir):
		_fail("invalid arguments")
		return
	var preview: Node3D = SCENE.instantiate()
	preview.prototype_worker_handoff = worker_handoff
	preview.prototype_ledger_ring_capacity = target_tick if ledger_ring else 0
	preview.prototype_ledger_batch_ticks = ledger_batch_ticks
	preview.prototype_batched_ledger_bookkeeping = batch_bookkeeping
	preview.checkpoint_interval_ticks = auto_checkpoint_tick
	preview.prototype_fixed_substeps = fixed_substeps
	preview.prototype_fixed_cfl_audit = fixed_cfl_audit
	root.add_child(preview)
	var start_us := Time.get_ticks_usec()
	while not preview.ready_for_ticks and preview.last_error.is_empty() and \
			Time.get_ticks_usec() - start_us < 30000000:
		await process_frame
	if not preview.ready_for_ticks or not preview.last_error.is_empty():
		_fail("initialization: " + preview.last_error)
		return
	var request := {"domain_id": preview.shadow_domain.domain_id,
		"generation": preview.generation, "request_id": 1,
		"start_tick": 8, "profile_id": &"test_packet",
		"amplitude_m": 0.18, "duration_s": 6.0, "seed": 31}
	var admitted: Dictionary = preview.request_wave(request)
	if not admitted.ok:
		_fail("wave rejected: " + String(admitted.code))
		return
	start_us = Time.get_ticks_usec()
	while preview.completed_ticks < target_tick - 1 and \
			preview.last_error.is_empty() and Time.get_ticks_usec() - start_us < 30000000:
		await process_frame
	preview.playing = false
	while preview.tick_pending and Time.get_ticks_usec() - start_us < 30000000:
		await process_frame
	while preview.completed_ticks < target_tick and preview.last_error.is_empty() and \
			Time.get_ticks_usec() - start_us < 30000000:
		if not preview.tick_pending and not preview.checkpoint_capture_pending:
			preview._start_tick()
		await process_frame
	if preview.completed_ticks != target_tick or preview.tick_pending or \
			not preview.last_error.is_empty():
		_fail("exact tick unavailable: %d / %d, %s" % [
			preview.completed_ticks, target_tick, preview.last_error])
		return
	if auto_checkpoint_tick > 0:
		start_us = Time.get_ticks_usec()
		while preview.checkpoint_capture_pending and \
				preview.last_error.is_empty() and \
				Time.get_ticks_usec() - start_us < 15000000:
			await process_frame
		if preview.checkpoint_capture_pending or preview.checkpoints.is_empty() or \
				preview.checkpoints.back().tick != auto_checkpoint_tick:
			_fail("auto checkpoint unavailable")
			return
	var revision: int = preview.solver.state_revision
	if ledger_batch_ticks > 0:
		RenderingServer.call_on_render_thread(_flush_batches.bind(preview))
	RenderingServer.call_on_render_thread(_request_fields.bind(preview))
	start_us = Time.get_ticks_usec()
	var expected_batches := ceili(float(target_tick) / float(ledger_batch_ticks)) if \
		ledger_batch_ticks > 0 else 0
	while (readbacks.size() < FIELD_SIZES.size() + (1 if ledger_ring else 0) or \
			preview.tide_ledger_batch_results.size() < expected_batches or \
			(batch_bookkeeping and preview.tide_ledger_settled_ticks < target_tick) or \
			(fixed_cfl_audit and preview.fixed_cfl_audit_count < target_tick)) and \
			preview.last_error.is_empty() and \
			Time.get_ticks_usec() - start_us < 15000000:
		await process_frame
	if readbacks.size() != FIELD_SIZES.size() + (1 if ledger_ring else 0) or \
			preview.tide_ledger_batch_results.size() != expected_batches or \
			(batch_bookkeeping and preview.tide_ledger_settled_ticks != target_tick) or \
			(fixed_cfl_audit and preview.fixed_cfl_audit_count != target_tick) or \
			not preview.last_error.is_empty() or \
			preview.solver.state_revision != revision:
		_fail("readback incomplete or revision changed: %d fields" % readbacks.size())
		return
	var hashes := {}
	for field in FIELD_SIZES:
		var data: PackedByteArray = readbacks[field]
		if data.size() != FIELD_SIZES[field]:
			_fail("wrong byte length for %s: %d" % [field, data.size()])
			return
		var hash := HashingContext.new()
		if hash.start(HashingContext.HASH_SHA256) != OK or hash.update(data) != OK:
			_fail("hash failed: " + field)
			return
		hashes[field] = hash.finish().hex_encode()
	for field in save_fields:
		if not FIELD_SIZES.has(field):
			_fail("unknown save field: " + field)
			return
		var field_path := output_dir.path_join("%s_%s.bin" % [run_id, field])
		var field_file := FileAccess.open(field_path, FileAccess.WRITE)
		if field_file == null:
			_fail("save field open failed: " + field)
			return
		field_file.store_buffer(readbacks[field])
		field_file.close()
	var ring_result := {}
	if ledger_ring:
		var ring_bytes: PackedByteArray = readbacks["ledger_ring"]
		if ring_bytes.size() != target_tick * 256 * 4 or \
				preview.tide_ledger_ring.captured != target_tick:
			_fail("ledger ring incomplete: %d bytes" % ring_bytes.size())
			return
		var ring_source := 0.0
		var ring_sink := 0.0
		var ring_values := ring_bytes.to_float32_array()
		var cpu_pairs: Array = preview.tide_ledger_cpu_pairs
		if cpu_pairs.size() != target_tick:
			_fail("CPU ledger pair count mismatch: %d" % cpu_pairs.size())
			return
		var max_tick_source_error := 0.0
		var max_tick_sink_error := 0.0
		for tick_index in target_tick:
			var tick_source := 0.0
			var tick_sink := 0.0
			for z in 256:
				var delta_m3: float = ring_values[tick_index * 256 + z]
				if not is_finite(delta_m3):
					_fail("ledger ring nonfinite delta")
					return
				if delta_m3 >= 0.0:
					tick_source += delta_m3
				else:
					tick_sink -= delta_m3
			var source_error := absf(tick_source - cpu_pairs[tick_index].source_m3)
			var sink_error := absf(tick_sink - cpu_pairs[tick_index].sink_m3)
			max_tick_source_error = maxf(max_tick_source_error, source_error)
			max_tick_sink_error = maxf(max_tick_sink_error, sink_error)
			if source_error > 0.00000001 or sink_error > 0.00000001:
				_fail("ledger ring tick %d differs" % (tick_index + 1))
				return
			ring_source += tick_source
			ring_sink += tick_sink
		ring_result = {"bytes": ring_bytes.size(),
			"captured_ticks": preview.tide_ledger_ring.captured,
			"water_source_m3": ring_source, "water_sink_m3": ring_sink,
			"max_tick_source_error_m3": max_tick_source_error,
			"max_tick_sink_error_m3": max_tick_sink_error,
			"source_error_m3": ring_source - preview.solver.water_source_m3,
			"sink_error_m3": ring_sink - preview.solver.water_sink_m3}
		if absf(ring_result.source_error_m3) > 0.000001 or \
				absf(ring_result.sink_error_m3) > 0.000001:
			_fail("ledger ring differs from per-tick ledger")
			return
	var batch_result := {}
	if ledger_batch_ticks > 0:
		var cpu_pairs: Array = preview.tide_ledger_cpu_pairs
		if (not batch_bookkeeping and cpu_pairs.size() != target_tick) or \
				preview.tide_ledger_batches.total_captured != target_tick:
			_fail("batch capture count mismatch")
			return
		var tick_cursor := 0
		var batch_source := 0.0
		var batch_sink := 0.0
		var max_source_error := 0.0
		var max_sink_error := 0.0
		for index in expected_batches:
			var batch: Dictionary = preview.tide_ledger_batch_results[index]
			var expected_count := mini(ledger_batch_ticks, target_tick - tick_cursor)
			var bytes: PackedByteArray = batch.data
			if batch.index != index or batch.count != expected_count or \
					bytes.size() != ledger_batch_ticks * 256 * 4:
				_fail("batch order/count/size mismatch at %d" % index)
				return
			var values := bytes.to_float32_array()
			for local_tick in expected_count:
				var tick_source := 0.0
				var tick_sink := 0.0
				for z in 256:
					var delta_m3: float = values[local_tick * 256 + z]
					if not is_finite(delta_m3):
						_fail("batch nonfinite delta")
						return
					if delta_m3 >= 0.0:
						tick_source += delta_m3
					else:
						tick_sink -= delta_m3
				var source_error := 0.0 if batch_bookkeeping else \
					absf(tick_source - cpu_pairs[tick_cursor].source_m3)
				var sink_error := 0.0 if batch_bookkeeping else \
					absf(tick_sink - cpu_pairs[tick_cursor].sink_m3)
				max_source_error = maxf(max_source_error, source_error)
				max_sink_error = maxf(max_sink_error, sink_error)
				if source_error > 0.00000001 or sink_error > 0.00000001:
					_fail("batch tick %d differs" % (tick_cursor + 1))
					return
				batch_source += tick_source
				batch_sink += tick_sink
				tick_cursor += 1
		if tick_cursor != target_tick or \
				absf(batch_source - preview.solver.water_source_m3) > 0.000001 or \
				absf(batch_sink - preview.solver.water_sink_m3) > 0.000001:
			_fail("batch total differs")
			return
		batch_result = {"batch_ticks": ledger_batch_ticks,
			"batch_bookkeeping": batch_bookkeeping,
			"batch_count": expected_batches, "captured_ticks": tick_cursor,
			"buffer_bytes": 2 * ledger_batch_ticks * 256 * 4,
			"water_source_m3": batch_source, "water_sink_m3": batch_sink,
			"max_tick_source_error_m3": max_source_error,
			"max_tick_sink_error_m3": max_sink_error}
	var result := {"role": "w07_worker_handoff_state_probe",
		"run_id": run_id, "worker_handoff": worker_handoff,
		"ledger_ring": ring_result, "ledger_batches": batch_result,
		"fixed_substeps": fixed_substeps,
		"fixed_cfl_audit": {"count": preview.fixed_cfl_audit_count,
			"max_required_substeps": preview.fixed_cfl_max_required,
			"over_bound_ticks": preview.fixed_cfl_over_bound} if \
			fixed_cfl_audit else {},
		"auto_checkpoint": {"tick": preview.checkpoints.back().tick,
			"water_source_m3": preview.checkpoints.back().water_source_m3,
			"water_sink_m3": preview.checkpoints.back().water_sink_m3} if \
			auto_checkpoint_tick > 0 else {},
		"fixture_id": String(preview.fixture_id),
		"tick": preview.completed_ticks, "generation": preview.generation,
		"revision": revision, "wave_request": request,
		"field_sizes": FIELD_SIZES, "field_sha256": hashes,
		"water_source_m3": preview.solver.water_source_m3,
		"water_sink_m3": preview.solver.water_sink_m3,
		"sand_closure_m3": preview.audit_sand_closure_m3,
		"overload_events": preview.solver.overload_events,
		"nan_events": preview.solver.nan_events,
		"rendering_driver": RenderingServer.get_current_rendering_driver_name(),
		"adapter": RenderingServer.get_video_adapter_name(),
		"viewport_px": [root.size.x, root.size.y]}
	var path := output_dir.path_join("%s_state.json" % run_id)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_fail("manifest open")
		return
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	print("PASS: worker state tick=%d fields=%d" % [target_tick, hashes.size()])
	quit(0)


func _request_fields(preview: Node3D) -> void:
	if ledger_ring:
		var ring_error: Error = preview.tide_ledger_ring.request_data(
			_on_readback.bind("ledger_ring"))
		if ring_error != OK:
			call_deferred("_fail", "ledger ring readback request: %d" % ring_error)
			return
	for field in FIELD_SIZES:
		var error: Error
		if field == "foam_history":
			error = preview.foam_field.request_data(_on_readback.bind(field))
		else:
			error = preview.solver.request_data(field, _on_readback.bind(field))
		if error != OK:
			call_deferred("_fail", "readback request %s: %d" % [field, error])


func _flush_batches(preview: Node3D) -> void:
	if not preview.tide_ledger_batches.flush():
		call_deferred("_fail", "final tide ledger batch flush failed")


func _on_readback(data: PackedByteArray, field: String) -> void:
	call_deferred("_receive_readback", data, field)


func _receive_readback(data: PackedByteArray, field: String) -> void:
	readbacks[field] = data


func _fail(message: String) -> void:
	printerr("FAIL: worker state " + message)
	quit(1)

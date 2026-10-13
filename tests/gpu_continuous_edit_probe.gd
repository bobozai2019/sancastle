extends SceneTree

const EDIT_POINT := Vector3(-14.0, 0.0, 2.0)
const CHUNK_ID := 32
var preview: Node3D
var duration_seconds := 60
var coupled := false
var csv_path := ""
var started_usec := 0
var last_edit_usec := 0
var last_sample_second := -1
var finished := false
var submitted := 0
var completed := 0
var pending_records: Array[Dictionary] = []
var latencies_ms := PackedFloat32Array()
var latency_rows := PackedStringArray(["command_id,latency_ms,source,pre_apply_ms,apply_to_collision_ms,queue_ms,readback_ms,apply_wait_ms"])
var maximum_height_error_m := 0.0
var maximum_ray_error_m := 0.0
var maximum_pending := 0
var warm_static := -1
var warm_video := -1
var steady_static := -1
var steady_video := -1
var rows := PackedStringArray(["elapsed_s,ticks,submitted,completed,pending,max_latency_ms,max_cell_edit_height_m,max_collision_sample_error_m,max_ray_center_error_m,static_bytes,video_bytes,checkpoint_count,collision_batches,invalid_readbacks"])
var sand_readback := PackedByteArray()


func _init() -> void:
	call_deferred("_begin")


func _begin() -> void:
	var requested := int(OS.get_environment("SANDCASTLE_CONTINUOUS_SECONDS"))
	if requested > 0:
		duration_seconds = requested
	var checkpoint_interval := int(OS.get_environment("SANDCASTLE_CHECKPOINT_INTERVAL"))
	coupled = OS.get_environment("SANDCASTLE_COUPLED_EDIT") == "1"
	var run_tag := OS.get_environment("SANDCASTLE_CONTINUOUS_RUN_TAG")
	if not run_tag.is_empty() and not run_tag.is_valid_identifier():
		_fail("continuous edit run tag invalid")
		return
	csv_path = "res://test_output/sandcastle_water_sand_coupling/验收/%s_gpu_continuous_edit_%d%s%s.csv" % [
		"T04" if coupled else "T03", duration_seconds,
		"_checkpoint" if checkpoint_interval > 0 else "",
		"_" + run_tag if not run_tag.is_empty() else ""]
	var scene: PackedScene = load("res://scenes/gpu_water_preview.tscn")
	if scene == null:
		_fail("continuous edit scene missing")
		return
	preview = scene.instantiate()
	preview.enable_erosion = coupled
	preview.checkpoint_interval_ticks = checkpoint_interval
	root.add_child(preview)
	call_deferred("_wait_ready")


func _wait_ready() -> void:
	if finished:
		return
	if not preview.last_error.is_empty():
		_fail(preview.last_error)
		return
	if not preview.ready_for_ticks or preview.collision_proxy.shapes.size() < 64:
		await process_frame
		call_deferred("_wait_ready")
		return
	preview.collision_proxy.profile_latency_details = true
	preview.profile_tool_latency = true
	started_usec = Time.get_ticks_usec()
	last_edit_usec = started_usec - 34000
	call_deferred("_monitor")


func _monitor() -> void:
	if finished:
		return
	if not preview.last_error.is_empty() or preview.collision_proxy.invalid_readbacks > 0:
		_fail("continuous edit preview/collision error: %s invalid=%d" % [
			preview.last_error, preview.collision_proxy.invalid_readbacks])
		return
	var now := Time.get_ticks_usec()
	var elapsed_seconds := float(now - started_usec) / 1000000.0
	if elapsed_seconds < float(duration_seconds) and now - last_edit_usec >= 33000 and \
			preview.command_queue.pending.size() < 8:
		var kind: StringName = &"remove_sand" if submitted % 2 == 0 else &"place_sand"
		var error: StringName = preview._submit_brush(kind, 0.002,
			EDIT_POINT, EDIT_POINT, &"circle")
		if not error.is_empty():
			_fail("continuous edit submit %d rejected: %s" % [submitted, error])
			return
		pending_records.append({"id": preview.command_id, "submitted_usec": now})
		submitted += 1
		last_edit_usec = now
	maximum_pending = maxi(maximum_pending, pending_records.size())
	_poll_completed()
	if not coupled:
		_sample_collision_map()
	var second := int(elapsed_seconds)
	if second > last_sample_second:
		await physics_frame
		if not coupled:
			_sample_ray_height()
		var static_bytes := int(Performance.get_monitor(Performance.MEMORY_STATIC))
		var video_bytes := int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED))
		if warm_static < 0 and submitted >= 100:
			warm_static = static_bytes
			warm_video = video_bytes
		if steady_static < 0 and second >= 30 and preview.checkpoints.size() == 8:
			steady_static = static_bytes
			steady_video = video_bytes
		rows.append("%d,%d,%d,%d,%d,%.3f,%.6f,%.6f,%.6f,%d,%d,%d,%d,%d" % [
			second, preview.completed_ticks, submitted, completed,
			pending_records.size(), _maximum_latency(),
			preview.max_cell_edit_height_m, maximum_height_error_m,
			maximum_ray_error_m,
			static_bytes, video_bytes, preview.checkpoints.size(),
			preview.collision_proxy.completed_batches,
			preview.collision_proxy.invalid_readbacks])
		last_sample_second = second
	if elapsed_seconds >= float(duration_seconds):
		call_deferred("_settle")
		return
	await process_frame
	call_deferred("_monitor")


func _poll_completed() -> void:
	while not pending_records.is_empty():
		var record: Dictionary = pending_records[0]
		var id: int = record.id
		if not preview.tool_revision_by_command_id.has(id):
			break
		var revision: int = preview.tool_revision_by_command_id[id]
		if int(preview.collision_proxy.applied_revisions.get(CHUNK_ID, -1)) < revision:
			break
		var applied_usec: int = preview.collision_proxy.applied_usec[CHUNK_ID]
		var latency_ms := float(applied_usec - int(record.submitted_usec)) / 1000.0
		if latency_ms < 0.0:
			_fail("continuous edit collision timestamp reversed")
			return
		latencies_ms.append(latency_ms)
		var stage: PackedInt64Array = preview.collision_proxy.applied_stage_usec.get(
			CHUNK_ID, PackedInt64Array())
		var tool_apply_usec: int = int(preview.tool_apply_usec_by_command_id.get(id, -1))
		if stage.size() == 4 and tool_apply_usec >= 0:
			latency_rows.append("%d,%.6f,gpu_readback,%.6f,%.6f,%.6f,%.6f,%.6f" % [
				id, latency_ms,
				float(tool_apply_usec - int(record.submitted_usec)) / 1000.0,
				float(stage[0] - tool_apply_usec) / 1000.0,
				float(stage[1] - stage[0]) / 1000.0,
				float(stage[2] - stage[1]) / 1000.0,
				float(stage[3] - stage[2]) / 1000.0])
		elif tool_apply_usec >= 0:
			latency_rows.append("%d,%.6f,cpu_shadow,%.6f,%.6f,,," % [
				id, latency_ms,
				float(tool_apply_usec - int(record.submitted_usec)) / 1000.0,
				float(applied_usec - tool_apply_usec) / 1000.0])
		else:
			latency_rows.append("%d,%.6f,unknown,,,,," % [id, latency_ms])
		completed += 1
		pending_records.pop_front()


func _sample_collision_map() -> void:
	for offset in [Vector2.ZERO, Vector2(0.125, 0.0), Vector2(-0.125, 0.125),
			Vector2(0.0, -0.125)]:
		var position := EDIT_POINT + Vector3(offset.x, 0.0, offset.y)
		var x := clampi(floori((position.x + 16.0) / 0.125), 0, 255)
		var z := clampi(floori((position.z + 16.0) / 0.125), 0, 255)
		var expected: float = preview.shadow_domain.bed_at(preview.shadow_domain.index(x, z))
		var chunk_id: int = (z / 32) * 8 + x / 32
		var shape: CollisionShape3D = preview.collision_proxy.shapes[chunk_id]
		var samples: PackedFloat32Array = shape.shape.map_data
		var sample: float = samples[(z % 32) * 33 + x % 32]
		maximum_height_error_m = maxf(maximum_height_error_m,
			absf(sample - expected))


func _sample_ray_height() -> void:
	for offset in [Vector2.ZERO, Vector2(0.125, 0.0), Vector2(-0.125, 0.125),
			Vector2(0.0, -0.125)]:
		var position := EDIT_POINT + Vector3(offset.x, 0.0, offset.y)
		var query := PhysicsRayQueryParameters3D.create(
			position + Vector3.UP * 10.0, position + Vector3.DOWN * 10.0)
		var hit: Dictionary = root.world_3d.direct_space_state.intersect_ray(query)
		if not hit.has("position"):
			_fail("continuous edit collision ray missed")
			return
		var x := clampi(floori((position.x + 16.0) / 0.125), 0, 255)
		var z := clampi(floori((position.z + 16.0) / 0.125), 0, 255)
		var expected: float = preview.shadow_domain.bed_at(preview.shadow_domain.index(x, z))
		maximum_ray_error_m = maxf(maximum_ray_error_m,
			absf(hit.position.y - expected))


func _settle() -> void:
	if finished:
		return
	if not preview.last_error.is_empty() or preview.collision_proxy.invalid_readbacks > 0:
		_fail("continuous edit failed during settle")
		return
	_poll_completed()
	if completed < submitted:
		if Time.get_ticks_usec() - started_usec > (duration_seconds + 10) * 1000000:
			_fail("continuous edit did not settle: %d/%d pending=%s" % [
				completed, submitted, str(pending_records.slice(0, mini(3, pending_records.size())))])
			return
		await process_frame
		call_deferred("_settle")
		return
	preview.playing = false
	while preview.tick_pending:
		await process_frame
	if coupled and preview.shadow_revision != preview.solver.state_revision:
		preview._request_shadow_sync("debug")
		while preview.shadow_revision != preview.solver.state_revision:
			await process_frame
	if coupled:
		_sample_collision_map()
		await physics_frame
		_sample_ray_height()
	sand_readback = PackedByteArray()
	RenderingServer.call_on_render_thread(_render_read_sand)
	while sand_readback.is_empty():
		await process_frame
	var actual := sand_readback.to_float32_array()
	var sand_error := 0.0
	for i in actual.size():
		sand_error = maxf(sand_error, absf(actual[i] - preview.shadow_domain.sand[i]))
	latencies_ms.sort()
	var p95_index := clampi(ceili(float(latencies_ms.size()) * 0.95) - 1,
		0, latencies_ms.size() - 1)
	var p95_ms: float = latencies_ms[p95_index]
	var max_ms := _maximum_latency()
	var final_static := int(Performance.get_monitor(Performance.MEMORY_STATIC))
	var final_video := int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED))
	rows.append("%d,%d,%d,%d,%d,%.3f,%.6f,%.6f,%.6f,%d,%d,%d,%d,%d" % [
		duration_seconds, preview.completed_ticks, submitted, completed,
		pending_records.size(), max_ms, preview.max_cell_edit_height_m,
		maximum_height_error_m, maximum_ray_error_m,
		final_static, final_video, preview.checkpoints.size(),
		preview.collision_proxy.completed_batches,
		preview.collision_proxy.invalid_readbacks])
	var file := FileAccess.open(csv_path, FileAccess.WRITE)
	if file == null:
		_fail("continuous edit CSV unavailable")
		return
	file.store_string("\n".join(rows) + "\n")
	file.close()
	var latency_path := csv_path.trim_suffix(".csv") + "_latencies.csv"
	var latency_file := FileAccess.open(latency_path, FileAccess.WRITE)
	if latency_file == null:
		_fail("continuous edit latency CSV unavailable")
		return
	latency_file.store_string("\n".join(latency_rows) + "\n")
	latency_file.close()
	var memory_base_static := steady_static if steady_static >= 0 else warm_static
	var memory_base_video := steady_video if steady_video >= 0 else warm_video
	if duration_seconds >= 60 and submitted < 900 or sand_error > 0.000001 or \
			maximum_height_error_m > preview.max_cell_edit_height_m + 0.000001 or \
			max_ms > 100.0 or \
			(memory_base_static >= 0 and (final_static - memory_base_static > 4 * 1024 * 1024 or
			final_video - memory_base_video > 4 * 1024 * 1024)):
		_fail("continuous edit limits failed edits=%d sand=%.8f collision_sample=%.6f cell_edit=%.6f p95_ms=%.3f max_ms=%.3f sand_only_syncs=%d prefetch_hits=%d full_syncs=%d static_growth=%d video_growth=%d postfill_static=%d" % [
			submitted, sand_error, maximum_height_error_m,
			preview.max_cell_edit_height_m, p95_ms, max_ms,
			preview.sand_only_syncs, preview.sand_prefetch_hits,
			preview.full_shadow_syncs,
			final_static - warm_static, final_video - warm_video,
			final_static - memory_base_static])
		return
	print("PASS: GPU %s%d-second continuous edits=%d ticks=%d collision_p95=%.3f max=%.3f ms collision_sample_max=%.6f cell_edit_max=%.6f ray_center_max=%.6f sand_error=%.8f pending_max=%d full_shadow_syncs=%d sand_only_syncs=%d prefetch_hits=%d static_growth=%d postfill_growth=%d video_growth=%d CSV=%s" % [
		"coupled " if coupled else "", duration_seconds, submitted,
		preview.completed_ticks, p95_ms,
		max_ms, maximum_height_error_m, preview.max_cell_edit_height_m,
		maximum_ray_error_m, sand_error, maximum_pending, preview.full_shadow_syncs,
		preview.sand_only_syncs, preview.sand_prefetch_hits,
		final_static - warm_static, final_static - memory_base_static,
		final_video - warm_video, csv_path])
	finished = true
	preview.queue_free()
	quit(0)


func _maximum_latency() -> float:
	var maximum := 0.0
	for value in latencies_ms:
		maximum = maxf(maximum, value)
	return maximum


func _render_read_sand() -> void:
	var error: Error = preview.solver.request_data("sand", _on_sand)
	if error != OK:
		call_deferred("_fail", "continuous edit sand readback failed")


func _on_sand(data: PackedByteArray) -> void:
	call_deferred("_record_sand", data)


func _record_sand(data: PackedByteArray) -> void:
	sand_readback = data


func _fail(message: String) -> void:
	if finished:
		return
	finished = true
	printerr("FAIL: " + message)
	if preview != null:
		preview.queue_free()
	quit(1)

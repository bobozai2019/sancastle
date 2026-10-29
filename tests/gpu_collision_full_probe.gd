extends SceneTree

var preview: Node3D
var readback := PackedByteArray()
var started_ms := 0
var finished := false


func _init() -> void:
	call_deferred("_begin")


func _begin() -> void:
	var scene: PackedScene = load("res://scenes/gpu_water_preview.tscn")
	preview = scene.instantiate()
	root.add_child(preview)
	started_ms = Time.get_ticks_msec()
	call_deferred("_watchdog")
	call_deferred("_run")


func _run() -> void:
	while preview.completed_ticks < 3:
		await process_frame
	preview.playing = false
	while preview.tick_pending or preview.collision_proxy.shapes.size() < 64 or \
			not preview.collision_proxy.pending_revisions.is_empty() or \
			not preview.collision_proxy.active_chunks.is_empty():
		await process_frame
	for frame in 3:
		await process_frame
	var rock: PackedFloat32Array = await _read_field("rock")
	var sand: PackedFloat32Array = await _read_field("sand")
	var bad_chunks := []
	var total_bad := 0
	var maximum := 0.0
	for chunk_id in 64:
		var shape: CollisionShape3D = preview.collision_proxy.shapes[chunk_id]
		var values: PackedFloat32Array = shape.shape.map_data
		var bad := 0
		var chunk_max := 0.0
		for local_z in 33:
			for local_x in 33:
				var x: int = mini((chunk_id % 8) * 32 + local_x, 255)
				var z: int = mini((chunk_id / 8) * 32 + local_z, 255)
				var i := z * 256 + x
				var error := absf(values[local_z * 33 + local_x] - rock[i] - sand[i])
				chunk_max = maxf(chunk_max, error)
				if error > 0.00001:
					bad += 1
		if bad > 0:
			bad_chunks.append("%d:%d:%.6f" % [chunk_id, bad, chunk_max])
			total_bad += bad
		maximum = maxf(maximum, chunk_max)
	print("COLLISION_FULL bad=%d max=%.8f chunks=%s" % [total_bad, maximum, str(bad_chunks)])
	finished = true
	preview.queue_free()
	quit(0 if total_bad == 0 else 1)


func _read_field(field: String) -> PackedFloat32Array:
	readback = PackedByteArray()
	RenderingServer.call_on_render_thread(_render_read.bind(field))
	while readback.is_empty():
		await process_frame
	return readback.to_float32_array()


func _render_read(field: String) -> void:
	var error: Error = preview.solver.request_data(field, _on_data)
	if error != OK:
		call_deferred("_fail", "collision full readback failed %s" % field)


func _on_data(data: PackedByteArray) -> void:
	call_deferred("_record_data", data)


func _record_data(data: PackedByteArray) -> void:
	readback = data


func _watchdog() -> void:
	if finished:
		return
	if Time.get_ticks_msec() - started_ms > 30000:
		_fail("collision full probe timeout")
		return
	await process_frame
	call_deferred("_watchdog")


func _fail(message: String) -> void:
	if finished:
		return
	finished = true
	printerr("FAIL: " + message)
	preview.queue_free()
	quit(1)

class_name SandcastleGpuCollisionProxy
extends Node3D

## Render-thread requests pack only dirty 32x32 bed chunks. Async readback
## reaches the main thread before a physics shape is replaced.

const CHUNK_SIZE := 32
const CHUNK_SAMPLES := CHUNK_SIZE + 1
const MAX_BATCH_CHUNKS := 16
const PrepareJob = preload("res://scripts/collision/collision_prepare_job.gd")
const PrepareScheduler = preload("res://scripts/collision/collision_prepare_scheduler.gd")

var solver: SandcastleGpuShallowSolver
var rd: RenderingDevice
var shader := RID()
var pipeline := RID()
var chunk_buffer := RID()
var staging_texture := RID()
var uniform_set := RID()
@onready var body: StaticBody3D = $GpuTerrainCollision
var shapes: Dictionary = {}
var reuse_chunk_shapes := false
var shape_allocations := 0
var shape_reuses := 0
var shape_unchanged_skips := 0
var applied_revisions: Dictionary = {}
var applied_usec: Dictionary = {}
var pending_revisions: Dictionary = {}
var active_chunks := PackedInt32Array()
var active_revision := 0
var active_generation := 0
var generation := 0
var closing := false
var request_started_usec := 0
var last_readback_ms := 0.0
var last_replace_ms := 0.0
var last_apply_ms := 0.0
var last_apply_generation := -1
var last_batch_replaced_chunks := 0
var last_batch_unchanged_chunks := 0
var completed_batches := 0
var invalid_readbacks := 0
var profile_passes := false
var profile_latency_details := false
var pending_queued_usec: Dictionary = {}
var active_queued_usec := PackedInt64Array()
var applied_stage_usec: Dictionary = {}
var last_prepare_segments: Dictionary = {}
var prepare_policy := "baseline"
var prepare_scheduler: RefCounted
var prepare_serial := 0
var stale_prepared_batches := 0
var prepare_backpressure_fallbacks := 0
var recent_prepared_ids: Array[int] = []
var last_prepare_worker: Dictionary = {}
var prepare_admission_us: Dictionary = {}
var prepare_poll_us := 0
var prepare_min_chunks := 1
var cost_samples: Array[Dictionary] = []

func _record_cost_sample(chunks: int, mode: String) -> void:
	if not profile_latency_details:return
	cost_samples.append({"generation":last_apply_generation,"chunks":chunks,"mode":mode,
		"at_usec":Time.get_ticks_usec(),"apply_ms":last_apply_ms,"submit_ms":last_replace_ms,
		"readback_ms":last_readback_ms,"segments":last_prepare_segments.duplicate(true),
		"worker":last_prepare_worker.duplicate(true) if mode.begins_with("worker") else {},
		"replaced":last_batch_replaced_chunks,"unchanged":last_batch_unchanged_chunks})
	if cost_samples.size()>256:cost_samples.pop_front()

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--collision-prepare-min="):
			var value:=arg.trim_prefix("--collision-prepare-min=")
			if value.is_valid_int() and int(value)>=1 and int(value)<=MAX_BATCH_CHUNKS:
				prepare_min_chunks=int(value)
			else:push_error("invalid collision prepare minimum: "+value)
		if arg.begins_with("--collision-prepare="):
			var requested := arg.trim_prefix("--collision-prepare=")
			if requested in ["baseline", "serial", "worker1", "worker2", "worker4"]:
				prepare_policy = requested
			else:
				push_error("invalid collision prepare policy: " + requested)

func has_prepare_in_flight() -> bool:
	return prepare_scheduler != null and prepare_scheduler.has_in_flight()

func stop_prepare_and_drain() -> void:
	if prepare_scheduler == null:
		return
	prepare_scheduler.stop_admission()
	while prepare_scheduler.has_in_flight():
		for result in prepare_scheduler.poll_completed(): _commit_prepared(result)
		if prepare_scheduler.has_in_flight(): await get_tree().process_frame
	prepare_admission_us.clear()

func _process(_delta: float) -> void:
	if prepare_scheduler == null or not prepare_scheduler.has_in_flight():
		return
	if closing:
		prepare_scheduler.stop_admission()
	var start := Time.get_ticks_usec()
	var results: Array[Dictionary] = prepare_scheduler.poll_completed()
	prepare_poll_us += Time.get_ticks_usec()-start
	for result in results:
		result.poll_cpu_us = prepare_poll_us
		prepare_poll_us = 0
		_commit_prepared(result)

func _commit_prepared(result: Dictionary) -> void:
	var admission_us: int = prepare_admission_us.get(result.request_id, 0)
	prepare_admission_us.erase(result.request_id)
	if closing or result.generation != generation:
		stale_prepared_batches += 1
		return
	if recent_prepared_ids.has(result.request_id):
		return
	# Scheduler emits each request once. This bounded guard also catches accidental
	# duplicate delivery; ordering is decided per chunk, never by a global watermark.
	recent_prepared_ids.append(result.request_id)
	if recent_prepared_ids.size() > 128: recent_prepared_ids.pop_front()
	if result.status != &"prepared":
		invalid_readbacks += 1
		if result.status == &"worker_failed":
			push_error("collision preparation failed after serial retry")
			if get_parent().has_method("_fail"):
				get_parent()._fail("collision preparation failed")
		return
	var start := Time.get_ticks_usec()
	var replaced_before := shape_allocations + shape_reuses
	var skipped_before := shape_unchanged_skips
	for slot in result.chunks.size():
		var chunk: Dictionary = result.chunks[slot]
		if result.captured_revision < int(applied_revisions.get(chunk.chunk_id, -1)):
			continue
		_replace_chunk_shape(chunk.chunk_id, result.captured_revision, chunk.heights)
		if profile_latency_details and slot < result.queued_usec.size():
			applied_stage_usec[chunk.chunk_id] = PackedInt64Array([result.queued_usec[slot],
				result.requested_usec, result.readback_done_usec, applied_usec[chunk.chunk_id]])
	last_replace_ms = float(Time.get_ticks_usec()-start)/1000.0
	last_apply_ms = last_replace_ms + float(admission_us + result.get("poll_cpu_us",0))/1000.0
	last_apply_generation = result.generation
	last_readback_ms = float(result.readback_done_usec-result.requested_usec)/1000.0
	last_batch_replaced_chunks = shape_allocations + shape_reuses - replaced_before
	last_batch_unchanged_chunks = shape_unchanged_skips - skipped_before
	last_prepare_worker = {"request_id":result.request_id,"scheduled_usec":result.scheduled_usec,
		"collected_usec":result.collected_usec,"timings":result.timings,"worker_count":result.worker_count,
		"admission_cpu_us":admission_us,"poll_cpu_us":result.get("poll_cpu_us",0)}
	last_prepare_segments = {"generation":result.generation,"revision":result.captured_revision,
		"chunks":result.chunks.size(),"admission_us":admission_us,
		"poll_cpu_us":result.get("poll_cpu_us",0),"submit_us":int(last_replace_ms*1000.0),
		"apply_us":int(last_apply_ms*1000.0),"prepare_mode":prepare_policy}
	completed_batches += 1
	_record_cost_sample(result.chunks.size(),prepare_policy)


func setup_render(p_solver: SandcastleGpuShallowSolver,
		spirv: RDShaderSPIRV, token: int) -> bool:
	if closing or p_solver == null or spirv == null or token < 1:
		return false
	solver = p_solver
	rd = p_solver.rd
	generation = token
	shader = rd.shader_create_from_spirv(spirv)
	if not shader.is_valid():
		return false
	pipeline = rd.compute_pipeline_create(shader)
	chunk_buffer = rd.storage_buffer_create(MAX_BATCH_CHUNKS * 4)
	return pipeline.is_valid() and chunk_buffer.is_valid()


func request_chunks_render(chunks: PackedInt32Array, revision: int, token: int) -> bool:
	if closing or rd == null or token != generation or revision < 0:
		return false
	var per_row: int = solver.grid_size / CHUNK_SIZE
	for chunk_id in chunks:
		if chunk_id < 0 or chunk_id >= per_row * per_row:
			return false
		pending_revisions[chunk_id] = maxi(int(pending_revisions.get(chunk_id, -1)), revision)
		if profile_latency_details:
			pending_queued_usec[chunk_id] = Time.get_ticks_usec()
	if not staging_texture.is_valid():
		_dispatch_pending_render()
	return true


func apply_shadow_chunks(chunks: PackedInt32Array, revision: int, token: int,
		rock: PackedFloat32Array, sand: PackedFloat32Array) -> bool:
	if closing or token != generation or solver == null or revision < 0:
		return false
	var grid_size: int = solver.grid_size
	if rock.size() != grid_size * grid_size or sand.size() != rock.size():
		return false
	var per_row: int = grid_size / CHUNK_SIZE
	var seen := {}
	var prepared := []
	for chunk_id in chunks:
		if chunk_id < 0 or chunk_id >= per_row * per_row or seen.has(chunk_id):
			return false
		seen[chunk_id] = true
		var values := PackedFloat32Array()
		values.resize(CHUNK_SAMPLES * CHUNK_SAMPLES)
		for local_z in CHUNK_SAMPLES:
			var z: int = mini((chunk_id / per_row) * CHUNK_SIZE + local_z,
				grid_size - 1)
			for local_x in CHUNK_SAMPLES:
				var x: int = mini((chunk_id % per_row) * CHUNK_SIZE + local_x,
					grid_size - 1)
				var index: int = z * grid_size + x
				var height: float = rock[index] + sand[index]
				if not is_finite(height):
					return false
				values[local_z * CHUNK_SAMPLES + local_x] = height
		# Conversion to float32 can overflow a finite double sum. The shared pure
		# validator checks actual collider bytes; no chunk publishes before all pass.
		var decoded := PrepareJob.decode_heights(values.to_byte_array())
		if decoded.status != &"prepared":
			return false
		prepared.append({"chunk_id":chunk_id,"heights":decoded.heights})
	for chunk in prepared:
		var chunk_id: int = chunk.chunk_id
		if revision < int(applied_revisions.get(chunk_id, -1)):
			continue
		_replace_chunk_shape(chunk_id, revision, chunk.heights)
		if profile_latency_details:
			applied_stage_usec.erase(chunk_id)
	return true


func _dispatch_pending_render() -> void:
	if closing or rd == null or pending_revisions.is_empty() or staging_texture.is_valid():
		return
	var sorted_ids: Array = pending_revisions.keys()
	sorted_ids.sort()
	active_chunks = PackedInt32Array()
	active_queued_usec = PackedInt64Array()
	active_revision = 0
	for i in mini(sorted_ids.size(), MAX_BATCH_CHUNKS):
		var chunk_id: int = sorted_ids[i]
		active_chunks.append(chunk_id)
		if profile_latency_details:
			active_queued_usec.append(int(pending_queued_usec.get(chunk_id, 0)))
			pending_queued_usec.erase(chunk_id)
		active_revision = maxi(active_revision, int(pending_revisions[chunk_id]))
		pending_revisions.erase(chunk_id)
	var format := RDTextureFormat.new()
	format.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	format.width = CHUNK_SAMPLES
	format.height = CHUNK_SAMPLES * active_chunks.size()
	format.format = RenderingDevice.DATA_FORMAT_R32_SFLOAT
	format.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | \
		RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	staging_texture = rd.texture_create(format, RDTextureView.new())
	if not staging_texture.is_valid():
		call_deferred("_report_failure", "collision staging texture creation failed")
		return
	if rd.buffer_update(chunk_buffer, 0, active_chunks.size() * 4,
			active_chunks.to_byte_array()) != OK:
		call_deferred("_report_failure", "collision chunk upload failed")
		return
	var resources: Array[RID] = [solver.current_texture("rock"),
		solver.current_texture("sand"), staging_texture, chunk_buffer]
	var uniforms: Array[RDUniform] = []
	for binding in resources.size():
		var uniform := RDUniform.new()
		uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER if binding == 3 else \
			RenderingDevice.UNIFORM_TYPE_IMAGE
		uniform.binding = binding
		uniform.add_id(resources[binding])
		uniforms.append(uniform)
	uniform_set = rd.uniform_set_create(uniforms, shader, 0)
	if not uniform_set.is_valid():
		call_deferred("_report_failure", "collision uniform set creation failed")
		return
	if profile_passes:
		rd.capture_timestamp("sandcastle_collision_start")
	var list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list, pipeline)
	rd.compute_list_bind_uniform_set(list, uniform_set, 0)
	rd.compute_list_set_push_constant(list, PackedInt32Array([
		solver.grid_size, solver.grid_size / CHUNK_SIZE,
		active_chunks.size(), 0]).to_byte_array(), 16)
	rd.compute_list_dispatch(list, ceili(float(CHUNK_SAMPLES) / 8.0),
		ceili(float(CHUNK_SAMPLES * active_chunks.size()) / 8.0), 1)
	rd.compute_list_end()
	if profile_passes:
		rd.capture_timestamp("sandcastle_collision_end")
	active_generation = generation
	request_started_usec = Time.get_ticks_usec()
	var error := _request_staging_readback()
	if error != OK:
		call_deferred("_report_failure", "collision readback request failed: %d" % error)

func _request_staging_readback() -> Error:
	return rd.texture_get_data_async(staging_texture, 0, _on_data_render)


func _on_data_render(data: PackedByteArray) -> void:
	var chunks := active_chunks
	var queued_usec := active_queued_usec
	var revision := active_revision
	var token := active_generation
	var readback_done_usec := Time.get_ticks_usec()
	var requested_usec := request_started_usec
	var elapsed_ms := float(readback_done_usec - requested_usec) / 1000.0
	if uniform_set.is_valid():
		rd.free_rid(uniform_set)
	if staging_texture.is_valid():
		rd.free_rid(staging_texture)
	uniform_set = RID()
	staging_texture = RID()
	active_chunks = PackedInt32Array()
	active_queued_usec = PackedInt64Array()
	if not closing:
		call_deferred("_apply_data", data, chunks, revision, token, elapsed_ms,
			queued_usec, requested_usec, readback_done_usec)
		# Do not start the next GPU batch from inside an async readback callback.
		# D3D12 produced valid data for batch 1 but stale/zero rows for later
		# batches when their compute and readback were submitted recursively here.
		call_deferred("_schedule_pending_render")


func _schedule_pending_render() -> void:
	if not closing:
		RenderingServer.call_on_render_thread(_dispatch_pending_render)


func _apply_data(data: PackedByteArray, chunks: PackedInt32Array,
		revision: int, token: int, elapsed_ms: float,
		queued_usec: PackedInt64Array, requested_usec: int,
		readback_done_usec: int) -> void:
	var callback_start := Time.get_ticks_usec()
	if closing or token != generation:
		return
	if solver == null or revision < 0 or chunks.is_empty() or chunks.size() > MAX_BATCH_CHUNKS:
		invalid_readbacks += 1
		return
	var per_row: int = solver.grid_size / CHUNK_SIZE
	var seen := {}
	for chunk in chunks:
		if chunk < 0 or chunk >= per_row*per_row or seen.has(chunk):
			invalid_readbacks += 1
			return
		seen[chunk] = true
	if prepare_policy=="serial" or (prepare_policy.begins_with("worker") and chunks.size()>=prepare_min_chunks):
		var admission_start := callback_start
		if prepare_scheduler == null:
			prepare_scheduler = PrepareScheduler.new()
		prepare_serial += 1
		var request := {"schema_version":1,"request_id":prepare_serial,"generation":token,
			"captured_revision":revision,"grid_size":solver.grid_size,"chunks":chunks,
			"raw_heights":data,"queued_usec":queued_usec,"requested_usec":requested_usec,
			"readback_done_usec":readback_done_usec,"task_policy":prepare_policy}
		var error: StringName = prepare_scheduler.enqueue(request)
		prepare_admission_us[prepare_serial] = Time.get_ticks_usec()-admission_start
		if error == &"backpressure":
			# This already-read snapshot cannot be dropped. Use the same pure serial oracle.
			prepare_backpressure_fallbacks += 1
			var job := PrepareJob.new(request)
			job.scheduled_usec = Time.get_ticks_usec()
			job.prepare_serial()
			job.collected_usec = Time.get_ticks_usec()
			_commit_prepared(job.result())
		elif not error.is_empty():
			prepare_admission_us.erase(prepare_serial)
			invalid_readbacks += 1
		elif prepare_policy == "serial":
			_process(0.0)
		return
	var apply_start := callback_start
	if data.size() != chunks.size() * CHUNK_SAMPLES * CHUNK_SAMPLES * 4:
		invalid_readbacks += 1
		return
	var decoded := PrepareJob.decode_heights(data, profile_latency_details)
	if decoded.status != &"prepared":
		invalid_readbacks += 1
		return
	var heights: PackedFloat32Array = decoded.heights
	var replace_start := Time.get_ticks_usec()
	var slice_us := 0
	var submit_us := 0
	var replaced_before := shape_allocations + shape_reuses
	var unchanged_before := shape_unchanged_skips
	var samples_per_chunk := CHUNK_SAMPLES * CHUNK_SAMPLES
	for slot in chunks.size():
		var chunk_id: int = chunks[slot]
		if revision < int(applied_revisions.get(chunk_id, -1)):
			continue
		var offset := slot * samples_per_chunk
		var slice_start := Time.get_ticks_usec() if profile_latency_details else 0
		var values := heights.slice(offset, offset + samples_per_chunk)
		var submit_start := Time.get_ticks_usec() if profile_latency_details else 0
		_replace_chunk_shape(chunk_id, revision, values)
		if profile_latency_details:
			slice_us += submit_start - slice_start
			submit_us += Time.get_ticks_usec() - submit_start
		if profile_latency_details and slot < queued_usec.size():
			applied_stage_usec[chunk_id] = PackedInt64Array([
				queued_usec[slot], requested_usec, readback_done_usec,
				int(applied_usec[chunk_id])])
	last_readback_ms = elapsed_ms
	last_replace_ms = float(Time.get_ticks_usec() - replace_start) / 1000.0
	last_batch_replaced_chunks = shape_allocations + shape_reuses - replaced_before
	last_batch_unchanged_chunks = shape_unchanged_skips - unchanged_before
	last_apply_generation = token
	last_apply_ms = float(Time.get_ticks_usec() - apply_start) / 1000.0
	if profile_latency_details:
		last_prepare_segments = {"generation":token,"revision":revision,"chunks":chunks.size(),
			"decode_us":decoded.decode_us,"finite_us":decoded.finite_us,
			"slice_us":slice_us,"submit_us":submit_us,"apply_us":int(last_apply_ms*1000.0),
			"callback_to_apply_us":apply_start-readback_done_usec}
	completed_batches += 1
	_record_cost_sample(chunks.size(),"baseline")


func _replace_chunk_shape(chunk_id: int, revision: int,
		values: PackedFloat32Array) -> void:
	var per_row: int = solver.grid_size / CHUNK_SIZE
	var half_extent: float = float(solver.grid_size) * solver.cell_size_m * 0.5
	var node: CollisionShape3D = shapes.get(chunk_id)
	var chunk_position := Vector3(
		(float(chunk_id % per_row * CHUNK_SIZE) + 16.5) * solver.cell_size_m - half_extent,
		0.0,
		(float(chunk_id / per_row * CHUNK_SIZE) + 16.5) * solver.cell_size_m - half_extent)
	var chunk_scale := Vector3(solver.cell_size_m, 1.0, solver.cell_size_m)
	# Exact finite heights and the same transform need no PhysicsServer update.
	# Still acknowledge this revision, including after a generation restore.
	if node != null and node.shape is HeightMapShape3D and \
			node.shape.map_width == CHUNK_SAMPLES and node.shape.map_depth == CHUNK_SAMPLES and \
			node.position == chunk_position and node.scale == chunk_scale and \
			node.shape.map_data == values:
		shape_unchanged_skips += 1
		applied_revisions[chunk_id] = revision
		applied_usec[chunk_id] = Time.get_ticks_usec()
		return
	var shape: HeightMapShape3D
	if reuse_chunk_shapes and node!=null and node.shape is HeightMapShape3D:
		shape=node.shape;shape_reuses+=1
	else:
		shape=HeightMapShape3D.new();shape_allocations+=1
		shape.map_width = CHUNK_SAMPLES
		shape.map_depth = CHUNK_SAMPLES
	shape.map_data = values
	if node == null:
		node = CollisionShape3D.new()
		node.name = "Chunk_%d" % chunk_id
		body.add_child(node)
		shapes[chunk_id] = node
	node.position = chunk_position
	node.scale = chunk_scale
	node.shape = shape
	applied_revisions[chunk_id] = revision
	applied_usec[chunk_id] = Time.get_ticks_usec()


func _report_failure(message: String) -> void:
	invalid_readbacks += 1
	push_error(message)


func _exit_tree() -> void:
	closing = true
	generation += 1
	if prepare_scheduler != null:
		prepare_scheduler.detach(get_tree())
	RenderingServer.call_on_render_thread(_release_render)


func _release_render() -> void:
	if rd == null:
		return
	for rid in [uniform_set, staging_texture, chunk_buffer, pipeline, shader]:
		if rid.is_valid():
			rd.free_rid(rid)
	uniform_set = RID()
	staging_texture = RID()
	chunk_buffer = RID()
	pipeline = RID()
	shader = RID()
	rd = null

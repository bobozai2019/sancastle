class_name SandcastleGpuCollisionProxy
extends Node3D

## Render-thread requests pack only dirty 32x32 bed chunks. Async readback
## reaches the main thread before a physics shape is replaced.

const CHUNK_SIZE := 32
const CHUNK_SAMPLES := CHUNK_SIZE + 1
const MAX_BATCH_CHUNKS := 16

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
var completed_batches := 0
var invalid_readbacks := 0
var profile_passes := false
var profile_latency_details := false
var pending_queued_usec: Dictionary = {}
var active_queued_usec := PackedInt64Array()
var applied_stage_usec: Dictionary = {}


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
	for chunk_id in chunks:
		if chunk_id < 0 or chunk_id >= per_row * per_row:
			return false
		if revision < int(applied_revisions.get(chunk_id, -1)):
			continue
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
		_replace_chunk_shape(chunk_id, revision, values)
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
	var error := rd.texture_get_data_async(staging_texture, 0, _on_data_render)
	if error != OK:
		call_deferred("_report_failure", "collision readback request failed: %d" % error)


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
	if closing or token != generation:
		return
	if data.size() != chunks.size() * CHUNK_SAMPLES * CHUNK_SAMPLES * 4:
		invalid_readbacks += 1
		return
	var heights := data.to_float32_array()
	for value in heights:
		if not is_finite(value):
			invalid_readbacks += 1
			return
	var replace_start := Time.get_ticks_usec()
	for slot in chunks.size():
		var chunk_id: int = chunks[slot]
		if revision < int(applied_revisions.get(chunk_id, -1)):
			continue
		var values := PackedFloat32Array()
		values.resize(CHUNK_SAMPLES * CHUNK_SAMPLES)
		for i in values.size():
			values[i] = heights[slot * values.size() + i]
		_replace_chunk_shape(chunk_id, revision, values)
		if profile_latency_details and slot < queued_usec.size():
			applied_stage_usec[chunk_id] = PackedInt64Array([
				queued_usec[slot], requested_usec, readback_done_usec,
				int(applied_usec[chunk_id])])
	last_readback_ms = elapsed_ms
	last_replace_ms = float(Time.get_ticks_usec() - replace_start) / 1000.0
	completed_batches += 1


func _replace_chunk_shape(chunk_id: int, revision: int,
		values: PackedFloat32Array) -> void:
	var per_row: int = solver.grid_size / CHUNK_SIZE
	var half_extent: float = float(solver.grid_size) * solver.cell_size_m * 0.5
	var node: CollisionShape3D = shapes.get(chunk_id)
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
	node.position = Vector3(
		(float(chunk_id % per_row * CHUNK_SIZE) + 16.5) * solver.cell_size_m - half_extent,
		0.0,
		(float(chunk_id / per_row * CHUNK_SIZE) + 16.5) * solver.cell_size_m - half_extent)
	node.scale = Vector3(solver.cell_size_m, 1.0, solver.cell_size_m)
	node.shape = shape
	applied_revisions[chunk_id] = revision
	applied_usec[chunk_id] = Time.get_ticks_usec()


func _report_failure(message: String) -> void:
	invalid_readbacks += 1
	push_error(message)


func _exit_tree() -> void:
	closing = true
	generation += 1
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

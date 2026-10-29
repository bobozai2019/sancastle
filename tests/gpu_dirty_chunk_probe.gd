extends SceneTree

const SOURCE_SIZE := 256
const CHUNK_SIZE := 32

var rd: RenderingDevice
var source_spirv: RDShaderSPIRV
var pack_spirv: RDShaderSPIRV
var source_texture := RID()
var staging_texture := RID()
var source_shader := RID()
var source_pipeline := RID()
var source_set := RID()
var pack_shader := RID()
var pack_pipeline := RID()
var pack_set := RID()
var body: StaticBody3D
var collision_nodes: Array[CollisionShape3D] = []
var completed_cases := 0
var request_us := 0
var watchdog_frames := 0
var finished := false


func _init() -> void:
	call_deferred("_begin")


func _begin() -> void:
	var source_file: RDShaderFile = load("res://shaders/benchmarks/checker_compute.glsl")
	var pack_file: RDShaderFile = load("res://shaders/benchmarks/pack_dirty_chunks.glsl")
	if source_file == null or pack_file == null:
		_fail("shader import failed")
		return
	source_spirv = source_file.get_spirv()
	pack_spirv = pack_file.get_spirv()
	body = StaticBody3D.new()
	root.add_child(body)
	RenderingServer.call_on_render_thread(_render_setup)
	call_deferred("_watchdog")


func _render_setup() -> void:
	rd = RenderingServer.get_rendering_device()
	if rd == null:
		call_deferred("_fail", "main RenderingDevice unavailable")
		return
	source_texture = rd.texture_create(_format(SOURCE_SIZE, SOURCE_SIZE), RDTextureView.new())
	source_shader = rd.shader_create_from_spirv(source_spirv)
	pack_shader = rd.shader_create_from_spirv(pack_spirv)
	if not source_texture.is_valid() or not source_shader.is_valid() or not pack_shader.is_valid():
		call_deferred("_fail", "source GPU resources invalid")
		return
	source_pipeline = rd.compute_pipeline_create(source_shader)
	pack_pipeline = rd.compute_pipeline_create(pack_shader)
	var source_uniform := RDUniform.new()
	source_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	source_uniform.binding = 0
	source_uniform.add_id(source_texture)
	source_set = rd.uniform_set_create([source_uniform], source_shader, 0)
	if not source_pipeline.is_valid() or not pack_pipeline.is_valid() or not source_set.is_valid():
		call_deferred("_fail", "compute pipelines invalid")
		return
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, source_pipeline)
	rd.compute_list_bind_uniform_set(compute_list, source_set, 0)
	rd.compute_list_dispatch(compute_list, SOURCE_SIZE / 8, SOURCE_SIZE / 8, 1)
	rd.compute_list_end()
	_run_case(1)


func _format(width: int, height: int) -> RDTextureFormat:
	var result := RDTextureFormat.new()
	result.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	result.width = width
	result.height = height
	result.format = RenderingDevice.DATA_FORMAT_R32_SFLOAT
	result.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	return result


func _run_case(count: int) -> void:
	staging_texture = rd.texture_create(_format(CHUNK_SIZE, CHUNK_SIZE * count), RDTextureView.new())
	var source_uniform := RDUniform.new()
	source_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	source_uniform.binding = 0
	source_uniform.add_id(source_texture)
	var packed_uniform := RDUniform.new()
	packed_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	packed_uniform.binding = 1
	packed_uniform.add_id(staging_texture)
	pack_set = rd.uniform_set_create([source_uniform, packed_uniform], pack_shader, 0)
	if not staging_texture.is_valid() or not pack_set.is_valid():
		call_deferred("_fail", "dirty chunk resources invalid")
		return
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pack_pipeline)
	rd.compute_list_bind_uniform_set(compute_list, pack_set, 0)
	var params := PackedInt32Array([96, 112, count, 0]).to_byte_array()
	rd.compute_list_set_push_constant(compute_list, params, params.size())
	rd.compute_list_dispatch(compute_list, CHUNK_SIZE / 8, CHUNK_SIZE * count / 8, 1)
	rd.compute_list_end()
	request_us = Time.get_ticks_usec()
	var err := rd.texture_get_data_async(staging_texture, 0, _on_data.bind(count))
	if err != OK:
		call_deferred("_fail", "async read failed: %d" % err)


func _on_data(data: PackedByteArray, count: int) -> void:
	call_deferred("_verify_case", data, count, Time.get_ticks_usec())


func _verify_case(data: PackedByteArray, count: int, callback_us: int) -> void:
	if finished:
		return
	if data.size() != CHUNK_SIZE * CHUNK_SIZE * count * 4:
		_fail("%d chunks: unexpected data bytes %d" % [count, data.size()])
		return
	var heights := data.to_float32_array()
	var expected_first := 1.0 if ((96 / 8 + 112 / 8) % 2 == 0) else 0.25
	if absf(heights[0] - expected_first) > 0.01:
		_fail("%d chunks: first GPU height %f" % [count, heights[0]])
		return
	var collision_start := Time.get_ticks_usec()
	for old_node in collision_nodes:
		old_node.queue_free()
	collision_nodes.clear()
	for chunk in count:
		var height_data := PackedFloat32Array()
		height_data.resize(CHUNK_SIZE * CHUNK_SIZE)
		for i in height_data.size():
			height_data[i] = heights[chunk * height_data.size() + i]
		var shape := HeightMapShape3D.new()
		shape.map_width = CHUNK_SIZE
		shape.map_depth = CHUNK_SIZE
		shape.map_data = height_data
		var collision := CollisionShape3D.new()
		collision.shape = shape
		collision.position = Vector3(chunk * 34.0, 0, 0)
		body.add_child(collision)
		collision_nodes.append(collision)
	var collision_us := Time.get_ticks_usec()
	print("CHUNKS=%d GPU_TO_CPU_MS=%.3f COLLISION_REPLACE_MS=%.3f" % [
		count, float(callback_us - request_us) / 1000.0,
		float(collision_us - collision_start) / 1000.0])
	completed_cases += 1
	if count == 16:
		call_deferred("_validate_collision_ray", request_us)
	else:
		RenderingServer.call_on_render_thread(_release_staging_and_next.bind(count * 4))


func _validate_collision_ray(start_us: int) -> void:
	await physics_frame
	await physics_frame
	var query := PhysicsRayQueryParameters3D.create(Vector3(0, 10, 0), Vector3(0, -10, 0))
	var hit: Dictionary = root.world_3d.direct_space_state.intersect_ray(query)
	if not hit.has("position"):
		_fail("collision ray missed the new heightmap")
		return
	var hit_height: float = hit.position.y
	if hit_height < 0.20 or hit_height > 1.10:
		_fail("collision ray height outside computed range: %f" % hit_height)
		return
	print("CHUNKS=16 GPU_TO_RAY_MS=%.3f RAY_HEIGHT=%.3f" % [
		float(Time.get_ticks_usec() - start_us) / 1000.0, hit_height])
	finished = true
	print("PASS: packed 1/4/16 dirty chunks from 256² GPU state into HeightMapShape3D")
	RenderingServer.call_on_render_thread(_release)
	quit(0)


func _release_staging_and_next(next_count: int) -> void:
	if pack_set.is_valid():
		rd.free_rid(pack_set)
	if staging_texture.is_valid():
		rd.free_rid(staging_texture)
	pack_set = RID()
	staging_texture = RID()
	_run_case(next_count)


func _release() -> void:
	if rd == null:
		return
	for rid in [pack_set, staging_texture, source_set, source_texture,
			source_pipeline, pack_pipeline, source_shader, pack_shader]:
		if rid.is_valid():
			rd.free_rid(rid)


func _watchdog() -> void:
	if finished:
		return
	watchdog_frames += 1
	if watchdog_frames > 300:
		_fail("GPU async callback timeout")
		return
	await process_frame
	call_deferred("_watchdog")


func _fail(message: String) -> void:
	if finished:
		return
	finished = true
	printerr("FAIL: dirty chunk probe: " + message)
	RenderingServer.call_on_render_thread(_release)
	quit(1)

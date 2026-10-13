extends SceneTree

const SIZE := 64
const CENTER := Vector2i(32, 32)

var spirv: RDShaderSPIRV
var rd: RenderingDevice
var resources: Array[RID] = []
var shader_rid := RID()
var pipeline_rid := RID()
var uniform_set_rid := RID()
var finished := false
var frames_waited := 0


func _init() -> void:
	call_deferred("_begin")


func _begin() -> void:
	var shader_file: RDShaderFile = load("res://shaders/simulation/shallow_drain_scale.glsl")
	if shader_file == null:
		_fail("drain shader import missing")
		return
	spirv = shader_file.get_spirv()
	if spirv == null:
		_fail("drain SPIR-V missing")
		return
	RenderingServer.call_on_render_thread(_render_probe)
	call_deferred("_watchdog")


func _render_probe() -> void:
	rd = RenderingServer.get_rendering_device()
	if rd == null:
		call_deferred("_fail", "main RD unavailable")
		return
	var water := PackedFloat32Array()
	var edge_x := PackedFloat32Array()
	var edge_z := PackedFloat32Array()
	water.resize(SIZE * SIZE)
	edge_x.resize(SIZE * SIZE * 4)
	edge_z.resize(SIZE * SIZE * 4)
	water.fill(0.0)
	edge_x.fill(0.0)
	edge_z.fill(0.0)
	var i := CENTER.y * SIZE + CENTER.x
	water[i] = 0.2
	edge_x[i * 4] = 0.3
	edge_x[(i - 1) * 4] = -0.2
	edge_z[i * 4] = 0.4
	edge_z[(i - SIZE) * 4] = -0.1
	resources.append(_create_texture(RenderingDevice.DATA_FORMAT_R32_SFLOAT, water.to_byte_array()))
	resources.append(_create_texture(RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT, edge_x.to_byte_array()))
	resources.append(_create_texture(RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT, edge_z.to_byte_array()))
	resources.append(_create_texture(RenderingDevice.DATA_FORMAT_R32_SFLOAT, PackedByteArray()))
	for rid in resources:
		if not rid.is_valid():
			call_deferred("_fail", "drain texture creation failed")
			return
	shader_rid = rd.shader_create_from_spirv(spirv)
	if not shader_rid.is_valid():
		call_deferred("_fail", "drain shader creation failed")
		return
	pipeline_rid = rd.compute_pipeline_create(shader_rid)
	if not pipeline_rid.is_valid():
		call_deferred("_fail", "drain pipeline creation failed")
		return
	var uniforms: Array[RDUniform] = []
	for binding in resources.size():
		var uniform := RDUniform.new()
		uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		uniform.binding = binding
		uniform.add_id(resources[binding])
		uniforms.append(uniform)
	uniform_set_rid = rd.uniform_set_create(uniforms, shader_rid, 0)
	if not uniform_set_rid.is_valid():
		call_deferred("_fail", "drain uniform creation failed")
		return
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline_rid)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set_rid, 0)
	var push := PackedFloat32Array([0.5, 0.0, 0.0, 0.0]).to_byte_array()
	rd.compute_list_set_push_constant(compute_list, push, push.size())
	rd.compute_list_dispatch(compute_list, SIZE / 8, SIZE / 8, 1)
	rd.compute_list_end()
	var error := rd.texture_get_data_async(resources[3], 0, _on_data)
	if error != OK:
		call_deferred("_fail", "drain readback failed %d" % error)


func _create_texture(format_id: int, data: PackedByteArray) -> RID:
	var format := RDTextureFormat.new()
	format.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	format.width = SIZE
	format.height = SIZE
	format.format = format_id
	format.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	return rd.texture_create(format, RDTextureView.new(), [data]) if not data.is_empty() else rd.texture_create(format, RDTextureView.new())


func _on_data(data: PackedByteArray) -> void:
	call_deferred("_verify", data)


func _verify(data: PackedByteArray) -> void:
	if finished:
		return
	if data.size() != SIZE * SIZE * 4:
		_fail("drain byte count mismatch")
		return
	var values := data.to_float32_array()
	var center_i := CENTER.y * SIZE + CENTER.x
	var expected := 0.2 / (0.5 * (0.3 + 0.2 + 0.4 + 0.1))
	if absf(values[center_i] - expected) > 0.000001 or absf(values[center_i + 1] - 1.0) > 0.000001:
		_fail("four-face outflow scale mismatch center=%f neighbor=%f" % [values[center_i], values[center_i + 1]])
		return
	print("PASS: GPU four-face positivity scale=%.6f expected=%.6f" % [values[center_i], expected])
	finished = true
	RenderingServer.call_on_render_thread(_release_success)


func _release_success() -> void:
	_release()
	call_deferred("_finish", 0)


func _watchdog() -> void:
	if finished:
		return
	frames_waited += 1
	if frames_waited > 300:
		_fail("drain callback timed out")
		return
	await process_frame
	call_deferred("_watchdog")


func _fail(message: String) -> void:
	if finished:
		return
	finished = true
	printerr("FAIL: " + message)
	RenderingServer.call_on_render_thread(_release_failure)


func _release_failure() -> void:
	_release()
	call_deferred("_finish", 1)


func _release() -> void:
	if rd == null:
		return
	if uniform_set_rid.is_valid():
		rd.free_rid(uniform_set_rid)
	if pipeline_rid.is_valid():
		rd.free_rid(pipeline_rid)
	if shader_rid.is_valid():
		rd.free_rid(shader_rid)
	for rid in resources:
		if rid.is_valid():
			rd.free_rid(rid)


func _finish(code: int) -> void:
	quit(code)

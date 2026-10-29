extends CompositorEffect

const SIZE := 32

var target_texture: Texture2DRD
var mutex := Mutex.new()
var requested_value := 0.05
var dispatched_value := -1.0
var dispatch_count := 0
var rd: RenderingDevice
var texture_rid := RID()
var shader_rid := RID()
var pipeline_rid := RID()
var set_rid := RID()
var spirv: RDShaderSPIRV


func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_PRE_OPAQUE
	var shader_file: RDShaderFile = load("res://shaders/benchmarks/frame_value_compute.glsl")
	if shader_file != null:
		spirv = shader_file.get_spirv()


func request_value(value: float) -> void:
	mutex.lock()
	requested_value = value
	mutex.unlock()


func last_dispatch() -> Dictionary:
	mutex.lock()
	var result := {"value": dispatched_value, "count": dispatch_count}
	mutex.unlock()
	return result


func _render_callback(callback_type: int, _render_data: RenderData) -> void:
	if callback_type != EFFECT_CALLBACK_TYPE_PRE_OPAQUE or target_texture == null:
		return
	if not texture_rid.is_valid():
		_setup()
	if not set_rid.is_valid():
		return
	mutex.lock()
	var value := requested_value
	mutex.unlock()
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline_rid)
	rd.compute_list_bind_uniform_set(compute_list, set_rid, 0)
	var params := PackedFloat32Array([value, 0.0, 0.0, 0.0]).to_byte_array()
	rd.compute_list_set_push_constant(compute_list, params, params.size())
	rd.compute_list_dispatch(compute_list, SIZE / 8, SIZE / 8, 1)
	rd.compute_list_end()
	mutex.lock()
	dispatched_value = value
	dispatch_count += 1
	mutex.unlock()


func _setup() -> void:
	rd = RenderingServer.get_rendering_device()
	if rd == null or spirv == null:
		return
	var format := RDTextureFormat.new()
	format.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	format.width = SIZE
	format.height = SIZE
	format.format = RenderingDevice.DATA_FORMAT_R32_SFLOAT
	format.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	texture_rid = rd.texture_create(format, RDTextureView.new())
	shader_rid = rd.shader_create_from_spirv(spirv)
	if not texture_rid.is_valid() or not shader_rid.is_valid():
		return
	pipeline_rid = rd.compute_pipeline_create(shader_rid)
	var uniform := RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	uniform.binding = 0
	uniform.add_id(texture_rid)
	set_rid = rd.uniform_set_create([uniform], shader_rid, 0)
	if pipeline_rid.is_valid() and set_rid.is_valid():
		target_texture.texture_rd_rid = texture_rid


func release() -> void:
	if target_texture != null:
		target_texture.texture_rd_rid = RID()
	if rd != null:
		for rid in [set_rid, pipeline_rid, shader_rid, texture_rid]:
			if rid.is_valid():
				rd.free_rid(rid)
	set_rid = RID()
	pipeline_rid = RID()
	shader_rid = RID()
	texture_rid = RID()

extends SceneTree

var rd: RenderingDevice
var texture := RID()
var shader := RID()
var pipeline := RID()
var uniforms := RID()
var wrapper := Texture2DRD.new()
var submitted := false
var read_done := false
var bytes := PackedByteArray()
var scene: Node3D
var output := "res://test_output/gpu_gravel/texture_probe_" + str(Time.get_unix_time_from_system()).replace(".", "_")
var error := ""

func _initialize() -> void:
	_run.call_deferred()

func _setup() -> void:
	rd = RenderingServer.get_rendering_device()
	var format := RDTextureFormat.new()
	format.width = 64
	format.height = 16
	format.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	format.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	var initial := PackedFloat32Array()
	initial.resize(64 * 16 * 4)
	initial.fill(0.0)
	initial[0] = -1.4
	initial[1] = 0.275
	texture = rd.texture_create(format, RDTextureView.new(), [initial.to_byte_array()])
	var source := RDShaderSource.new()
	source.source_compute = """#version 450
layout(local_size_x=1,local_size_y=1,local_size_z=1) in;
layout(rgba32f,set=0,binding=0) uniform image2D state;
void main() { imageStore(state, ivec2(0), vec4(1.4,0.275,0.0,1.0)); }
"""
	var spirv := rd.shader_compile_spirv_from_source(source)
	error = spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
	if not error.is_empty():
		submitted = true
		return
	shader = rd.shader_create_from_spirv(spirv)
	pipeline = rd.compute_pipeline_create(shader)
	var uniform := RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	uniform.binding = 0
	uniform.add_id(texture)
	uniforms = rd.uniform_set_create([uniform], shader, 0)
	wrapper.texture_rd_rid = texture
	submitted = true

func _move() -> void:
	var list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list, pipeline)
	rd.compute_list_bind_uniform_set(list, uniforms, 0)
	rd.compute_list_dispatch(list, 1, 1, 1)
	rd.compute_list_end()
	var result := rd.texture_get_data_async(texture, 0, _readback)
	if result != OK:
		error = "readback request: " + str(result)
		read_done = true

func _readback(data: PackedByteArray) -> void:
	bytes = data
	read_done = true

func _release() -> void:
	for rid in [uniforms, pipeline, shader, texture]:
		if rid.is_valid(): rd.free_rid(rid)
	submitted = true

func _frames(count: int) -> void:
	for i in count:
		await process_frame
		await RenderingServer.frame_post_draw

func _run() -> void:
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	scene = load("res://tests/gravel/gravel_texture_probe.tscn").instantiate()
	root.add_child(scene)
	RenderingServer.call_on_render_thread(_setup)
	while not submitted: await process_frame
	if not error.is_empty(): print(error); quit(1); return
	scene.get_node("Gravel").multimesh.mesh.material.set_shader_parameter("particle_state", wrapper)
	await _frames(8)
	root.get_texture().get_image().save_png(output.path_join("before.png"))
	RenderingServer.call_on_render_thread(_move)
	var deadline := Time.get_ticks_msec() + 10000
	while not read_done and Time.get_ticks_msec() < deadline: await process_frame
	await _frames(8)
	root.get_texture().get_image().save_png(output.path_join("after.png"))
	var values := bytes.to_float32_array()
	var ok := error.is_empty() and values.size() == 4096 and absf(values[0] - 1.4) < 0.000001 and absf(values[1] - 0.275) < 0.000001 and values[3] == 1.0
	var report := {"numeric_pass": ok, "error": error, "gpu": RenderingServer.get_video_adapter_name(), "driver": RenderingServer.get_current_rendering_driver_name(), "method": RenderingServer.get_current_rendering_method(), "window": [root.size.x,root.size.y], "before_position": [-1.4,0.275,0], "after_position": Array(values.slice(0,4)), "version": Engine.get_version_info(), "screenshots_require_visual_review": true}
	FileAccess.open(output.path_join("result.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("GRAVEL_TEXTURE_PROBE ", JSON.stringify(report), " OUTPUT ", output)
	wrapper.texture_rd_rid = RID()
	scene.queue_free()
	await _frames(2)
	submitted = false
	RenderingServer.call_on_render_thread(_release)
	while not submitted: await process_frame
	quit(0 if ok else 1)

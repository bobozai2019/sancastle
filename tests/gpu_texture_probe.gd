extends SceneTree

const WIDTH := 32
const EXPECTED_BYTES := WIDTH * WIDTH * 4

var rd_texture: Texture2DRD
var spirv: RDShaderSPIRV
var rd: RenderingDevice
var texture_rid := RID()
var shader_rid := RID()
var pipeline_rid := RID()
var uniform_set_rid := RID()
var did_finish := false
var readback_valid := false
var frames_waited := 0


func _init() -> void:
	call_deferred("_begin")


func _begin() -> void:
	var shader_file: RDShaderFile = load("res://shaders/benchmarks/checker_compute.glsl")
	if shader_file == null:
		_fail("compute shader did not import")
		return
	spirv = shader_file.get_spirv()
	if spirv == null:
		_fail("compute SPIR-V unavailable")
		return
	rd_texture = Texture2DRD.new()
	var display_shader: Shader = load("res://shaders/benchmarks/checker_display.gdshader")
	var material := ShaderMaterial.new()
	material.shader = display_shader
	material.set_shader_parameter("state_texture", rd_texture)
	var plane := MeshInstance3D.new()
	plane.mesh = PlaneMesh.new()
	plane.scale = Vector3(4, 1, 4)
	plane.material_override = material
	root.add_child(plane)
	var camera := Camera3D.new()
	camera.position = Vector3(0, 5, 0)
	root.add_child(camera)
	camera.look_at(Vector3.ZERO, Vector3(0, 0, -1))
	camera.current = true
	RenderingServer.call_on_render_thread(_create_and_dispatch)
	call_deferred("_watchdog")


func _create_and_dispatch() -> void:
	rd = RenderingServer.get_rendering_device()
	if rd == null:
		call_deferred("_fail", "main RenderingDevice unavailable")
		return
	var format := RDTextureFormat.new()
	format.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	format.width = WIDTH
	format.height = WIDTH
	format.format = RenderingDevice.DATA_FORMAT_R32_SFLOAT
	format.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	texture_rid = rd.texture_create(format, RDTextureView.new())
	if not texture_rid.is_valid():
		call_deferred("_fail", "R32F storage texture creation failed")
		return
	shader_rid = rd.shader_create_from_spirv(spirv)
	if not shader_rid.is_valid():
		call_deferred("_fail", "compute shader creation failed")
		return
	pipeline_rid = rd.compute_pipeline_create(shader_rid)
	if not pipeline_rid.is_valid():
		call_deferred("_fail", "compute pipeline creation failed")
		return
	var uniform := RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	uniform.binding = 0
	uniform.add_id(texture_rid)
	uniform_set_rid = rd.uniform_set_create([uniform], shader_rid, 0)
	if not uniform_set_rid.is_valid():
		call_deferred("_fail", "uniform set creation failed")
		return
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline_rid)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set_rid, 0)
	rd.compute_list_dispatch(compute_list, WIDTH / 8, WIDTH / 8, 1)
	rd.compute_list_end()
	rd_texture.texture_rd_rid = texture_rid
	var err := rd.texture_get_data_async(texture_rid, 0, _on_texture_data)
	if err != OK:
		call_deferred("_fail", "async texture read request failed: %d" % err)


func _on_texture_data(data: PackedByteArray) -> void:
	call_deferred("_verify", data)


func _verify(data: PackedByteArray) -> void:
	if did_finish:
		return
	if data.size() != EXPECTED_BYTES:
		_fail("wrong byte count: %d" % data.size())
		return
	var values := data.to_float32_array()
	if absf(values[0] - 1.0) > 0.01 or absf(values[8] - 0.25) > 0.01:
		_fail("compute output mismatch: %f, %f" % [values[0], values[8]])
		return
	readback_valid = true
	print("PASS: main RD compute and async R32F readback")
	call_deferred("_capture_after_frames")


func _capture_after_frames() -> void:
	for _frame in 8:
		await process_frame
	if did_finish:
		return
	var screenshot := root.get_texture().get_image()
	if screenshot == null or screenshot.is_empty():
		_fail("rendered viewport image unavailable")
		return
	var screenshot_path := "res://test_output/sandcastle_water_sand_coupling/验收/GPU_checker_20260928.png"
	var save_error := screenshot.save_png(screenshot_path)
	if save_error != OK:
		_fail("screenshot save failed: %d" % save_error)
		return
	var center := screenshot.get_pixel(screenshot.get_width() / 2, screenshot.get_height() / 2)
	if center.r < 0.1:
		_fail("display material appears black at center: %s" % center)
		return
	did_finish = true
	print("PASS: Texture2DRD material display; screenshot %s; center %s" % [screenshot_path, center])
	RenderingServer.call_on_render_thread(_release)
	quit(0)


func _watchdog() -> void:
	if did_finish:
		return
	frames_waited += 1
	if frames_waited > 300:
		_fail("GPU callback timed out")
		return
	await process_frame
	call_deferred("_watchdog")


func _release() -> void:
	rd_texture.texture_rd_rid = RID()
	for rid in [uniform_set_rid, pipeline_rid, shader_rid, texture_rid]:
		if rid.is_valid():
			rd.free_rid(rid)


func _fail(message: String) -> void:
	if did_finish:
		return
	did_finish = true
	printerr("FAIL: GPU probe: " + message)
	RenderingServer.call_on_render_thread(_release)
	quit(1)

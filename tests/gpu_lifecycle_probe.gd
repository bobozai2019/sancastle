extends SceneTree

const DEFAULT_CYCLES := 50
const WIDTH := 32
const EXPECTED_BYTES := WIDTH * WIDTH * 4

var shader_spirv: RDShaderSPIRV
var display_shader: Shader
var rd: RenderingDevice
var plane: MeshInstance3D
var rd_texture: Texture2DRD
var texture_rid := RID()
var shader_rid := RID()
var pipeline_rid := RID()
var uniform_set_rid := RID()
var cycle := 0
var cycle_target := DEFAULT_CYCLES
var frames_waited := 0
var finished := false
var initial_static_bytes := 0
var initial_video_bytes := 0
var memory_rows: PackedStringArray = PackedStringArray()
const MEMORY_CSV_FORMAT := "res://test_output/sandcastle_water_sand_coupling/验收/T00_gpu_lifecycle_memory_%d_cycles.csv"


func _init() -> void:
	call_deferred("_begin")


func _begin() -> void:
	var requested_cycles := int(OS.get_environment("SANDCASTLE_LIFECYCLE_CYCLES"))
	if requested_cycles > 0:
		cycle_target = requested_cycles
	var shader_file: RDShaderFile = load("res://shaders/benchmarks/checker_compute.glsl")
	display_shader = load("res://shaders/benchmarks/checker_display.gdshader")
	if shader_file == null or display_shader == null:
		_fail("shader import failed")
		return
	shader_spirv = shader_file.get_spirv()
	if shader_spirv == null:
		_fail("SPIR-V unavailable")
		return
	var camera := Camera3D.new()
	camera.position = Vector3(0, 5, 0)
	root.add_child(camera)
	camera.look_at(Vector3(0, 0, -1))
	camera.current = true
	initial_static_bytes = int(Performance.get_monitor(Performance.MEMORY_STATIC))
	initial_video_bytes = int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED))
	memory_rows.append("cycle,static_bytes,video_bytes")
	_start_cycle()
	call_deferred("_watchdog")


func _start_cycle() -> void:
	if finished:
		return
	rd_texture = Texture2DRD.new()
	var material := ShaderMaterial.new()
	material.shader = display_shader
	material.set_shader_parameter("state_texture", rd_texture)
	plane = MeshInstance3D.new()
	plane.mesh = PlaneMesh.new()
	plane.scale = Vector3(4, 1, 4)
	plane.material_override = material
	root.add_child(plane)
	RenderingServer.call_on_render_thread(_render_cycle)


func _render_cycle() -> void:
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
	shader_rid = rd.shader_create_from_spirv(shader_spirv)
	if not texture_rid.is_valid() or not shader_rid.is_valid():
		call_deferred("_fail", "texture/shader creation failed at cycle %d" % cycle)
		return
	pipeline_rid = rd.compute_pipeline_create(shader_rid)
	if not pipeline_rid.is_valid():
		call_deferred("_fail", "pipeline creation failed at cycle %d" % cycle)
		return
	var uniform := RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	uniform.binding = 0
	uniform.add_id(texture_rid)
	uniform_set_rid = rd.uniform_set_create([uniform], shader_rid, 0)
	if not uniform_set_rid.is_valid():
		call_deferred("_fail", "uniform set creation failed at cycle %d" % cycle)
		return
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline_rid)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set_rid, 0)
	rd.compute_list_dispatch(compute_list, WIDTH / 8, WIDTH / 8, 1)
	rd.compute_list_end()
	rd_texture.texture_rd_rid = texture_rid
	var error := rd.texture_get_data_async(texture_rid, 0, _on_data)
	if error != OK:
		call_deferred("_fail", "readback request failed at cycle %d: %d" % [cycle, error])


func _on_data(data: PackedByteArray) -> void:
	if data.size() != EXPECTED_BYTES:
		call_deferred("_fail", "wrong byte count at cycle %d" % cycle)
		return
	var values := data.to_float32_array()
	if absf(values[0] - 1.0) > 0.01 or absf(values[8] - 0.25) > 0.01:
		call_deferred("_fail", "compute mismatch at cycle %d" % cycle)
		return
	call_deferred("_finish_cycle")


func _finish_cycle() -> void:
	if finished:
		return
	plane.queue_free()
	plane = null
	for _frame in 3:
		await process_frame
	RenderingServer.call_on_render_thread(_release_cycle)


func _release_cycle() -> void:
	rd_texture.texture_rd_rid = RID()
	_release_rids()
	call_deferred("_after_release")


func _after_release() -> void:
	rd_texture = null
	cycle += 1
	frames_waited = 0
	var static_bytes := int(Performance.get_monitor(Performance.MEMORY_STATIC))
	var video_bytes := int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED))
	memory_rows.append("%d,%d,%d" % [cycle, static_bytes, video_bytes])
	if cycle % 10 == 0:
		print("LIFECYCLE completed=%d/%d static_memory=%d video_memory=%d" % [
			cycle, cycle_target, static_bytes, video_bytes])
	if cycle == cycle_target:
		var file := FileAccess.open(MEMORY_CSV_FORMAT % cycle_target, FileAccess.WRITE)
		if file == null:
			_fail("memory CSV unavailable")
			return
		file.store_string("\n".join(memory_rows) + "\n")
		file.close()
		finished = true
		print("LIFECYCLE static_memory_initial=%d final=%d delta=%d" % [initial_static_bytes, static_bytes, static_bytes - initial_static_bytes])
		print("LIFECYCLE video_memory_initial=%d final=%d delta=%d" % [initial_video_bytes, video_bytes, video_bytes - initial_video_bytes])
		print("PASS: %d main-RD compute/readback and scene rebuild cycles" % cycle_target)
		quit(0)
		return
	await process_frame
	_start_cycle()


func _watchdog() -> void:
	if finished:
		return
	frames_waited += 1
	if frames_waited > 300:
		_fail("cycle %d timed out" % cycle)
		return
	await process_frame
	call_deferred("_watchdog")


func _release_rids() -> void:
	for rid in [uniform_set_rid, pipeline_rid, shader_rid, texture_rid]:
		if rid.is_valid():
			rd.free_rid(rid)
	uniform_set_rid = RID()
	pipeline_rid = RID()
	shader_rid = RID()
	texture_rid = RID()


func _fail(message: String) -> void:
	if finished:
		return
	finished = true
	printerr("FAIL: GPU lifecycle: " + message)
	if plane != null:
		plane.queue_free()
	RenderingServer.call_on_render_thread(_release_rids)
	quit(1)

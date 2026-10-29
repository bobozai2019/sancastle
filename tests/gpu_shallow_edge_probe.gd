extends SceneTree

const Domain = preload("res://scripts/simulation/sand_water_domain.gd")
const SIZE := 64

var case_name := "dam_break"
var spirv: RDShaderSPIRV
var rd: RenderingDevice
var resources: Array[RID] = []
var shader_rid := RID()
var pipeline_rid := RID()
var uniform_set_rid := RID()
var edge_x_rid := RID()
var edge_z_rid := RID()
var x_data := PackedByteArray()
var z_data := PackedByteArray()
var finished := false
var frames_waited := 0


func _init() -> void:
	call_deferred("_begin")


func _begin() -> void:
	var requested := OS.get_environment("SANDCASTLE_EDGE_CASE")
	if not requested.is_empty():
		case_name = requested
	if case_name not in ["dam_break", "sloping_lake", "wall"]:
		_fail("unknown edge case")
		return
	var shader_file: RDShaderFile = load("res://shaders/simulation/shallow_edge_flux.glsl")
	if shader_file == null:
		_fail("edge flux shader import missing")
		return
	spirv = shader_file.get_spirv()
	if spirv == null:
		_fail("edge flux SPIR-V missing")
		return
	RenderingServer.call_on_render_thread(_render_case)
	call_deferred("_watchdog")


func _render_case() -> void:
	rd = RenderingServer.get_rendering_device()
	if rd == null:
		call_deferred("_fail", "main RD missing")
		return
	var domain = Domain.new(SIZE, 0.125)
	for z in SIZE:
		for x in SIZE:
			var i: int = domain.index(x, z)
			match case_name:
				"dam_break":
					domain.water[i] = 0.45 if x < SIZE / 2 else 0.0
				"sloping_lake":
					domain.rock[i] = 0.2 * float(x) / float(SIZE - 1) + 0.04 * float(z) / float(SIZE - 1)
					domain.water[i] = 0.5 - domain.rock[i]
				"wall":
					domain.water[i] = 0.45 if x < SIZE / 2 else 0.0
					if x == SIZE / 2:
						domain.obstacle[i] = 1.0
	var zero := PackedFloat32Array()
	zero.resize(SIZE * SIZE)
	zero.fill(0.0)
	var obstacle_bytes := PackedByteArray()
	obstacle_bytes.resize(SIZE * SIZE)
	for i in domain.obstacle.size():
		obstacle_bytes[i] = 255 if domain.obstacle[i] >= 0.5 else 0
	for field in [domain.rock, domain.sand, domain.water, zero, zero]:
		resources.append(_create_texture(RenderingDevice.DATA_FORMAT_R32_SFLOAT, field.to_byte_array()))
	resources.append(_create_texture(RenderingDevice.DATA_FORMAT_R8_UNORM, obstacle_bytes))
	edge_x_rid = _create_texture(RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT, PackedByteArray())
	edge_z_rid = _create_texture(RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT, PackedByteArray())
	resources.append(edge_x_rid)
	resources.append(edge_z_rid)
	for rid in resources:
		if not rid.is_valid():
			call_deferred("_fail", "edge texture creation failed")
			return
	shader_rid = rd.shader_create_from_spirv(spirv)
	if not shader_rid.is_valid():
		call_deferred("_fail", "edge shader creation failed")
		return
	pipeline_rid = rd.compute_pipeline_create(shader_rid)
	if not pipeline_rid.is_valid():
		call_deferred("_fail", "edge pipeline creation failed")
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
		call_deferred("_fail", "edge uniform set creation failed")
		return
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline_rid)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set_rid, 0)
	rd.compute_list_dispatch(compute_list, SIZE / 8, SIZE / 8, 1)
	rd.compute_list_end()
	var err_x := rd.texture_get_data_async(edge_x_rid, 0, _on_x_data)
	var err_z := rd.texture_get_data_async(edge_z_rid, 0, _on_z_data)
	if err_x != OK or err_z != OK:
		call_deferred("_fail", "edge readback requests failed %d/%d" % [err_x, err_z])


func _create_texture(format_id: int, data: PackedByteArray) -> RID:
	var format := RDTextureFormat.new()
	format.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	format.width = SIZE
	format.height = SIZE
	format.format = format_id
	format.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	return rd.texture_create(format, RDTextureView.new(), [data]) if not data.is_empty() else rd.texture_create(format, RDTextureView.new())


func _on_x_data(data: PackedByteArray) -> void:
	call_deferred("_record_data", true, data)


func _on_z_data(data: PackedByteArray) -> void:
	call_deferred("_record_data", false, data)


func _record_data(is_x: bool, data: PackedByteArray) -> void:
	if finished:
		return
	if is_x:
		x_data = data
	else:
		z_data = data
	if not x_data.is_empty() and not z_data.is_empty():
		_verify()


func _verify() -> void:
	if x_data.size() != SIZE * SIZE * 16 or z_data.size() != SIZE * SIZE * 16:
		_fail("edge readback byte count mismatch")
		return
	var fx := x_data.to_float32_array()
	var fz := z_data.to_float32_array()
	var interface_offset := (32 * SIZE + 31) * 4
	var expected_mass := 0.5 * sqrt(9.81 * 0.45) * 0.45
	var expected_momentum := 0.25 * 9.81 * 0.45 * 0.45
	match case_name:
		"dam_break":
			if absf(fx[interface_offset] - expected_mass) > 0.0001 or \
					absf(fx[interface_offset + 1] - expected_momentum) > 0.0001:
				_fail("dam-break edge flux disagrees with CPU formula: %f/%f" % [fx[interface_offset], fx[interface_offset + 1]])
				return
		"wall":
			if absf(fx[interface_offset]) > 0.000001 or absf(fx[interface_offset + 1]) > 0.000001:
				_fail("blocked edge leaked water or momentum")
				return
		"sloping_lake":
			var maximum_mass := 0.0
			for i in SIZE * SIZE:
				maximum_mass = maxf(maximum_mass, maxf(absf(fx[i * 4]), absf(fz[i * 4])))
			if maximum_mass > 0.00001:
				_fail("sloping still lake has spontaneous mass flux %.8f" % maximum_mass)
				return
	print("PASS: GPU edge flux %s 64-square shared-edge check" % case_name)
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
		_fail("edge readback callback timed out")
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

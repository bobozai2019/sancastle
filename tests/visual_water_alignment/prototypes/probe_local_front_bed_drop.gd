extends SceneTree

# Execute the two local-front compute passes on controlled bed/depth changes.
# A bed drop with constant eta must not create an advancing front.
const GRID := 256
const CELLS := GRID * GRID
const X_SHADER := "res://tests/visual_water_alignment/prototypes/reference_local_front_x.glsl"
const Z_SHADER := "res://tests/visual_water_alignment/prototypes/reference_local_front_z.glsl"

var output_dir := ""
var x_shader_path := X_SHADER
var rd: RenderingDevice
var x_shader := RID()
var z_shader := RID()
var x_pipeline := RID()
var z_pipeline := RID()
var textures: Array[RID] = []
var uniform_sets: Array[RID] = []
var received := {}
var finished := false


func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			output_dir = arg.trim_prefix("--output=")
		elif arg.begins_with("--x-shader="):
			x_shader_path = arg.trim_prefix("--x-shader=")
	call_deferred("_begin")


func _begin() -> void:
	if output_dir.is_empty() or not DirAccess.dir_exists_absolute(output_dir):
		_fail("existing output directory required")
		return
	var x_file: RDShaderFile = load(x_shader_path)
	var z_file: RDShaderFile = load(Z_SHADER)
	if x_file == null or z_file == null or x_file.get_spirv() == null or \
			z_file.get_spirv() == null:
		_fail("local-front shader import missing")
		return
	RenderingServer.call_on_render_thread(_run_gpu.bind(
		x_file.get_spirv(), z_file.get_spirv()))
	call_deferred("_watchdog")


func _format(channels: int) -> RDTextureFormat:
	var format := RDTextureFormat.new()
	format.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	format.width = GRID
	format.height = GRID
	format.format = RenderingDevice.DATA_FORMAT_R32_SFLOAT if channels == 1 else \
		RenderingDevice.DATA_FORMAT_R32G32_SFLOAT if channels == 2 else \
		RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	format.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | \
		RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | \
		RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	return format


func _texture(values: PackedFloat32Array, channels: int) -> RID:
	var rid := rd.texture_create(_format(channels), RDTextureView.new(),
		[values.to_byte_array()])
	textures.append(rid)
	return rid


func _constant(value: float, channels: int) -> RID:
	var values := PackedFloat32Array()
	values.resize(CELLS * channels)
	values.fill(value)
	return _texture(values, channels)


func _uniform_set(ids: Array[RID], shader: RID) -> RID:
	var uniforms: Array[RDUniform] = []
	for binding in ids.size():
		var uniform := RDUniform.new()
		uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		uniform.binding = binding
		uniform.add_id(ids[binding])
		uniforms.append(uniform)
	var set_rid := rd.uniform_set_create(uniforms, shader, 0)
	uniform_sets.append(set_rid)
	return set_rid


func _run_gpu(x_spirv: RDShaderSPIRV, z_spirv: RDShaderSPIRV) -> void:
	rd = RenderingServer.get_rendering_device()
	if rd == null:
		call_deferred("_fail", "main RenderingDevice missing")
		return
	x_shader = rd.shader_create_from_spirv(x_spirv)
	z_shader = rd.shader_create_from_spirv(z_spirv)
	if not x_shader.is_valid() or not z_shader.is_valid():
		call_deferred("_fail", "shader RID invalid")
		return
	x_pipeline = rd.compute_pipeline_create(x_shader)
	z_pipeline = rd.compute_pipeline_create(z_shader)
	if not x_pipeline.is_valid() or not z_pipeline.is_valid():
		call_deferred("_fail", "pipeline RID invalid")
		return
	for scenario in [
			{"name": "steady", "bed": 0.10, "depth": 0.10},
			{"name": "bed_drop", "bed": 0.08, "depth": 0.12},
			{"name": "eta_rise", "bed": 0.10, "depth": 0.12}]:
		if not _dispatch_case(scenario):
			return


func _dispatch_case(scenario: Dictionary) -> bool:
	var history := PackedFloat32Array()
	history.resize(CELLS * 2)
	for cell in CELLS:
		history[cell * 2 + 1] = 0.10
	var water := _constant(float(scenario.depth), 1)
	var previous := _texture(history, 2)
	var x_out := _constant(0.0, 4)
	var rock := _constant(0.0, 1)
	var sand := _constant(float(scenario.bed), 1)
	var previous_bed := _constant(0.10, 1)
	var result := _constant(0.0, 2)
	var x_set := _uniform_set([water, previous, x_out, rock, sand,
		previous_bed], x_shader)
	var z_set := _uniform_set([x_out, result], z_shader)
	if not x_set.is_valid() or not z_set.is_valid():
		call_deferred("_fail", "uniform set invalid")
		return false
	var x_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(x_list, x_pipeline)
	rd.compute_list_bind_uniform_set(x_list, x_set, 0)
	rd.compute_list_dispatch(x_list, 32, 32, 1)
	rd.compute_list_end()
	var z_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(z_list, z_pipeline)
	rd.compute_list_bind_uniform_set(z_list, z_set, 0)
	rd.compute_list_dispatch(z_list, 32, 32, 1)
	rd.compute_list_end()
	var error := rd.texture_get_data_async(result, 0,
		_on_data.bind(String(scenario.name)))
	if error != OK:
		call_deferred("_fail", "readback failed: " + str(error))
		return false
	return true


func _on_data(data: PackedByteArray, name: String) -> void:
	call_deferred("_receive", data, name)


func _receive(data: PackedByteArray, name: String) -> void:
	if finished:
		return
	if data.size() != CELLS * 8:
		_fail("wrong result size for " + name)
		return
	received[name] = data
	if received.size() < 3:
		return
	var center := (128 * GRID + 128) * 2 + 1
	var peaks := {}
	for key in ["steady", "bed_drop", "eta_rise"]:
		if not received.has(key):
			_fail("missing scenario " + key)
			return
		var values: PackedFloat32Array = received[key].to_float32_array()
		peaks[key] = values[center]
		var file := FileAccess.open(output_dir.path_join(
			"%s_local_front_rg32f.bin" % key), FileAccess.WRITE)
		if file == null:
			_fail("output open failed for " + key)
			return
		file.store_buffer(received[key])
		file.close()
	var manifest := {"x_shader": x_shader_path, "z_shader": Z_SHADER,
		"x_sha256": FileAccess.get_sha256(x_shader_path),
		"z_sha256": FileAccess.get_sha256(Z_SHADER),
		"grid_size": GRID, "center_peak": peaks,
		"scenarios": {"steady": [0.10, 0.10],
			"bed_drop": [0.08, 0.12], "eta_rise": [0.10, 0.12]},
		"adapter": RenderingServer.get_video_adapter_name()}
	var manifest_file := FileAccess.open(output_dir.path_join(
		"synthetic_local_front_manifest.json"), FileAccess.WRITE)
	if manifest_file == null:
		_fail("manifest open failed")
		return
	manifest_file.store_string(JSON.stringify(manifest, "\t"))
	manifest_file.close()
	if absf(peaks.steady) > 1e-7 or absf(peaks.bed_drop) > 1e-7 or \
			peaks.eta_rise < 0.019:
		_fail("free-surface synthetic cases failed: " + str(peaks))
		return
	finished = true
	RenderingServer.call_on_render_thread(_cleanup)


func _cleanup() -> void:
	for set_rid in uniform_sets:
		if set_rid.is_valid():
			rd.free_rid(set_rid)
	for texture in textures:
		if texture.is_valid():
			rd.free_rid(texture)
	for rid in [x_pipeline, z_pipeline, x_shader, z_shader]:
		if rid.is_valid():
			rd.free_rid(rid)
	call_deferred("_done")


func _done() -> void:
	print("PASS: free-surface local-front synthetic cases")
	quit(0)


func _watchdog() -> void:
	for frame in 600:
		if finished:
			return
		await process_frame
	_fail("GPU readback timeout")


func _fail(message: String) -> void:
	if finished:
		return
	finished = true
	printerr("FAIL: local-front bed-drop probe " + message)
	quit(1)

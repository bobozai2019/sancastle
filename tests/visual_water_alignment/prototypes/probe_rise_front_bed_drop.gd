extends SceneTree

# The 256x1 row-front GPU pass must reject depth rise caused by bed drop.
const GRID := 256
const CELLS := GRID * GRID
const SHADER_PATH := "res://tests/visual_water_alignment/prototypes/reference_rise_front_field.glsl"

var output_dir := ""
var rd: RenderingDevice
var shader := RID()
var pipeline := RID()
var textures: Array[RID] = []
var uniform_sets: Array[RID] = []
var received := {}
var finished := false


func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			output_dir = arg.trim_prefix("--output=")
	call_deferred("_begin")


func _begin() -> void:
	if output_dir.is_empty() or not DirAccess.dir_exists_absolute(output_dir):
		_fail("existing output directory required")
		return
	var shader_file: RDShaderFile = load(SHADER_PATH)
	if shader_file == null or shader_file.get_spirv() == null:
		_fail("row-front shader import missing")
		return
	RenderingServer.call_on_render_thread(_run_gpu.bind(shader_file.get_spirv()))
	call_deferred("_watchdog")


func _format(channels: int, height: int) -> RDTextureFormat:
	var format := RDTextureFormat.new()
	format.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	format.width = GRID
	format.height = height
	format.format = RenderingDevice.DATA_FORMAT_R32G32_SFLOAT if channels == 2 else \
		RenderingDevice.DATA_FORMAT_R32_SFLOAT
	format.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | \
		RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | \
		RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	return format


func _texture(values: PackedFloat32Array, channels: int, height: int) -> RID:
	var rid := rd.texture_create(_format(channels, height), RDTextureView.new(),
		[values.to_byte_array()])
	textures.append(rid)
	return rid


func _constant(value: float, channels: int, height := GRID) -> RID:
	var values := PackedFloat32Array()
	values.resize(GRID * height * channels)
	values.fill(value)
	return _texture(values, channels, height)


func _run_gpu(spirv: RDShaderSPIRV) -> void:
	rd = RenderingServer.get_rendering_device()
	if rd == null:
		call_deferred("_fail", "main RenderingDevice missing")
		return
	shader = rd.shader_create_from_spirv(spirv)
	if not shader.is_valid():
		call_deferred("_fail", "shader RID invalid")
		return
	pipeline = rd.compute_pipeline_create(shader)
	if not pipeline.is_valid():
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
	var ids: Array[RID] = [_constant(float(scenario.depth), 1),
		_texture(history, 2, GRID), _constant(0.0, 2, 1),
		_constant(0.0, 1), _constant(float(scenario.bed), 1),
		_constant(0.10, 1)]
	for rid in ids:
		if not rid.is_valid():
			call_deferred("_fail", "texture RID invalid")
			return false
	var uniforms: Array[RDUniform] = []
	for binding in ids.size():
		var uniform := RDUniform.new()
		uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		uniform.binding = binding
		uniform.add_id(ids[binding])
		uniforms.append(uniform)
	var uniform_set := rd.uniform_set_create(uniforms, shader, 0)
	if not uniform_set.is_valid():
		call_deferred("_fail", "uniform set invalid")
		return false
	uniform_sets.append(uniform_set)
	var list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list, pipeline)
	rd.compute_list_bind_uniform_set(list, uniform_set, 0)
	rd.compute_list_dispatch(list, 4, 1, 1)
	rd.compute_list_end()
	var error := rd.texture_get_data_async(ids[2], 0,
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
	if data.size() != GRID * 8:
		_fail("wrong output bytes for " + name)
		return
	received[name] = data
	if received.size() < 3:
		return
	var peaks := {}
	for key in ["steady", "bed_drop", "eta_rise"]:
		if not received.has(key):
			_fail("missing scenario " + key)
			return
		var values: PackedFloat32Array = received[key].to_float32_array()
		peaks[key] = values[128 * 2 + 1]
		var file := FileAccess.open(output_dir.path_join(
			"%s_row_front_rg32f.bin" % key), FileAccess.WRITE)
		if file == null:
			_fail("output open failed for " + key)
			return
		file.store_buffer(received[key])
		file.close()
	var manifest := {"shader": SHADER_PATH,
		"shader_sha256": FileAccess.get_sha256(SHADER_PATH),
		"center_peak": peaks, "grid_size": GRID,
		"scenarios": {"steady": [0.10, 0.10],
			"bed_drop": [0.08, 0.12], "eta_rise": [0.10, 0.12]},
		"adapter": RenderingServer.get_video_adapter_name()}
	var file := FileAccess.open(output_dir.path_join(
		"synthetic_row_front_manifest.json"), FileAccess.WRITE)
	if file == null:
		_fail("manifest open failed")
		return
	file.store_string(JSON.stringify(manifest, "\t"))
	file.close()
	if absf(peaks.steady) > 1e-7 or absf(peaks.bed_drop) > 1e-7 or \
			peaks.eta_rise < 0.019:
		_fail("free-surface synthetic cases failed: " + str(peaks))
		return
	finished = true
	RenderingServer.call_on_render_thread(_cleanup)


func _cleanup() -> void:
	for rid in uniform_sets:
		if rid.is_valid():
			rd.free_rid(rid)
	for rid in textures:
		if rid.is_valid():
			rd.free_rid(rid)
	if pipeline.is_valid():
		rd.free_rid(pipeline)
	if shader.is_valid():
		rd.free_rid(shader)
	call_deferred("_done")


func _done() -> void:
	print("PASS: free-surface row-front synthetic cases")
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
	printerr("FAIL: row-front bed-drop probe " + message)
	quit(1)

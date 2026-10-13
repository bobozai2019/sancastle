extends SceneTree

# Run the production foam compute shader on controlled, spatially uniform fields.
# The bed-drop case keeps eta = bed + depth unchanged while depth rises.

const GRID := 256
const CELLS := GRID * GRID
const SHADER_PATH := "res://shaders/simulation/visual_foam_step.glsl"

var output_dir := ""
var shader_path := SHADER_PATH
var rd: RenderingDevice
var shader_rid := RID()
var pipeline_rid := RID()
var textures: Array[RID] = []
var uniform_sets: Array[RID] = []
var received := {}
var finished := false


func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			output_dir = arg.trim_prefix("--output=")
		elif arg.begins_with("--shader="):
			shader_path = arg.trim_prefix("--shader=")
	call_deferred("_begin")


func _begin() -> void:
	if output_dir.is_empty() or not DirAccess.dir_exists_absolute(output_dir):
		_fail("existing output directory required")
		return
	var shader_file: RDShaderFile = load(shader_path)
	if shader_file == null or shader_file.get_spirv() == null:
		_fail("production foam shader import missing")
		return
	RenderingServer.call_on_render_thread(_run_gpu.bind(shader_file.get_spirv()))
	call_deferred("_watchdog")


func _run_gpu(spirv: RDShaderSPIRV) -> void:
	rd = RenderingServer.get_rendering_device()
	if rd == null:
		call_deferred("_fail", "main RenderingDevice missing")
		return
	shader_rid = rd.shader_create_from_spirv(spirv)
	if not shader_rid.is_valid():
		call_deferred("_fail", "foam shader RID invalid")
		return
	pipeline_rid = rd.compute_pipeline_create(shader_rid)
	if not pipeline_rid.is_valid():
		call_deferred("_fail", "foam pipeline RID invalid")
		return
	for scenario in [{"name": "steady", "bed": 0.10, "depth": 0.10},
			{"name": "bed_drop", "bed": 0.08, "depth": 0.12},
			{"name": "eta_rise", "bed": 0.10, "depth": 0.12}]:
		if not _dispatch_case(scenario):
			return


func _format(channels: int) -> RDTextureFormat:
	var format := RDTextureFormat.new()
	format.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	format.width = GRID
	format.height = GRID
	format.format = RenderingDevice.DATA_FORMAT_R32G32_SFLOAT if channels == 2 else \
		RenderingDevice.DATA_FORMAT_R32_SFLOAT
	format.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | \
		RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | \
		RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	return format


func _constant_texture(value: float, channels: int) -> RID:
	var data := PackedFloat32Array()
	data.resize(CELLS * channels)
	data.fill(value)
	var texture := rd.texture_create(_format(channels), RDTextureView.new(),
		[data.to_byte_array()])
	textures.append(texture)
	return texture


func _dispatch_case(scenario: Dictionary) -> bool:
	var history := PackedFloat32Array()
	history.resize(CELLS * 2)
	for cell in CELLS:
		history[cell * 2] = 0.0
		history[cell * 2 + 1] = 0.10
	var history_texture := rd.texture_create(_format(2), RDTextureView.new(),
		[history.to_byte_array()])
	textures.append(history_texture)
	var depth: float = scenario.depth
	var bed: float = scenario.bed
	var ids: Array[RID] = [history_texture, _constant_texture(depth, 1),
		_constant_texture(depth, 1), _constant_texture(0.0, 1),
		_constant_texture(0.0, 1), _constant_texture(bed, 1),
		_constant_texture(0.0, 2), _constant_texture(0.10, 1),
		_constant_texture(0.0, 1)]
	for id in ids:
		if not id.is_valid():
			call_deferred("_fail", "texture creation failed")
			return false
	var uniforms: Array[RDUniform] = []
	for binding in ids.size():
		var uniform := RDUniform.new()
		uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		uniform.binding = binding
		uniform.add_id(ids[binding])
		uniforms.append(uniform)
	var uniform_set := rd.uniform_set_create(uniforms, shader_rid, 0)
	if not uniform_set.is_valid():
		call_deferred("_fail", "uniform set creation failed")
		return false
	uniform_sets.append(uniform_set)
	var list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list, pipeline_rid)
	rd.compute_list_bind_uniform_set(list, uniform_set, 0)
	var params := PackedFloat32Array([1.0 / 30.0, 0.125, 1.8, 25.0]).to_byte_array()
	rd.compute_list_set_push_constant(list, params, 16)
	rd.compute_list_dispatch(list, GRID / 8, GRID / 8, 1)
	rd.compute_list_end()
	var err := rd.texture_get_data_async(ids[6], 0,
		_on_data.bind(String(scenario.name)))
	if err != OK:
		call_deferred("_fail", "foam readback request failed: " + str(err))
		return false
	return true


func _on_data(data: PackedByteArray, name: String) -> void:
	call_deferred("_receive", data, name)


func _receive(data: PackedByteArray, name: String) -> void:
	if finished:
		return
	if data.size() != CELLS * 8:
		_fail("wrong output bytes for " + name)
		return
	received[name] = data
	if received.size() < 3:
		return
	for key in ["steady", "bed_drop", "eta_rise"]:
		if not received.has(key):
			_fail("missing scenario " + key)
			return
		var path := output_dir.path_join("%s_foam_rg32f.bin" % key)
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			_fail("output open " + key)
			return
		file.store_buffer(received[key])
		file.close()
	var manifest := {"shader": shader_path,
		"shader_sha256": FileAccess.get_sha256(shader_path),
		"grid_size": GRID, "delta_s": 1.0 / 30.0,
		"cell_size_m": 0.125, "lifetime_s": 1.8,
		"source_gain": 25.0, "initial_depth_m": 0.10,
		"initial_foam": 0.0, "velocity_x_m_s": 1.0,
		"scenarios": {"steady": {"bed_m": 0.10, "depth_m": 0.10},
			"bed_drop": {"bed_m": 0.08, "depth_m": 0.12},
			"eta_rise": {"bed_m": 0.10, "depth_m": 0.12}},
		"rendering_driver": "d3d12",
		"adapter": RenderingServer.get_video_adapter_name()}
	var manifest_path := output_dir.path_join("synthetic_foam_manifest.json")
	var manifest_file := FileAccess.open(manifest_path, FileAccess.WRITE)
	if manifest_file == null:
		_fail("manifest open")
		return
	manifest_file.store_string(JSON.stringify(manifest, "\t"))
	manifest_file.close()
	finished = true
	RenderingServer.call_on_render_thread(_cleanup)


func _cleanup() -> void:
	for uniform_set in uniform_sets:
		if uniform_set.is_valid():
			rd.free_rid(uniform_set)
	for texture in textures:
		if texture.is_valid():
			rd.free_rid(texture)
	if pipeline_rid.is_valid():
		rd.free_rid(pipeline_rid)
	if shader_rid.is_valid():
		rd.free_rid(shader_rid)
	call_deferred("_done")


func _done() -> void:
	print("PASS: production foam compute synthetic cases captured")
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
	printerr("FAIL: foam bed-drop probe " + message)
	quit(1)

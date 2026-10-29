extends "res://probe.gd"

const CB_BYTES := {1484:2496,1490:2560,1495:2528,1500:2544,1537:2560,1543:2496}
const READ_COUNTS := {1484:1,1490:5,1495:5,1500:5,1537:1,1543:5}

func _checked_bytes(artifact: Dictionary) -> PackedByteArray:
	var bytes := FileAccess.get_file_as_bytes(str(artifact["path"]))
	if bytes.is_empty():
		_fail("EMPTY_ARTIFACT:" + str(artifact["path"]))
		return PackedByteArray()
	if bytes.size() != int(artifact["size_bytes"]) or FileAccess.get_sha256(str(artifact["path"])) != artifact["sha256"]:
		_fail("ARTIFACT_IDENTITY_MISMATCH:" + str(artifact["path"]))
		return PackedByteArray()
	return bytes

func _write_bytes(path: String, bytes: PackedByteArray) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()

func _hash_bytes(bytes: PackedByteArray) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	return hash.finish().hex_encode()

func _free_case() -> void:
	while not owned.is_empty():
		rd.free_rid(owned.pop_back())
		released += 1

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2 or args[0] != "--request":
		_fail("REQUEST_REQUIRED")
		return
	var request: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[1]))
	output_root = str(request["output_root"])
	if not output_root.is_absolute_path() or not DirAccess.dir_exists_absolute(output_root):
		_fail("OUTPUT_DIRECTORY_REQUIRED")
		return
	rd = RenderingServer.create_local_rendering_device()
	if rd == null:
		_fail("LOCAL_RENDERING_DEVICE_UNAVAILABLE")
		return
	var results: Array[Dictionary] = []
	for case: Dictionary in request["cases"]:
		var event := int(case["event_id"])
		var read_count := int(case.get("read_count", 0))
		var mode := str(case.get("execution_mode", ""))
		if not READ_COUNTS.has(event) or read_count != int(READ_COUNTS[event]) or not ["read_stream", "in_place_record"].has(mode) or not case.get("register_trace", false):
			_fail("READ_STREAM_PILOT_MODE_REQUIRED")
			return
		if mode == "in_place_record" and case.has("stream_input"):
			_fail("UNEXPECTED_STREAM_INPUT_FOR_RECORD")
			return
		if mode == "read_stream" and not case.has("stream_input"):
			_fail("STREAM_INPUT_REQUIRED_FOR_REPLAY")
			return
		var stream_bytes := WATER_BYTES * read_count * 2
		var input := _checked_bytes(case["input"])
		var constants := _checked_bytes(case["constants"])
		if input.is_empty() or constants.is_empty():
			return
		if input.size() != WATER_BYTES or not CB_BYTES.has(event) or constants.size() != int(CB_BYTES[event]):
			_fail("DEPENDENCY_EXTENT_MISMATCH")
			return
		var shader_path := str(case.get("shader_path", "res://shaders/e%d_inplace.glsl" % event))
		if FileAccess.get_sha256(shader_path) != case["shader_sha256"]:
			_fail("SHADER_IDENTITY_CHANGED")
			return
		var source := RDShaderSource.new()
		source.source_compute = FileAccess.get_file_as_string(shader_path).replace("\r\n", "\n").trim_prefix("#[compute]\n")
		var spirv := rd.shader_compile_spirv_from_source(source)
		var compile_error := spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
		if not compile_error.is_empty():
			_fail("COMPUTE_COMPILE:e%d:" % event + compile_error)
			return
		var compiled_bytes := spirv.get_stage_bytecode(RenderingDevice.SHADER_STAGE_COMPUTE)
		_write_bytes(output_root.path_join(str(case["case_id"]) + "_shader.spv"), compiled_bytes)
		var shader := rd.shader_create_from_spirv(spirv)
		owned.append(shader)
		var pipeline := rd.compute_pipeline_create(shader)
		owned.append(pipeline)
		if not rd.compute_pipeline_is_valid(pipeline):
			_fail("PIPELINE_CREATION_FAILED")
			return
		var water := rd.storage_buffer_create(WATER_BYTES, input)
		var cb := rd.storage_buffer_create(constants.size(), constants)
		owned.append_array([water, cb])
		var uniforms: Array[RDUniform] = [_buffer_uniform(0, water), _buffer_uniform(1, cb)]
		var stream_input := RID()
		var stream_input_seed := PackedByteArray()
		if str(case.get("execution_mode", "in_place")) == "read_stream":
			stream_input_seed = _checked_bytes(case["stream_input"])
			if stream_input_seed.is_empty():
				return
			if stream_input_seed.size() != stream_bytes:
				_fail("READ_STREAM_EXTENT_MISMATCH")
				return
			stream_input = rd.storage_buffer_create(stream_bytes, stream_input_seed)
			owned.append(stream_input)
			uniforms.append(_buffer_uniform(4, stream_input))
		var debug_trace := RID()
		var debug_seed := PackedByteArray()
		if case.get("register_trace", false):
			debug_seed.resize(stream_bytes)
			debug_seed.fill(0)
			debug_trace = rd.storage_buffer_create(stream_bytes, debug_seed)
			owned.append(debug_trace)
			uniforms.append(_buffer_uniform(5, debug_trace))
		var auxiliary := RID()
		var texture := RID()
		var texture_seed := PackedByteArray()
		var auxiliary_seed := PackedByteArray()
		if event == 1484 or event == 1537:
			auxiliary_seed = _checked_bytes(case["srvs"][0 if event == 1484 else 1])
			if auxiliary_seed.is_empty():
				return
			auxiliary = rd.storage_buffer_create(auxiliary_seed.size(), auxiliary_seed)
			owned.append(auxiliary)
			uniforms.append(_buffer_uniform(2, auxiliary))
		if event == 1537:
			texture_seed = _checked_bytes(case["srvs"][0])
			if texture_seed.size() != 512 * 256 * 4:
				_fail("SOURCE_TEXTURE_EXTENT_MISMATCH")
				return
			var format := RDTextureFormat.new()
			format.width = 512
			format.height = 256
			format.format = RenderingDevice.DATA_FORMAT_R16G16_SFLOAT
			format.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
			var data: Array[PackedByteArray] = [texture_seed]
			texture = rd.texture_create(format, RDTextureView.new(), data)
			owned.append(texture)
			var uniform := RDUniform.new()
			uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
			uniform.binding = 3
			uniform.add_id(texture)
			uniforms.append(uniform)
		var uniform_set := rd.uniform_set_create(uniforms, shader, 0)
		owned.append(uniform_set)
		if not rd.uniform_set_is_valid(uniform_set):
			_fail("UNIFORM_SET_CREATION_FAILED")
			return
		rd.submit()
		rd.sync()
		var cb_before := rd.buffer_get_data(cb)
		_write_bytes(output_root.path_join(str(case["case_id"]) + "_cb_before.bin"), cb_before)
		var proof := {"cb":_hash_bytes(cb_before)}
		if proof["cb"] != _hash_bytes(constants):
			_fail("GPU_CONSTANTS_INPUT_MISMATCH")
			return
		if stream_input.is_valid():
			var stream_input_before := rd.buffer_get_data(stream_input)
			proof["stream_input"] = _hash_bytes(stream_input_before)
			_write_bytes(output_root.path_join(str(case["case_id"]) + "_stream_input_before.bin"), stream_input_before)
			if proof["stream_input"] != _hash_bytes(stream_input_seed):
				_fail("GPU_READ_STREAM_INPUT_MISMATCH")
				return
		if auxiliary.is_valid():
			var aux_before := rd.buffer_get_data(auxiliary)
			proof["auxiliary"] = _hash_bytes(aux_before)
			_write_bytes(output_root.path_join(str(case["case_id"]) + "_aux_before.bin"), aux_before)
			if proof["auxiliary"] != _hash_bytes(auxiliary_seed):
				_fail("GPU_AUX_INPUT_MISMATCH")
				return
		if texture.is_valid():
			var texture_before := rd.texture_get_data(texture, 0)
			proof["texture"] = _hash_bytes(texture_before)
			_write_bytes(output_root.path_join(str(case["case_id"]) + "_texture_before.bin"), texture_before)
			if proof["texture"] != _hash_bytes(texture_seed):
				_fail("GPU_TEXTURE_INPUT_MISMATCH")
				return
		var repeats: Array[Dictionary] = []
		for repeat_index in int(request["repeat_count"]):
			rd.buffer_update(water, 0, input.size(), input)
			if debug_trace.is_valid():
				rd.buffer_update(debug_trace, 0, stream_bytes, debug_seed)
			rd.submit()
			rd.sync()
			var before := rd.buffer_get_data(water)
			if _hash_bytes(before) != case["input"]["sha256"]:
				_fail("GPU_WATER_INPUT_MISMATCH")
				return
			var prefix := str(case["case_id"]) + "_%d" % repeat_index
			_write_bytes(output_root.path_join(prefix + "_before.bin"), before)
			var list := rd.compute_list_begin()
			rd.compute_list_bind_compute_pipeline(list, pipeline)
			rd.compute_list_bind_uniform_set(list, uniform_set, 0)
			rd.compute_list_dispatch(list, 16, 8, 1)
			rd.compute_list_end()
			var submit_begin := Time.get_ticks_usec()
			rd.submit()
			var sync_begin := Time.get_ticks_usec()
			rd.sync()
			var sync_end := Time.get_ticks_usec()
			var after := rd.buffer_get_data(water)
			var target := output_root.path_join(prefix + "_after.bin")
			_write_bytes(target, after)
			if debug_trace.is_valid():
				_write_bytes(output_root.path_join(prefix + "_stream_output.bin"), rd.buffer_get_data(debug_trace))
			repeats.append({"index":repeat_index,"before_sha256":_hash_bytes(before),"after":target,"submit_begin_usec":submit_begin,"sync_begin_usec":sync_begin,"sync_end_usec":sync_end})
		if stream_input.is_valid():
			var stream_input_after := rd.buffer_get_data(stream_input)
			proof["stream_input_after"] = _hash_bytes(stream_input_after)
			_write_bytes(output_root.path_join(str(case["case_id"]) + "_stream_input_after.bin"), stream_input_after)
			if proof["stream_input_after"] != _hash_bytes(stream_input_seed):
				_fail("READ_STREAM_MUTATED")
				return
		results.append({"case_id":case["case_id"],"event":event,"execution_mode":case.get("execution_mode", "in_place"),"gpu_dependency_hashes":proof,"repeats":repeats,"alias":"explicit fixed post-swizzle stream plus separate output" if stream_input.is_valid() else "one water SSBO read/write; restore before every repeat","completion":"local submit then sync, CPU bracket only"})
		_free_case()
	_finish(0, {"operation_status":"complete","verification_status":"not_evaluated","errors":[],"engine_version":Engine.get_version_info(),"device":rd.get_device_name(),"cases":results,"scope":"Instrumented alias record and fixed-stream replay; mode-specific exact pairing required"})

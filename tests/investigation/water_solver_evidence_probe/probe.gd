extends Node

const WATER_BYTES: int = 512 * 256 * 16
const CODE_BYTES: int = 512 * 256 * 9 * 4
var rd: RenderingDevice
var output_root: String = ""
var owned: Array[RID] = []
var released: int = 0

func _ready() -> void:
	call_deferred("_run")

func _release() -> void:
	if rd == null:
		return
	while not owned.is_empty():
		rd.free_rid(owned.pop_back())
		released += 1
	rd.free()
	rd = null

func _finish(code: int, result: Dictionary) -> void:
	_release()
	result["released_rids"] = released
	result["local_device_released"] = rd == null
	if not output_root.is_empty():
		var file := FileAccess.open(output_root.path_join("probe_result.json"), FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(result, "\t"))
	print(JSON.stringify(result))
	get_tree().quit(code)

func _fail(reason: String) -> void:
	_finish(1, {"operation_status":"failed", "verification_status":"not_evaluated", "errors":[reason]})

func _buffer_uniform(binding: int, buffer: RID) -> RDUniform:
	var uniform := RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform.binding = binding
	uniform.add_id(buffer)
	return uniform

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2 or args[0] != "--request":
		_fail("REQUEST_REQUIRED")
		return
	var request: Variant = JSON.parse_string(FileAccess.get_file_as_string(args[1]))
	if not request is Dictionary:
		_fail("REQUEST_INVALID")
		return
	output_root = str(request.get("output_root", ""))
	if not output_root.is_absolute_path() or not DirAccess.dir_exists_absolute(output_root):
		_fail("OUTPUT_DIRECTORY_REQUIRED")
		return
	var inputs: Array[PackedByteArray] = []
	for case: Dictionary in request["cases"]:
		var path := str(case["input"]["path"])
		var bytes := FileAccess.get_file_as_bytes(path)
		if bytes.size() != WATER_BYTES or int(case["input"]["size_bytes"]) != WATER_BYTES:
			_fail("INPUT_SIZE_MISMATCH")
			return
		if FileAccess.get_sha256(path) != case["input"]["sha256"]:
			_fail("INPUT_IDENTITY_MISMATCH")
			return
		inputs.append(bytes)
	rd = RenderingServer.create_local_rendering_device()
	if rd == null:
		_fail("LOCAL_RENDERING_DEVICE_UNAVAILABLE")
		return
	var source := RDShaderSource.new()
	source.source_compute = FileAccess.get_file_as_string("res://shaders/packed_codec.glsl").replace("\r\n", "\n").trim_prefix("#[compute]\n")
	var spirv := rd.shader_compile_spirv_from_source(source)
	var compile_error := spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
	if not compile_error.is_empty():
		_fail("COMPUTE_COMPILE:" + compile_error)
		return
	var shader := rd.shader_create_from_spirv(spirv)
	if not shader.is_valid():
		_fail("SHADER_CREATION_FAILED")
		return
	owned.append(shader)
	var pipeline := rd.compute_pipeline_create(shader)
	owned.append(pipeline)
	if not rd.compute_pipeline_is_valid(pipeline):
		_fail("PIPELINE_CREATION_FAILED")
		return
	var results: Array[Dictionary] = []
	for index in inputs.size():
		var input_buffer := rd.storage_buffer_create(WATER_BYTES, inputs[index])
		var packed_buffer := rd.storage_buffer_create(WATER_BYTES)
		var code_buffer := rd.storage_buffer_create(CODE_BYTES)
		owned.append_array([input_buffer, packed_buffer, code_buffer])
		var uniforms: Array[RDUniform] = [_buffer_uniform(0, input_buffer), _buffer_uniform(1, packed_buffer), _buffer_uniform(2, code_buffer)]
		var uniform_set := rd.uniform_set_create(uniforms, shader, 0)
		owned.append(uniform_set)
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
		var packed := rd.buffer_get_data(packed_buffer)
		var codes := rd.buffer_get_data(code_buffer)
		if packed.size() != WATER_BYTES or codes.size() != CODE_BYTES:
			_fail("GPU_READBACK_EXTENT_MISMATCH")
			return
		var case_id := str(request["cases"][index]["case_id"])
		var packed_path := output_root.path_join(case_id + "_roundtrip.bin")
		var codes_path := output_root.path_join(case_id + "_codes.bin")
		var packed_file := FileAccess.open(packed_path, FileAccess.WRITE)
		var codes_file := FileAccess.open(codes_path, FileAccess.WRITE)
		if packed_file == null or codes_file == null:
			_fail("OUTPUT_OPEN_FAILED")
			return
		packed_file.store_buffer(packed)
		codes_file.store_buffer(codes)
		packed_file.close()
		codes_file.close()
		results.append({"case_id":case_id,"input_sha256":request["cases"][index]["input"]["sha256"],"roundtrip":packed_path,"codes":codes_path,"groups":[16,8,1],"submit_begin_usec":submit_begin,"sync_begin_usec":sync_begin,"sync_end_usec":sync_end,"completion":"local RenderingDevice submit then sync before readback; these are CPU brackets, not GPU timestamps"})
	_finish(0, {"operation_status":"complete", "verification_status":"not_evaluated", "errors":[],"engine_version":Engine.get_version_info(),"device":rd.get_device_name(),"device_vendor":rd.get_device_vendor_name(),"cases":results,"scope":"Packed uint4 codec only, no six-kernel or G5 claim"})

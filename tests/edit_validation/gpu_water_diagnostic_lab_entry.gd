extends "res://tests/edit_validation/gpu_water_lab_entry.gd"

func _ready() -> void:
	var file: RDShaderFile = load("res://shaders/simulation/edit_validation/shallow_update_diagnostic.glsl")
	var spirv := file.get_spirv()
	var error := spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
	if not error.is_empty():
		_fail("diagnostic update shader compile: " + error)
		return
	super._ready()
	if not last_error.is_empty(): return
	spirvs[2] = spirv
	var bytes: PackedByteArray = spirv.call("get_stage_bytecode", RenderingDevice.SHADER_STAGE_COMPUTE)
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	shader_metadata.append({"path": file.resource_path, "source_sha256": FileAccess.get_sha256(file.resource_path),
		"spirv_bytes": bytes.size(), "spirv_sha256": hash.finish().hex_encode(),
		"scope": "observation-only clone; not cost backend"})

func _create_solver() -> SandcastleGpuShallowSolver:
	var editor := preload("res://scripts/simulation/edit_validation/gpu_water_diagnostic_editor.gd").new()
	editor.edit_spirvs = editor_spirvs
	editor.water_spirvs = displacement_spirvs
	editor.local_dispatch = local_dispatch
	editor.fast_full_wet = fast_full_wet
	return editor

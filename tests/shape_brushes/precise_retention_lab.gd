extends "res://tests/shape_brushes/original_retention_lab.gd"

var precision_identity := {}

func _render_setup(target: SandWaterDomain, token: int) -> void:
	var device:=RenderingServer.get_rendering_device()
	var source:=RDShaderSource.new()
	source.source_compute=FileAccess.get_file_as_string("res://tests/shape_brushes/precise_sediment_diagnostic.glsl").replace("#[compute]","")
	var code:=device.shader_compile_spirv_from_source(source)
	var error:=code.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
	if not error.is_empty(): call_deferred("_fail","precision diagnostic compile: "+error);return
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(code.get_stage_bytecode(RenderingDevice.SHADER_STAGE_COMPUTE))
	precision_identity={"compiled_spirv_sha256":hash.finish().hex_encode(),"diagnostic_source_sha256":FileAccess.get_sha256("res://tests/shape_brushes/precise_sediment_diagnostic.glsl"),"original_source_sha256":FileAccess.get_sha256("res://shaders/simulation/erosion/sediment_step.glsl"),"solver_script":"res://scripts/simulation/edit_validation/gpu_water_editor.gd","scope":"Only explicit precision annotations/return temporaries changed in diagnostic sediment source; production shader unchanged."}
	spirvs[10]=code
	super._render_setup(target,token)

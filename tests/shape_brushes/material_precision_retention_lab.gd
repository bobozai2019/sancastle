extends "res://tests/shape_brushes/original_retention_lab.gd"

var precision_identity := {}

func _render_setup(target: SandWaterDomain, token: int) -> void:
	var variant: String="precise"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--variant="): variant=arg.trim_prefix("--variant=")
	if variant not in ["original","precise"]: call_deferred("_fail","material precision variant invalid");return
	var path: String="res://shaders/simulation/material/material_step.glsl" if variant=="original" else "res://tests/shape_brushes/precise_material_step_diagnostic.glsl"
	var device:=RenderingServer.get_rendering_device();var source:=RDShaderSource.new()
	source.source_compute=FileAccess.get_file_as_string(path).replace("#[compute]","")
	var code:=device.shader_compile_spirv_from_source(source)
	var error:=code.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
	if not error.is_empty(): call_deferred("_fail","material precision diagnostic compile: "+error);return
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(code.get_stage_bytecode(RenderingDevice.SHADER_STAGE_COMPUTE))
	precision_identity={"variant":variant,"compiled_spirv_sha256":hash.finish().hex_encode(),"source_sha256":FileAccess.get_sha256(path),"original_source_sha256":FileAccess.get_sha256("res://shaders/simulation/material/material_step.glsl"),"compile_route":"runtime_shader_compile_spirv_from_source","scope":"Original vs precise material_step at same compile route; production unchanged."}
	spirvs[12]=code
	super._render_setup(target,token)
	if solver!=null: precision_identity["actual_solver_script"]=solver.get_script().resource_path

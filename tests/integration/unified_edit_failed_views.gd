extends "res://scripts/simulation/unified_edit/views.gd"

# A real compiler rejection after the preceding view allocations and publication
# kernel succeed. It never changes the runtime shader or simulates success.
var actual_compile_error:=""
const BROKEN_SOURCE:="#version 450\nlayout(local_size_x=1) in;\nvoid main(){ deliberately_invalid_token; }"

func compile(name: String, path: String) -> bool:
	if name!="query":return super.compile(name,path)
	var source:=RDShaderSource.new();source.source_compute=BROKEN_SOURCE
	var spirv:=rd.shader_compile_spirv_from_source(source)
	actual_compile_error=spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
	last_error="query:"+actual_compile_error
	return actual_compile_error.is_empty()

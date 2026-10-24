extends SceneTree

var output:="res://test_output/water_execution_optimization/shader_compile"

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	call_deferred("run")

func run() -> void:
	RenderingServer.call_on_render_thread(compile_render)

func compile_render() -> void:
	var rd:=RenderingServer.get_rendering_device()
	var rows: Array=[]
	var passed:=true
	DirAccess.make_dir_recursive_absolute(output)
	for variant in ["baseline","candidate"]:
		var base:="res://task/water_execution_optimization/baseline/shaders/simulation/muscl/" if variant=="baseline" else "res://shaders/simulation/muscl/"
		for name in ["rk_decide","rk_edge","rk_euler"]:
			var text:=FileAccess.get_file_as_string(base+name+".glsl").trim_prefix("#[compute]")
			for _pass in 4:
				for include in ["muscl_spatial.glslinc","muscl_math.glslinc","muscl_stats.glslinc"]:
					text=text.replace("#include \""+include+"\"",FileAccess.get_file_as_string(base+include))
			var source:=RDShaderSource.new();source.source_compute=text
			var spirv:=rd.shader_compile_spirv_from_source(source)
			var error:=spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
			var bytes:=spirv.get_stage_bytecode(RenderingDevice.SHADER_STAGE_COMPUTE)
			var path:=output.path_join(variant+"_"+name+".spv")
			FileAccess.open(path,FileAccess.WRITE).store_buffer(bytes)
			FileAccess.open(output.path_join(variant+"_"+name+".glsl"),FileAccess.WRITE).store_string(text)
			rows.append({"variant":variant,"kernel":name,"bytes":bytes.size(),"sha256":FileAccess.get_sha256(path),"error":error})
			passed=passed and error.is_empty() and not bytes.is_empty()
	FileAccess.open(output.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"pass":passed,"engine":Engine.get_version_info(),"rows":rows,"scope":"Actual RD GLSL-to-SPIR-V output; not final D3D12 native ISA or a timing result."},"\t"))
	quit.call_deferred(0 if passed else 1)

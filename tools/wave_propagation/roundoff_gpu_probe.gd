extends SceneTree
var output:=""
var done:=false
var result: Dictionary={}

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	call_deferred("run")

func render_test() -> void:
	var rd: RenderingDevice=RenderingServer.get_rendering_device()
	var owned: Array[RID]=[]
	var zero:=PackedByteArray();zero.resize(128)
	var safety:=rd.storage_buffer_create(128,zero);owned.append(safety)
	var trial:=rd.storage_buffer_create(128,zero);owned.append(trial)
	var base:="res://shaders/simulation/muscl/"
	var text:="#version 450\nlayout(local_size_x=2) in;layout(set=0,binding=0,std430) buffer S{uint stats[];};layout(set=0,binding=1,std430) buffer T{uint tr[];};layout(set=0,binding=2,r32f) uniform writeonly image2D output_tex;\n"
	text+=FileAccess.get_file_as_string(base+"muscl_math.glslinc")+"\n"+FileAccess.get_file_as_string(base+"muscl_stats.glslinc")
	text+="\nvoid main(){uint lane=gl_GlobalInvocationID.x;float x=nonnegative(lane==0u?-1e-9:-0.001,0.1,16u+lane*8u,0u,6u,0.015625);imageStore(output_tex,ivec2(lane,0),vec4(x));}"
	FileAccess.open(output.path_join("compiled.glsl"),FileAccess.WRITE).store_string(text)
	var source:=RDShaderSource.new();source.source_compute=text
	var spirv:=rd.shader_compile_spirv_from_source(source)
	var error:=spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
	if not error.is_empty():
		for rid in owned:rd.free_rid(rid)
		finished.call_deferred({"outcome":"fail","compile_error":error});return
	var shader:=rd.shader_create_from_spirv(spirv);owned.append(shader)
	var format:=RDTextureFormat.new();format.width=2;format.height=1;format.format=RenderingDevice.DATA_FORMAT_R32_SFLOAT
	format.usage_bits=RenderingDevice.TEXTURE_USAGE_STORAGE_BIT|RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	var image:=rd.texture_create(format,RDTextureView.new());owned.append(image)
	var pipeline:=rd.compute_pipeline_create(shader);owned.append(pipeline)
	var uniforms: Array[RDUniform]=[]
	for pair in [[0,safety,RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER],[1,trial,RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER],[2,image,RenderingDevice.UNIFORM_TYPE_IMAGE]]:
		var uniform:=RDUniform.new();uniform.binding=pair[0];uniform.uniform_type=pair[2];uniform.add_id(pair[1]);uniforms.append(uniform)
	var binding:=rd.uniform_set_create(uniforms,shader,0);owned.append(binding)
	var list:=rd.compute_list_begin();rd.compute_list_bind_compute_pipeline(list,pipeline);rd.compute_list_bind_uniform_set(list,binding,0);rd.compute_list_dispatch(list,1,1,1);rd.compute_list_end()
	var safety_bytes:=rd.buffer_get_data(safety);var trial_bytes:=rd.buffer_get_data(trial);var image_bytes:=rd.texture_get_data(image,0)
	for pair in [["safety",safety_bytes],["trial",trial_bytes],["output",image_bytes]]:FileAccess.open(output.path_join(pair[0]+".bin"),FileAccess.WRITE).store_buffer(pair[1])
	var volume:=safety_bytes.decode_float(88)
	var okay:=safety_bytes.decode_u32(64)==1 and safety_bytes.decode_u32(96)==0 and trial_bytes.decode_u32(56)==2 and volume>0.0 and absf(volume-1.5625e-11)<=1.5625e-11*8.0*1.1920928955078125e-7 and image_bytes.decode_float(0)==0.0 and image_bytes.decode_float(4)==0.0
	var report:={"outcome":"pass" if okay else "fail","allowed_count":safety_bytes.decode_u32(64),"rejected_count":safety_bytes.decode_u32(96),"flags":trial_bytes.decode_u32(56),"roundoff_volume_m3":volume,"source_hashes":{base+"muscl_math.glslinc":FileAccess.get_sha256(base+"muscl_math.glslinc"),base+"muscl_stats.glslinc":FileAccess.get_sha256(base+"muscl_stats.glslinc")},"scope":"Actual main-RD shared float32 helper, CAS volume and counters; not an authority mutation"}
	for index in range(owned.size()-1,-1,-1):rd.free_rid(owned[index])
	finished.call_deferred(report)

func finished(value: Dictionary) -> void:
	result=value;done=true

func run() -> void:
	if output.is_empty():quit(2);return
	RenderingServer.call_on_render_thread(render_test)
	while not done:await process_frame
	result.probe_sha256=FileAccess.get_sha256(get_script().resource_path)
	result.engine=Engine.get_version_info();result.adapter=RenderingServer.get_video_adapter_name();result.driver=RenderingServer.get_current_rendering_driver_name()
	var files: Array=[]
	for name in ["compiled.glsl","safety.bin","trial.bin","output.bin"]:
		var path:=output.path_join(name)
		if FileAccess.file_exists(path):files.append({"path":path,"sha256":FileAccess.get_sha256(path),"bytes":FileAccess.get_file_as_bytes(path).size()})
	result.files=files
	FileAccess.open(output.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify(result,"\t"));print(JSON.stringify(result));quit(0 if result.outcome=="pass" else 1)

extends SceneTree

var output:=""
var done:=false
var checks: Array=[]
var errors: Array=[]

const SOURCE="""#version 450
layout(local_size_x=1) in;
layout(set=0,binding=0,std430) buffer Args {uint groups[];};
layout(set=0,binding=1,std430) buffer Payload {uint payload[];};
layout(set=0,binding=2,std430) buffer Result {uint result[];};
layout(set=0,binding=3,r32f) uniform image2D pixel;
layout(push_constant,std430) uniform Params {uint mode,count,value,pad;} p;
void main(){
 if(p.mode==0u){groups[0]=p.count;groups[1]=1u;groups[2]=1u;payload[0]=p.value;imageStore(pixel,ivec2(0),vec4(0.5));}
 else {result[0]=payload[0]+uint(imageLoad(pixel,ivec2(0)).x*2.0);}
}
"""

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	call_deferred("run")

func exercise() -> void:
	var rd:=RenderingServer.get_rendering_device()
	var owned: Array[RID]=[]
	var args:=rd.storage_buffer_create(12,PackedByteArray(),RenderingDevice.STORAGE_BUFFER_USAGE_DISPATCH_INDIRECT)
	var payload:=rd.storage_buffer_create(4)
	var result:=rd.storage_buffer_create(4)
	owned.append_array([args,payload,result])
	var format:=RDTextureFormat.new();format.width=1;format.height=1;format.format=RenderingDevice.DATA_FORMAT_R32_SFLOAT
	format.usage_bits=RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
	var pixel:=rd.texture_create(format,RDTextureView.new());owned.append(pixel)
	var pipelines: Array[RID]=[]
	var bindings: Array[RID]=[]
	for i in 2:
		var source:=RDShaderSource.new();source.source_compute=SOURCE
		var spirv:=rd.shader_compile_spirv_from_source(source)
		var error:=spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
		if not error.is_empty():errors.append(error);break
		var shader:=rd.shader_create_from_spirv(spirv);owned.append(shader)
		var pipeline:=rd.compute_pipeline_create(shader);owned.append(pipeline);pipelines.append(pipeline)
		var uniforms: Array[RDUniform]=[]
		for index in 4:
			var u:=RDUniform.new();u.binding=index;u.uniform_type=RenderingDevice.UNIFORM_TYPE_IMAGE if index==3 else RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
			u.add_id([args,payload,result,pixel][index]);uniforms.append(u)
		var binding:=rd.uniform_set_create(uniforms,shader,0);owned.append(binding);bindings.append(binding)
	if pipelines.size()==2:
		for count in [0,1,0,1]:
			rd.buffer_update(result,0,4,PackedInt32Array([7]).to_byte_array())
			var list:=rd.compute_list_begin()
			rd.compute_list_bind_compute_pipeline(list,pipelines[0]);rd.compute_list_bind_uniform_set(list,bindings[0],0)
			rd.compute_list_set_push_constant(list,PackedInt32Array([0,count,42,0]).to_byte_array(),16)
			rd.compute_list_dispatch(list,1,1,1)
			rd.compute_list_add_barrier(list)
			rd.compute_list_bind_compute_pipeline(list,pipelines[1]);rd.compute_list_bind_uniform_set(list,bindings[1],0)
			rd.compute_list_set_push_constant(list,PackedInt32Array([1,count,42,0]).to_byte_array(),16)
			rd.compute_list_dispatch_indirect(list,args,0)
			rd.compute_list_end()
			var read:=rd.buffer_get_data(result)
			checks.append({"indirect_count":count,"expected":7 if count==0 else 43,"actual":read.decode_u32(0),"pass":read.decode_u32(0)==(7 if count==0 else 43)})
	for i in range(owned.size()-1,-1,-1):rd.free_rid(owned[i])
	done=true

func run() -> void:
	RenderingServer.call_on_render_thread(exercise)
	var deadline:=Time.get_ticks_msec()+15000
	while not done and Time.get_ticks_msec()<deadline:await process_frame
	var passed: bool=done and errors.is_empty() and checks.size()==4 and checks.all(func(row):return row.pass)
	DirAccess.make_dir_recursive_absolute(output)
	FileAccess.open(output.path_join("dependency.json"),FileAccess.WRITE).store_string(JSON.stringify({"pass":passed,"checks":checks,"errors":errors,"engine":Engine.get_version_info(),"adapter":RenderingServer.get_video_adapter_name(),"driver":RenderingServer.get_current_rendering_driver_name(),"scope":"Actual texture/storage/indirect write-read in one list, explicit barrier, two pipeline bindings, zero and nonzero indirect counts; numerical validation only"},"\t"))
	quit(0 if passed else 1)

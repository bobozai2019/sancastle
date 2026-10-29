extends RefCounted

# Render-thread resource owner for the fixed sand/water stages.
const L=preload("res://scripts/simulation/unified_edit/layout.gd")
var rd: RenderingDevice
var owned: Array[RID]=[]
var kernels: Dictionary={}
var source_hashes: Dictionary={}
var last_error:=""

func own(rid: RID) -> RID:
	if rid.is_valid():owned.append(rid)
	return rid

func compile(name: String, path: String) -> bool:
	if rd==null or kernels.has(name):return false
	var text:=FileAccess.get_file_as_string(path)
	source_hashes[path]=FileAccess.get_sha256(path)
	var source:=RDShaderSource.new()
	source.source_compute=text.trim_prefix("#[compute]").replace("// UE_LAYOUT",L.shader_defines())
	var spirv:=rd.shader_compile_spirv_from_source(source)
	last_error=spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
	if not last_error.is_empty():last_error=name+":"+last_error;return false
	var shader:=own(rd.shader_create_from_spirv(spirv))
	var pipeline:=own(rd.compute_pipeline_create(shader))
	if not shader.is_valid() or not pipeline.is_valid():last_error=name+":create_failed";return false
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(spirv.get_stage_bytecode(RenderingDevice.SHADER_STAGE_COMPUTE))
	kernels[name]={"shader":shader,"pipeline":pipeline,"spirv_sha256":hash.finish().hex_encode()}
	return true

func binding(name: String, buffers: Dictionary={}, images: Dictionary={}, set_index: int=0) -> RID:
	var uniforms: Array[RDUniform]=[]
	for pair in [[buffers,RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER],[images,RenderingDevice.UNIFORM_TYPE_IMAGE]]:
		for index in pair[0]:
			var uniform:=RDUniform.new();uniform.binding=index
			uniform.uniform_type=pair[1]
			uniform.add_id(pair[0][index]);uniforms.append(uniform)
	return own(rd.uniform_set_create(uniforms,kernels[name].shader,set_index))

func dispatch(name: String, binding_set: RID, groups: Vector3i, push: PackedByteArray=PackedByteArray()) -> void:
	var list:=rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list,kernels[name].pipeline)
	rd.compute_list_bind_uniform_set(list,binding_set,0)
	if not push.is_empty():rd.compute_list_set_push_constant(list,push,push.size())
	rd.compute_list_dispatch(list,groups.x,groups.y,groups.z);rd.compute_list_end()

func release() -> void:
	if rd!=null:
		for index in range(owned.size()-1,-1,-1):rd.free_rid(owned[index])
	owned.clear();kernels.clear();rd=null

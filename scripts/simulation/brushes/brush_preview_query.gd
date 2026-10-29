extends RefCounted

var rd:RenderingDevice
var solver
var owned:Array[RID]=[]
var shader:=RID()
var pipeline:=RID()
var uniform_set:=RID()
var buffer:=RID()
var pending:=false
var initialized:=false
var query_count:=0
var last_error:=""

func _own(rid:RID) -> RID:
	if rid.is_valid():owned.append(rid)
	return rid

func initialize(owner,template:RID) -> bool:
	solver=owner;rd=owner.rd
	var source:=RDShaderSource.new();source.source_compute=FileAccess.get_file_as_string("res://shaders/simulation/brushes/preview_base.glsl").replace("#[compute]","")
	var code:=rd.shader_compile_spirv_from_source(source);last_error=code.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
	if not last_error.is_empty():return false
	shader=_own(rd.shader_create_from_spirv(code));pipeline=_own(rd.compute_pipeline_create(shader));buffer=_own(rd.storage_buffer_create(64))
	var uniforms:Array[RDUniform]=[]
	var images:Array[RID]=[owner.textures.rock,owner.textures.sand[0],owner.textures.sand[1],owner.textures.water[0],owner.textures.water[1],owner.textures.obstacle,template]
	for binding in images.size():
		var u:=RDUniform.new();u.binding=binding;u.uniform_type=RenderingDevice.UNIFORM_TYPE_IMAGE;u.add_id(images[binding]);uniforms.append(u)
	var data:=RDUniform.new();data.binding=7;data.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER;data.add_id(buffer);uniforms.append(data)
	uniform_set=_own(rd.uniform_set_create(uniforms,shader,0))
	initialized=shader.is_valid() and pipeline.is_valid() and buffer.is_valid() and uniform_set.is_valid();return initialized

func request(position:Vector2,params:Dictionary,callback:Callable) -> bool:
	if not initialized or pending or solver._writes_locked():return false
	pending=true;query_count+=1
	var list:=rd.compute_list_begin();rd.compute_list_bind_compute_pipeline(list,pipeline);rd.compute_list_bind_uniform_set(list,uniform_set,0)
	rd.compute_list_set_push_constant(list,PackedFloat32Array([position.x,position.y,params.yaw_rad,params.scale_xz,params.height_m,solver.current_index,0,0]).to_byte_array(),32)
	rd.compute_list_dispatch(list,1,1,1);rd.compute_list_end()
	if rd.buffer_get_data_async(buffer,_received.bind(callback))!=OK:pending=false;return false
	return true

func _received(bytes:PackedByteArray,callback:Callable) -> void:
	pending=false;callback.call(bytes)

func release() -> void:
	assert(not pending)
	if rd!=null:
		for i in range(owned.size()-1,-1,-1):rd.free_rid(owned[i])
	owned.clear();rd=null;initialized=false

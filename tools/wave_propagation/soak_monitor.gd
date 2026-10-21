extends RefCounted

const SOURCE="res://tools/wave_propagation/soak_monitor.glsl"
var owner
var rd: RenderingDevice
var reference: RID
var stats: RID
var shader: RID
var pipeline: RID
var binding: RID
var original_tail: Callable
var error:=""
var reference_copy_verified:=false

func initialize(value, negative: bool=false) -> void:
	owner=value;rd=owner.state.rd
	var source:=RDShaderSource.new();source.source_compute=FileAccess.get_file_as_string(SOURCE).trim_prefix("#[compute]")
	var spirv:=rd.shader_compile_spirv_from_source(source);error=spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
	if not error.is_empty():return
	shader=rd.shader_create_from_spirv(spirv);pipeline=rd.compute_pipeline_create(shader)
	var format:=RDTextureFormat.new();format.width=256;format.height=256;format.format=RenderingDevice.DATA_FORMAT_R32_SFLOAT
	format.usage_bits=RenderingDevice.TEXTURE_USAGE_STORAGE_BIT|RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT|RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT|RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT
	reference=rd.texture_create(format,RDTextureView.new())
	var initial: PackedByteArray=rd.texture_get_data(owner.state.textures.water[0],0)
	var copied:=initial.duplicate()
	if negative:
		var values:=copied.to_float32_array()
		for i in values.size():values[i]+=0.001
		copied=values.to_byte_array()
	rd.texture_update(reference,0,copied)
	reference_copy_verified=reference!=owner.state.textures.water[0] and rd.texture_get_data(reference,0)==copied
	var zero:=PackedByteArray();zero.resize(16);stats=rd.storage_buffer_create(16,zero)
	var uniforms: Array[RDUniform]=[]
	var images: Array=[owner.state.textures.water[0],owner.state.textures.sand[0],owner.state.textures.sediment[0],owner.state.textures.momentum_x[0],owner.state.textures.momentum_z[0],reference]
	for i in images.size():
		var uniform:=RDUniform.new();uniform.uniform_type=RenderingDevice.UNIFORM_TYPE_IMAGE;uniform.binding=i;uniform.add_id(images[i]);uniforms.append(uniform)
	var buffer:=RDUniform.new();buffer.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER;buffer.binding=6;buffer.add_id(stats);uniforms.append(buffer)
	binding=rd.uniform_set_create(uniforms,shader,0)
	if not reference_copy_verified or not binding.is_valid():error="monitor_initialization";return
	original_tail=owner.water.tail_recorder;owner.water.tail_recorder=record_tick

func record_tick(decision: RID) -> void:
	if original_tail.is_valid():original_tail.call(decision)
	var list:=rd.compute_list_begin();rd.compute_list_bind_compute_pipeline(list,pipeline);rd.compute_list_bind_uniform_set(list,binding,0);rd.compute_list_dispatch(list,32,32,1);rd.compute_list_end()

func release() -> void:
	if owner!=null and owner.water!=null:owner.water.tail_recorder=original_tail
	for rid in [binding,pipeline,shader,stats,reference]:
		if rid.is_valid():rd.free_rid(rid)
	binding=RID();pipeline=RID();shader=RID();stats=RID();reference=RID();original_tail=Callable();owner=null;rd=null

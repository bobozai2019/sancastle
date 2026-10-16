extends "res://tests/shape_brushes/snapshot_retention_lab.gd"

const TRACE_MAX_EVENTS := 2048
const TRACE_PIXELS := 48
const TRACE_EVENT_BYTES := 3*TRACE_PIXELS*24*4
const HASH_EVENT_BYTES := 3*64*15*2*4
var trace_owned: Array[RID]=[]
var trace_images: Array[RID]=[]
var trace_buffer:=RID()
var hash_buffer:=RID()
var trace_shader:=RID()
var trace_pipeline:=RID()
var trace_sets: Array[RID]=[]
var trace_event_count:=0
var trace_identity := {}

func trace_own(rid: RID) -> RID:
	if rid.is_valid(): trace_owned.append(rid)
	return rid

func _render_setup(target: SandWaterDomain, token: int) -> void:
	super._render_setup(target,token)
	if snapshot_device==null or snapshot_inputs.size()!=8: return
	trace_buffer=trace_own(snapshot_device.storage_buffer_create(TRACE_MAX_EVENTS*TRACE_EVENT_BYTES))
	var zeros:=PackedByteArray();zeros.resize(TRACE_MAX_EVENTS*HASH_EVENT_BYTES);zeros.fill(0)
	hash_buffer=trace_own(snapshot_device.storage_buffer_create(zeros.size(),zeros))
	for format_id in [RenderingDevice.DATA_FORMAT_R32_SFLOAT,RenderingDevice.DATA_FORMAT_R32_SFLOAT,RenderingDevice.DATA_FORMAT_R16_SFLOAT,RenderingDevice.DATA_FORMAT_R16_SFLOAT]:
		trace_images.append(trace_own(solver._create_texture(format_id,PackedByteArray())))
	var source:=RDShaderSource.new();source.source_compute=FileAccess.get_file_as_string("res://tests/shape_brushes/stage_log_diagnostic.glsl").replace("#[compute]","")
	var code:=snapshot_device.shader_compile_spirv_from_source(source)
	var error:=code.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
	if not error.is_empty(): call_deferred("_fail","stage log compile failed: "+error);return
	trace_shader=trace_own(snapshot_device.shader_create_from_spirv(code));trace_pipeline=trace_own(snapshot_device.compute_pipeline_create(trace_shader))
	var buffer:=RDUniform.new();buffer.binding=0;buffer.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER;buffer.add_id(trace_buffer)
	var hash_uniform:=RDUniform.new();hash_uniform.binding=1;hash_uniform.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER;hash_uniform.add_id(hash_buffer)
	var uniforms: Array[RDUniform]=[buffer,hash_uniform]
	trace_sets.append(trace_own(snapshot_device.uniform_set_create(uniforms,trace_shader,0)))
	uniforms=[];var images: Array[RID]=snapshot_inputs.duplicate();images.append_array(trace_images)
	for binding in images.size():
		var u:=RDUniform.new();u.binding=binding;u.uniform_type=RenderingDevice.UNIFORM_TYPE_IMAGE;u.add_id(images[binding]);uniforms.append(u)
	trace_sets.append(trace_own(snapshot_device.uniform_set_create(uniforms,trace_shader,1)))
	trace_identity={"max_events":TRACE_MAX_EVENTS,"event_bytes":TRACE_EVENT_BYTES,"pixels_per_stage":TRACE_PIXELS,"hash_event_bytes":HASH_EVENT_BYTES,"hash_tiles":64,"hash_fields":15,"hash_words_per_field":2,"stages":3,"logger_source_sha256":FileAccess.get_sha256("res://tests/shape_brushes/stage_log_diagnostic.glsl"),"snapshot_identity":snapshot_identity.duplicate(true),"scope":"48 raw pixels plus full-grid tile integer locator hashes; hashes do not replace full raw identity. Extra GPU work can affect scheduling."}

func _trace_stage(phase: int, delta_s: float) -> bool:
	var live: int=solver.current_index
	var sources: Array[RID]=[solver.textures.sand[live],solver.textures.sediment[live],solver.textures.wetness[live],solver.textures.compaction[live]]
	for i in sources.size():
		if snapshot_device.texture_copy(sources[i],trace_images[i],Vector3.ZERO,Vector3.ZERO,Vector3(256,256,1),0,0,0,0)!=OK: return false
	var dt_bits:=PackedFloat32Array([delta_s]).to_byte_array().decode_u32(0)
	var list:=snapshot_device.compute_list_begin();snapshot_device.compute_list_bind_compute_pipeline(list,trace_pipeline)
	for i in 2: snapshot_device.compute_list_bind_uniform_set(list,trace_sets[i],i)
	snapshot_device.compute_list_set_push_constant(list,PackedInt32Array([trace_event_count,phase,completed_ticks+1,solver.state_revision,live,dt_bits,TRACE_PIXELS,24]).to_byte_array(),32)
	snapshot_device.compute_list_dispatch(list,32,32,1);snapshot_device.compute_list_end()
	return true

func _dispatch_coupled_substep(delta_s: float) -> bool:
	if trace_event_count>=TRACE_MAX_EVENTS or trace_sets.size()!=2: return false
	var live: int=solver.current_index;var old:=1-live
	var sources: Array[RID]=[solver.textures.sediment[old],solver.textures.water[old],solver.textures.flux[live],solver.textures.obstacle,solver.textures.sand[old],solver.textures.wetness[old],solver.textures.compaction[old],solver.textures.water[live]]
	for i in sources.size():
		if snapshot_device.texture_copy(sources[i],snapshot_inputs[i],Vector3.ZERO,Vector3.ZERO,Vector3(256,256,1),0,0,0,0)!=OK: return false
	snapshot_copy_count+=1
	if not _trace_stage(0,delta_s) or not sediment_coupler.dispatch_after_water_substep(delta_s): return false
	if not _trace_stage(1,delta_s) or not material_coupler.dispatch_after_erosion(delta_s): return false
	if not _trace_stage(2,delta_s): return false
	trace_event_count+=1
	return true

func _render_release() -> void:
	var device:=snapshot_device
	# Logger sets reference snapshot inputs; release these before their owner.
	if device!=null:
		for i in range(trace_owned.size()-1,-1,-1): device.free_rid(trace_owned[i])
	trace_owned.clear();trace_sets.clear();trace_images.clear();trace_buffer=RID();hash_buffer=RID();trace_shader=RID();trace_pipeline=RID()
	super._render_release()

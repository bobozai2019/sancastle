extends RefCounted

# All record methods run consecutively on the same RD as ordinary edits/water.
# No CPU shadow, old publication authorization, collision wait or legacy bridge.
const Brush=preload("res://scripts/simulation/brushes/brush_protocol.gd")
enum Mode { BEGIN, SHAPE, END, SMOOTH, COMPACT, GRAVEL }
var solver
var shape
var gravel
var visuals
var rd: RenderingDevice
var owned: Array[RID]=[]
var kernels:={}
var bindings: Array[Dictionary]=[]
var stroke:=RID()
var last_error:=""

func _own(rid: RID) -> RID:
	owned.append(rid)
	return rid

func _compile(name: String, path: String, replacements: Dictionary={}) -> bool:
	var source:=RDShaderSource.new()
	source.source_compute=FileAccess.get_file_as_string(path).trim_prefix("#[compute]")
	for key in replacements:source.source_compute=source.source_compute.replace(key,replacements[key])
	var code:=rd.shader_compile_spirv_from_source(source)
	last_error=code.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
	if not last_error.is_empty():last_error=name+": "+last_error;return false
	var shader:=_own(rd.shader_create_from_spirv(code))
	kernels[name]={"shader":shader,"pipeline":_own(rd.compute_pipeline_create(shader))}
	return shader.is_valid() and kernels[name].pipeline.is_valid()

func _binding(name: String, group: int, images: Array, buffers: Array) -> RID:
	var uniforms: Array[RDUniform]=[]
	var index:=0
	for resources in [images,buffers]:
		for rid in resources:
			var u:=RDUniform.new();u.binding=index
			u.uniform_type=RenderingDevice.UNIFORM_TYPE_IMAGE if resources==images else RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
			u.add_id(rid);uniforms.append(u);index+=1
	return _own(rd.uniform_set_create(uniforms,kernels[name].shader,group))

func initialize(target, brush, stones, visual_recorder) -> bool:
	solver=target;shape=brush;gravel=stones;visuals=visual_recorder;rd=target.rd
	if shape==null:return false
	stroke=_own(rd.storage_buffer_create(32))
	var base:="res://scripts/simulation/edit_validation/frame_pipeline/"
	for name in ["tool_select","tool_capture","smooth"]:
		if not _compile(name,base+"async_"+name+".glsl"):return false
	var common: Array=[shape.buffers.command,shape.buffers.receipt,shape.buffers.cells,solver.async_transport.control]
	kernels.smooth.binding=_binding("smooth",0,[],common)
	kernels.smooth.images=_binding("smooth",1,[solver.textures.sand[0],solver.textures.sand[1],solver.textures.compaction[0],solver.textures.compaction[1],solver.textures.mold_support[0],solver.textures.mold_support[1]],[])
	if gravel!=null:
		var guard:="layout(set=1,binding=0,std430) readonly buffer AsyncControl {uint async_control[];};\nvoid main() {\n if(async_control[1]!=0u)return;"
		if not _compile("gravel_add","res://shaders/simulation/visual_gravel_step.glsl",{"void main() {":guard}):return false
		kernels.gravel_add.control=_binding("gravel_add",1,[],[solver.async_transport.control])
		if not _compile("gravel_normalize",base+"async_gravel_normalize.glsl"):return false
		kernels.gravel_normalize.binding=_binding("gravel_normalize",0,[gravel.textures[1-gravel.current_index],gravel.textures[gravel.current_index]],[solver.async_transport.control])
	for slot in solver.async_transport.resources:
		bindings.append({"select":_binding("tool_select",0,[],[slot.input,shape.buffers.command,shape.buffers.receipt,solver.async_transport.control,stroke]),"capture":_binding("tool_capture",0,[],[shape.buffers.command,shape.buffers.receipt,solver.async_transport.control,slot.completion])})
	for rid in owned:
		if not rid.is_valid():return false
	return true

static func mode(command: Dictionary) -> int:
	if command.has("async_operation"):return int(command.async_operation)
	if command.get("schema_version")==2:return Mode.SHAPE
	return Mode.SMOOTH if command.get("kind")==&"smooth" else Mode.COMPACT

static func encode(command: Dictionary, ticket: int) -> PackedByteArray:
	if mode(command)==Mode.SHAPE:return Brush.encode(command,ticket,0)
	var bytes:=PackedByteArray();bytes.resize(256)
	bytes.encode_u32(0,Brush.COMMAND_MAGIC);bytes.encode_u32(4,2);bytes.encode_u32(8,256)
	for pair in [[16,ticket],[24,command.command_id],[32,command.get("stroke_id",0)],[40,command.generation],[64,command.get("baseline_token",0)]]:bytes.encode_s64(pair[0],pair[1])
	if mode(command) in [Mode.SMOOTH,Mode.COMPACT]:
		var a: Vector3=command.transform.position_m
		var b: Vector3=command.transform.get("end_position_m",a)
		var radius: float=command.radius_m
		for pair in [[96,a.x],[100,a.z],[104,b.x],[108,b.z],[112,radius],[116,command.strength]]:bytes.encode_float(pair[0],pair[1])
		var lo:=(Vector2(a.x,a.z).min(Vector2(b.x,b.z))-Vector2.ONE*radius+Vector2.ONE*16.0)/0.125-Vector2.ONE*0.5
		var hi:=(Vector2(a.x,a.z).max(Vector2(b.x,b.z))+Vector2.ONE*radius+Vector2.ONE*16.0)/0.125-Vector2.ONE*0.5
		for pair in [[128,clampi(floori(lo.x)-1,0,255)],[132,clampi(floori(lo.y)-1,0,255)],[136,clampi(ceili(hi.x)+1,0,255)],[140,clampi(ceili(hi.y)+1,0,255)]]:bytes.encode_u32(pair[0],pair[1])
	return bytes

func _dispatch(name: String, binding: RID, push: PackedByteArray, groups: Vector3i=Vector3i.ONE, image_binding: RID=RID()) -> void:
	var list:=rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list,kernels[name].pipeline)
	rd.compute_list_bind_uniform_set(list,binding,0)
	if image_binding.is_valid():rd.compute_list_bind_uniform_set(list,image_binding,1)
	rd.compute_list_set_push_constant(list,push,push.size())
	rd.compute_list_dispatch(list,groups.x,groups.y,groups.z)
	rd.compute_list_end()

func submit(id: Dictionary, command: Dictionary, ticket: int, callback: Callable) -> String:
	if mode(command) not in [Mode.BEGIN,Mode.SHAPE,Mode.END,Mode.SMOOTH,Mode.COMPACT,Mode.GRAVEL]:return "tool_kind"
	var bytes:=encode(command,ticket)
	if bytes.size()!=256:return "tool_command_size"
	if mode(command)==Mode.SHAPE and bytes.decode_u32(12)==1 and bytes.slice(216,248).hex_encode()!=shape.castle_template_sha256:return "tool_template_identity"
	return solver.async_transport.submit(id,bytes,_record.bind(id,command,bytes),callback,256,256)

func _record(_input: RID, _control: RID, _count: int, id: Dictionary, command: Dictionary, bytes: PackedByteArray) -> void:
	var kind:=mode(command)
	var inject:=1 if shape.inject_candidate_failure_once and kind==Mode.SHAPE else 0
	shape.inject_candidate_failure_once=false
	_dispatch("tool_select",bindings[id.slot_id].select,PackedInt32Array([kind,inject,0,0]).to_byte_array())
	solver.active_ticket=bytes.decode_s64(16)
	if kind==Mode.BEGIN:
		shape._dispatch(0)
		shape.active=true;shape.stroke_id=command.stroke_id;shape.baseline_token=command.baseline_token;shape.baseline_copy_count+=1
	elif kind==Mode.END:
		shape.active=false;shape.stroke_id=0;shape.baseline_token=0;shape.last_sample=-1
	elif kind==Mode.SHAPE:
		# Preserve the existing geometry, donor allocation and candidate validation.
		# Authority writes happen only after all sand/material/water checks on GPU.
		if bytes.decode_u32(12)==1:shape._dispatch(1,1)
		shape._dispatch(1)
		if bytes.decode_u32(12)==3:shape._dispatch(6)
		shape.material_transaction.dispatch(0)
		for stage in [2,3]:shape._dispatch(stage)
		if shape.water_transaction!=null:shape.water_transaction.prepare(bytes)
		shape._dispatch(4);shape.material_transaction.dispatch(1)
		if shape.water_transaction!=null:shape.water_transaction.commit()
		if bytes.decode_u32(92)==1:solver.mold_field_ever_used=true
	elif kind in [Mode.SMOOTH,Mode.COMPACT]:
		_dispatch("smooth",kernels.smooth.binding,PackedInt32Array([kind,0,0,0]).to_byte_array(),Vector3i.ONE,kernels.smooth.images)
		var size:=Vector3i(bytes.decode_u32(136)-bytes.decode_u32(128)+1,bytes.decode_u32(140)-bytes.decode_u32(132)+1,1)
		_dispatch("smooth",kernels.smooth.binding,PackedInt32Array([kind,1,0,0]).to_byte_array(),size,kernels.smooth.images)
	elif kind==Mode.GRAVEL:
		_record_gravel(command)
	_dispatch("tool_capture",bindings[id.slot_id].capture,PackedInt32Array([kind,0,0,0]).to_byte_array())
	solver.publish_sand()

func _record_gravel(command: Dictionary) -> void:
	var old: int=gravel.active_count
	gravel.active_count+=int(command.count)
	var p: Dictionary=gravel.profile
	var position: Vector2=command.point
	var push:=PackedInt32Array([gravel.active_count,p.capacity,p.seed,3]).to_byte_array()
	push.append_array(PackedFloat32Array([solver.grid_size,solver.cell_size_m,0,1,p.h_on_m,p.h_off_m,p.speed_on_m_s,p.speed_off_m_s,p.response_min,p.response_max,p.h_epsilon_m,p.speed_cap_m_s,position.x-0.45,position.y-0.45,position.x+0.45,position.y+0.45,1.0 if p.bed_reconstruction else 0.0,old,0,0]).to_byte_array())
	var binding: RID=gravel.uniform_sets[0][gravel.current_index]
	_dispatch("gravel_add",binding,push,Vector3i(16,1,1),kernels.gravel_add.control)
	# Keep the established read slot fixed, just like async_visual_normalize.
	_dispatch("gravel_normalize",kernels.gravel_normalize.binding,PackedInt32Array([0,0,0,0]).to_byte_array(),Vector3i(16,1,1))

func decode(bytes: PackedByteArray, command: Dictionary, ticket: int) -> Dictionary:
	if bytes.size()!=256:return {"error":"tool_receipt_size"}
	if mode(command)==Mode.SHAPE:
		var value:=Brush.decode_receipt(bytes)
		if not value.get("ok",false) or not Brush.receipt_matches(value,command,ticket,value.get("input_revision",-1)):return {"error":"tool_receipt_invalid"}
		value.gpu_complete=true
		return value
	if bytes.decode_u32(0)!=Brush.RECEIPT_MAGIC or bytes.decode_u32(4)!=2 or bytes.decode_u32(8)!=256 or bytes.decode_s64(16)!=ticket or bytes.decode_s64(24)!=command.command_id or bytes.decode_s64(40)!=command.generation or bytes.decode_u32(12) not in [1,2,3]:return {"error":"tool_receipt_identity"}
	var before:=bytes.decode_s64(48);var after:=bytes.decode_s64(56)
	if before<0 or after<0 or bytes.decode_s64(64)<0 or bytes.decode_u32(80)>18 or bytes.decode_u32(88)>65536:return {"error":"tool_receipt_value"}
	var changed: bool=mode(command) in [Mode.SMOOTH,Mode.COMPACT] and bytes.decode_u32(12)==1
	if after!=before+(1 if changed else 0):return {"error":"tool_receipt_revision"}
	if mode(command) in [Mode.BEGIN,Mode.END] and (bytes.decode_s64(32)!=command.stroke_id or bytes.decode_s64(72)!=command.baseline_token):return {"error":"tool_receipt_stroke"}
	return {"gpu_complete":true,"status":bytes.decode_u32(12),"error_code":bytes.decode_u32(80),"input_revision":bytes.decode_s64(48),"output_revision":bytes.decode_s64(56),"applied_tick":bytes.decode_s64(64),"edited_cells":bytes.decode_u32(88)}

func release() -> void:
	if rd!=null:
		for index in range(owned.size()-1,-1,-1):
			if owned[index].is_valid():rd.free_rid(owned[index])
	owned.clear();bindings.clear();kernels.clear();rd=null

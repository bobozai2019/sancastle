extends RefCounted

const STAGES := ["water_prepare","water_velocity","water_merge","water_commit"]
var rd:RenderingDevice
var solver
var owned:Array[RID]=[]
var shaders:Array[RID]=[]
var pipelines:Array[RID]=[]
var sets:Array=[]
var backups:Array[RID]=[]
var last_error:=""
var policy:=0

func own(rid:RID) -> RID:
	if rid.is_valid():owned.append(rid)
	return rid

func uniform_set(stage:int,group:int,buffers:Dictionary,images:Dictionary) -> RID:
	var uniforms:Array[RDUniform]=[]
	for key in buffers:
		var u:=RDUniform.new();u.binding=key;u.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER;u.add_id(buffers[key]);uniforms.append(u)
	for key in images:
		var u:=RDUniform.new();u.binding=key;u.uniform_type=RenderingDevice.UNIFORM_TYPE_IMAGE;u.add_id(images[key]);uniforms.append(u)
	return own(rd.uniform_set_create(uniforms,shaders[stage],group))

func initialize(owner,buffers:Dictionary) -> bool:
	solver=owner;rd=owner.rd
	for stage in STAGES:
		var source:=RDShaderSource.new();source.source_compute=FileAccess.get_file_as_string("res://shaders/simulation/brushes/"+stage+".glsl").replace("#[compute]","")
		var code:=rd.shader_compile_spirv_from_source(source);last_error=code.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
		if not last_error.is_empty():return false
		var shader:=own(rd.shader_create_from_spirv(code));shaders.append(shader);pipelines.append(own(rd.compute_pipeline_create(shader)))
	var live:Dictionary={};var rollback:Dictionary={}
	for field in ["water","sediment","momentum_x","momentum_z"]:
		for slot in 2:
			var binding:=live.size();live[binding]=solver.textures[field][slot]
			var backup:=own(solver._create_texture(RenderingDevice.DATA_FORMAT_R32_SFLOAT,PackedByteArray()));backups.append(backup);rollback[binding+8]=backup
	var read:Dictionary=live.duplicate();read[8]=solver.textures.obstacle
	sets.append([uniform_set(0,0,{0:buffers.cells,1:buffers.receipt,2:owner.water_input},{}),uniform_set(0,1,{},read)])
	sets.append([uniform_set(1,0,{0:buffers.command,1:buffers.cells,2:owner.water_candidate,3:owner.water_scratch,4:owner.water_receipt},{}),RID()])
	sets.append([uniform_set(2,0,{0:buffers.receipt,1:owner.water_receipt,2:owner.water_input,3:owner.water_candidate,4:buffers.cells},{}),RID()])
	live.merge(rollback);sets.append([uniform_set(3,0,{0:buffers.receipt,1:owner.water_input,2:owner.water_candidate},{}),uniform_set(3,1,{},live)])
	for rid in owned:
		if not rid.is_valid():return false
	return owned.size()==22

func backup() -> bool:
	var k:=0
	for field in ["water","sediment","momentum_x","momentum_z"]:
		for slot in 2:
			if rd.texture_copy(solver.textures[field][slot],backups[k],Vector3.ZERO,Vector3.ZERO,Vector3(256,256,1),0,0,0,0)!=OK:return false
			k+=1
	return true

func dispatch(stage:int,phase:int=0) -> void:
	var mark: String="edit_shape_water_%d_%d" % [stage,phase]
	if solver.profile_passes: rd.capture_timestamp(mark+"_start")
	var list:=rd.compute_list_begin();rd.compute_list_bind_compute_pipeline(list,pipelines[stage]);rd.compute_list_bind_uniform_set(list,sets[stage][0],0)
	if sets[stage][1].is_valid():rd.compute_list_bind_uniform_set(list,sets[stage][1],1)
	rd.compute_list_set_push_constant(list,PackedInt32Array([256,solver.current_index,phase,policy,0,0,0,0]).to_byte_array(),32)
	rd.compute_list_dispatch(list,1 if stage==2 else 1024,1,1);rd.compute_list_end()
	if solver.profile_passes: rd.capture_timestamp(mark+"_end")

func prepare(data:PackedByteArray) -> void:
	policy=data.decode_u32(88);solver.active_policy=policy
	var clear:=PackedByteArray();clear.resize(128);clear.fill(0)
	rd.buffer_update(solver.water_receipt,0,128,clear)
	var bridge:=clear.duplicate();bridge.encode_u32(80,256);bridge.encode_float(76,0.125);bridge.encode_u32(84,policy);bridge.encode_float(108,data.decode_float(164))
	rd.buffer_update(solver.command_buffer,0,128,bridge)
	dispatch(0)
	if policy==0:return
	if solver.fast_full_wet and policy!=2:solver._water_dispatch(7)
	solver._water_dispatch(1);solver.inject_water_loss_once=false
	dispatch(1);solver._water_dispatch(6);dispatch(2)

func commit() -> void:dispatch(3)
func rollback() -> void:dispatch(3,1)
func statistics() -> Dictionary:return {"rid_count":owned.size(),"bytes":8*256*256*4,"reuses":"original water input/candidate/scratch/receipt and displacement/CFL stages"}
func release() -> void:
	if rd!=null:
		for i in range(owned.size()-1,-1,-1):rd.free_rid(owned[i])
	owned.clear();backups.clear();sets.clear();rd=null

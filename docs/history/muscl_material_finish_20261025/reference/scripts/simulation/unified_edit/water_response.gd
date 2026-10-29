extends "res://scripts/simulation/unified_edit/gpu.gd"

# Shared edit response. Only commit() writes physical water/sediment/momentum;
# all numerics below operate on private input/candidate/scratch buffers.
const SOURCES=["res://scripts/simulation/unified_edit/water_response.gd","res://scripts/simulation/unified_edit/water_response.glsl","res://shaders/simulation/edit_validation/water_displace_compensated.glsl","res://shaders/simulation/edit_validation/water_packed_cached.glsl","res://shaders/simulation/edit_validation/water_velocity_prefetch.glsl","res://scripts/simulation/unified_edit/water_packed_topology.glsl","res://scripts/simulation/unified_edit/water_packed_parallel.glsl","res://scripts/simulation/unified_edit/water_velocity_prepare.glsl"]
var state
var owner
var buffers: Dictionary={}
var sets: Dictionary={}
var inject_water_loss_once:=false # Private probe fault; never a profile capability.

func initialize(executor) -> bool:
	owner=executor;state=owner.state;rd=owner.rd
	for pair in [["input",65536*32],["candidate",65536*16],["scratch",65536*20],["receipt",128],["bridge",128],["indirect",36],["components",16+32*96],["parallel_work",65536*48],["velocity_checks",256*8]]:
		var zero:=PackedByteArray();zero.resize(pair[1]);buffers[pair[0]]=own(rd.storage_buffer_create(pair[1],zero,RenderingDevice.STORAGE_BUFFER_USAGE_DISPATCH_INDIRECT if pair[0]=="indirect" else 0))
		if not buffers[pair[0]].is_valid():last_error="response_buffer";return false
	if not compile("response",SOURCES[1]):return false
	sets.response=binding("response",{0:owner.buffers.command,1:owner.buffers.cells,2:owner.buffers.summary,3:owner.buffers.decision,4:owner.transport.control,5:buffers.input,6:buffers.candidate,7:buffers.receipt,8:buffers.scratch,9:buffers.bridge,19:buffers.indirect},{10:state.textures.rock,11:state.textures.sand[0],12:state.textures.water[0],13:state.textures.water[1],14:state.textures.sediment[0],15:state.textures.sediment[1],16:state.textures.momentum[0],17:state.textures.momentum[1],18:state.textures.obstacle})
	for pair in [["displace",SOURCES[2]],["packed",SOURCES[5]],["velocity_reduce",SOURCES[4]],["packed_math",SOURCES[6]],["velocity_prepare",SOURCES[7]]]:
		if not compile(pair[0],pair[1]):return false
	if not _initialize_packed_phases():return false
	if not _initialize_velocity_prepare_phases():return false
	sets.displace=binding("displace",{0:buffers.input,1:buffers.candidate,2:buffers.scratch,3:buffers.receipt})
	sets.packed=binding("packed",{0:buffers.input,1:buffers.candidate,2:buffers.scratch,3:buffers.receipt,4:buffers.components})
	sets.packed_math=binding("packed_math",{0:buffers.input,1:buffers.candidate,2:buffers.scratch,3:buffers.receipt,4:buffers.components,5:buffers.parallel_work})
	sets.velocity_reduce=binding("velocity_reduce",{0:buffers.bridge,1:buffers.candidate,2:buffers.scratch,3:buffers.receipt})
	sets.velocity_prepare=binding("velocity_prepare",{0:buffers.input,1:buffers.candidate,2:buffers.scratch,3:buffers.receipt,4:buffers.velocity_checks,5:owner.buffers.decision,6:owner.transport.control})
	for value in sets.values():
		if not value.is_valid():last_error="response_uniform";return false
	return true

func _initialize_packed_phases() -> bool:
	# Specialize uniform phase branches before native shader compilation, so
	# per-cell passes do not carry reduction-only shared storage or control flow.
	kernels.packed_math.phases=[]
	for mode in 11:
		var constant:=RDPipelineSpecializationConstant.new()
		constant.constant_id=0;constant.value=mode
		var constants: Array[RDPipelineSpecializationConstant]=[constant]
		var pipeline:=own(rd.compute_pipeline_create(kernels.packed_math.shader,constants))
		if not pipeline.is_valid():last_error="response_phase_"+str(mode);return false
		kernels.packed_math.phases.append(pipeline)
	return true

func _legacy_dispatch(name: String, push: PackedByteArray) -> void:
	var list:=rd.compute_list_begin();rd.compute_list_bind_compute_pipeline(list,kernels[name].pipeline)
	rd.compute_list_bind_uniform_set(list,sets[name],0)
	if not push.is_empty():rd.compute_list_set_push_constant(list,push,push.size())
	rd.compute_list_dispatch_indirect(list,buffers.indirect,{"packed":0,"displace":12,"velocity_reduce":24}[name]);rd.compute_list_end()
	if name=="packed":_packed_math(push)

func _packed_math(push: PackedByteArray) -> void:
	# GPU-only phase boundaries. Per-cell math spans all SMs; component reductions
	# retain the reference's row-major compensated order and bounded repair.
	var phase_push:=push.duplicate()
	for mode in 11:
		phase_push.encode_u32(8,mode)
		_packed_phase(mode,phase_push)

func _packed_phase(mode: int, push: PackedByteArray) -> void:
	var groups:=1024 if mode in [1,3,5,8] else (1 if mode==10 else 32)
	var list:=rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list,kernels.packed_math.phases[mode])
	rd.compute_list_bind_uniform_set(list,sets.packed_math,0)
	rd.compute_list_set_push_constant(list,push,push.size())
	rd.compute_list_dispatch(list,groups,1,1);rd.compute_list_end()

func _initialize_velocity_prepare_phases() -> bool:
	kernels.velocity_prepare.phases=[]
	for mode in 2:
		var constant:=RDPipelineSpecializationConstant.new()
		constant.constant_id=0;constant.value=mode
		var constants: Array[RDPipelineSpecializationConstant]=[constant]
		var pipeline:=own(rd.compute_pipeline_create(kernels.velocity_prepare.shader,constants))
		if not pipeline.is_valid():last_error="velocity_prepare_phase_"+str(mode);return false
		kernels.velocity_prepare.phases.append(pipeline)
	return true

func _velocity_only() -> void:
	for mode in 2:
		var list:=rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(list,kernels.velocity_prepare.phases[mode])
		rd.compute_list_bind_uniform_set(list,sets.velocity_prepare,0)
		rd.compute_list_dispatch(list,256 if mode==0 else 1,1,1)
		rd.compute_list_end()

func record(policy: int) -> Array:
	var inject:=inject_water_loss_once;inject_water_loss_once=false
	dispatch("response",sets.response,Vector3i(256,1,1),PackedInt32Array([0,0,0,0]).to_byte_array())
	var push:=PackedFloat32Array([0,0.125,0,0]).to_byte_array();push.encode_u32(0,256)
	if policy==2:_velocity_only()
	else:
		if not inject:_legacy_dispatch("packed",push)
		push.encode_u32(8,1 if inject else 0);push.encode_u32(12,0 if inject else 2);_legacy_dispatch("displace",push)
	dispatch("response",sets.response,Vector3i(256,1,1),PackedInt32Array([1,0,0,0]).to_byte_array())
	_legacy_dispatch("velocity_reduce",PackedByteArray())
	dispatch("response",sets.response,Vector3i(256,1,1),PackedInt32Array([2,0,0,0]).to_byte_array())
	dispatch("response",sets.response,Vector3i(1,1,1),PackedInt32Array([3,0,0,0]).to_byte_array())
	return ["prepare","velocity_only" if policy==2 else ("generic_injected_loss" if inject else "packed"),"velocity_prepare_parallel" if policy==2 else "displace","momentum_B" if policy==2 else "velocity","velocity_reduce","audit_blocks","audit_merge"]

func commit() -> void:
	dispatch("response",sets.response,Vector3i(256,1,1),PackedInt32Array([4,0,0,0]).to_byte_array())

func release() -> void:
	sets.clear();buffers.clear();state=null;owner=null;super.release()

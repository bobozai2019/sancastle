extends "res://scripts/simulation/unified_edit/gpu.gd"

# Shared edit response. Only commit() writes physical water/sediment/momentum;
# all numerics below operate on private input/candidate/scratch buffers.
const SOURCES=["res://scripts/simulation/unified_edit/water_response.gd","res://scripts/simulation/unified_edit/water_response.glsl","res://shaders/simulation/edit_validation/water_displace_compensated.glsl","res://shaders/simulation/edit_validation/water_packed_cached.glsl","res://shaders/simulation/edit_validation/water_velocity_prefetch.glsl"]
var state
var owner
var buffers: Dictionary={}
var sets: Dictionary={}
var inject_water_loss_once:=false # Private probe fault; never a profile capability.

func initialize(executor) -> bool:
	owner=executor;state=owner.state;rd=owner.rd
	for pair in [["input",65536*32],["candidate",65536*16],["scratch",65536*20],["receipt",128],["bridge",128],["indirect",36]]:
		var zero:=PackedByteArray();zero.resize(pair[1]);buffers[pair[0]]=own(rd.storage_buffer_create(pair[1],zero,RenderingDevice.STORAGE_BUFFER_USAGE_DISPATCH_INDIRECT if pair[0]=="indirect" else 0))
		if not buffers[pair[0]].is_valid():last_error="response_buffer";return false
	if not compile("response",SOURCES[1]):return false
	sets.response=binding("response",{0:owner.buffers.command,1:owner.buffers.cells,2:owner.buffers.summary,3:owner.buffers.decision,4:owner.transport.control,5:buffers.input,6:buffers.candidate,7:buffers.receipt,8:buffers.scratch,9:buffers.bridge,21:buffers.indirect},{10:state.textures.rock,11:state.textures.sand[0],12:state.textures.water[0],13:state.textures.water[1],14:state.textures.sediment[0],15:state.textures.sediment[1],16:state.textures.momentum_x[0],17:state.textures.momentum_x[1],18:state.textures.momentum_z[0],19:state.textures.momentum_z[1],20:state.textures.obstacle})
	for pair in [["displace",SOURCES[2]],["packed",SOURCES[3]],["velocity_reduce",SOURCES[4]]]:
		if not compile(pair[0],pair[1]):return false
	for name in ["displace","packed"]:sets[name]=binding(name,{0:buffers.input,1:buffers.candidate,2:buffers.scratch,3:buffers.receipt})
	sets.velocity_reduce=binding("velocity_reduce",{0:buffers.bridge,1:buffers.candidate,2:buffers.scratch,3:buffers.receipt})
	for value in sets.values():
		if not value.is_valid():last_error="response_uniform";return false
	return true

func _legacy_dispatch(name: String, push: PackedByteArray) -> void:
	var list:=rd.compute_list_begin();rd.compute_list_bind_compute_pipeline(list,kernels[name].pipeline)
	rd.compute_list_bind_uniform_set(list,sets[name],0)
	if not push.is_empty():rd.compute_list_set_push_constant(list,push,push.size())
	rd.compute_list_dispatch_indirect(list,buffers.indirect,{"packed":0,"displace":12,"velocity_reduce":24}[name]);rd.compute_list_end()

func record(policy: int) -> Array:
	var inject:=inject_water_loss_once;inject_water_loss_once=false
	dispatch("response",sets.response,Vector3i(256,1,1),PackedInt32Array([0,0,0,0]).to_byte_array())
	var push:=PackedFloat32Array([0,0.125,0,0]).to_byte_array();push.encode_u32(0,256)
	if policy!=2 and not inject:_legacy_dispatch("packed",push)
	push.encode_u32(8,1 if inject else 0);push.encode_u32(12,1 if policy==2 else (0 if inject else 2));_legacy_dispatch("displace",push)
	dispatch("response",sets.response,Vector3i(256,1,1),PackedInt32Array([1,0,0,0]).to_byte_array())
	_legacy_dispatch("velocity_reduce",PackedByteArray())
	dispatch("response",sets.response,Vector3i(256,1,1),PackedInt32Array([2,0,0,0]).to_byte_array())
	dispatch("response",sets.response,Vector3i(1,1,1),PackedInt32Array([3,0,0,0]).to_byte_array())
	return ["prepare","generic_injected_loss" if inject else ("packed" if policy!=2 else "velocity_only"),"displace","velocity","velocity_reduce","audit_blocks","audit_merge"]

func commit() -> void:
	dispatch("response",sets.response,Vector3i(256,1,1),PackedInt32Array([4,0,0,0]).to_byte_array())

func release() -> void:
	sets.clear();buffers.clear();state=null;owner=null;super.release()

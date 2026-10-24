extends "res://scripts/simulation/unified_edit/gpu.gd"

# Render-thread-only. One immutable domain guard and three persistent leases.
const Wire=preload("res://scripts/simulation/unified_edit/protocol.gd")
var control:=RID()
var clock_texture:=RID()
var guard:=RID()
var resources: Array[Dictionary]=[]
var _generation:=0
var _domain_hash:=""
var fault: StringName=&""
var inject_upload_failure_once:=false
var inject_readback_failure_once:=false
var inject_terminal_unavailable:=false
var inject_completion_fault_once:=""
var inject_duplicate_completion_once:=false
var inject_reorder_first_completion:=false
var _held_completion: Dictionary={}
var idle_fence:=RID()
var idle_fence_set:=RID()
var _idle_serial:=0
var _idle_pending:=false
var idle_receipt:=PackedByteArray()
var inject_idle_fence_unavailable:=false

func initialize(device: RenderingDevice, domain: String, epoch: int, native_control: PackedByteArray=PackedByteArray()) -> bool:
	if rd!=null or device==null or domain.is_empty() or epoch<1:return false
	if not native_control.is_empty() and native_control.size()!=L.CONTROL_BYTES:last_error="native_control_size";return false
	rd=device;_generation=epoch;_domain_hash=domain.sha256_text()
	var bytes:=native_control.duplicate();bytes.resize(L.CONTROL_BYTES);bytes.encode_u32(0,L.VERSION);bytes.encode_s64(8,epoch)
	control=own(rd.storage_buffer_create(bytes.size(),bytes))
	guard=own(rd.storage_buffer_create(32,_domain_hash.hex_decode()))
	var format:=RDTextureFormat.new();format.width=1;format.height=1;format.format=RenderingDevice.DATA_FORMAT_R32_SFLOAT
	format.usage_bits=RenderingDevice.TEXTURE_USAGE_STORAGE_BIT|RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT|RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT|RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT|RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
	clock_texture=own(rd.texture_create(format,RDTextureView.new(),[bytes.slice(32,36)]))
	var proof_zero:=PackedByteArray();proof_zero.resize(16)
	idle_fence=own(rd.storage_buffer_create(16,proof_zero))
	if not compile("idle_fence","res://scripts/simulation/unified_edit/idle_fence.glsl"):return false
	idle_fence_set=binding("idle_fence",{0:idle_fence})
	if not idle_fence.is_valid() or not idle_fence_set.is_valid():last_error="idle_fence_create";return false
	for name in ["work_begin","work_seal"]:
		if not compile(name,"res://scripts/simulation/unified_edit/"+name+".glsl"):return false
	for index in L.WORK_SLOTS:
		var input:=own(rd.storage_buffer_create(L.INPUT_BYTES))
		var output:=own(rd.storage_buffer_create(L.OUTPUT_BYTES))
		var begin:=binding("work_begin",{0:input,1:control,2:output,3:guard})
		var seal:=binding("work_seal",{0:input,1:control,2:output},{4:clock_texture})
		resources.append({"input":input,"output":output,"begin":begin,"seal":seal,"identity":{},"readback_done":false,"terminal_pending":false})
		for rid in [input,output,begin,seal]:
			if not rid.is_valid():last_error="transport_binding_failed";return false
	return control.is_valid() and guard.is_valid() and clock_texture.is_valid()

func _matches(id: Dictionary) -> bool:
	return Wire.identity_valid(id) and id.generation==_generation and id.domain_hash==_domain_hash

# Record is a private executor/water method, never supplied by a profile or UI.
# Return distinguishes known-unrecorded from unknown; caller must not replay.
func submit(id: Dictionary, packet: PackedByteArray, record: Callable, callback: Callable, after_seal: Callable=Callable()) -> Dictionary:
	if rd==null or not fault.is_empty() or not _matches(id) or not record.is_valid() or not callback.is_valid():return {"error":&"submit_identity_or_backend","recorded":false}
	var decoded:=Wire.decode_batch(packet,id)
	if not decoded.error.is_empty():return {"error":decoded.error,"recorded":false}
	var slot: Dictionary=resources[id.slot_id]
	if not slot.identity.is_empty():return {"error":&"slot_in_use","recorded":false}
	if inject_upload_failure_once:inject_upload_failure_once=false;return {"error":&"upload_failed","recorded":false}
	if rd.buffer_update(slot.input,0,packet.size(),packet)!=OK:return {"error":&"upload_failed","recorded":false}
	slot.identity=id.duplicate(true);slot.readback_done=false;slot.terminal_pending=false
	dispatch("work_begin",slot.begin,Vector3i.ONE)
	record.call(slot.input,control,slot.output,decoded.commands.size())
	dispatch("work_seal",slot.seal,Vector3i.ONE)
	if after_seal.is_valid():after_seal.call()
	var error: Error=ERR_UNAVAILABLE
	if inject_readback_failure_once:inject_readback_failure_once=false
	else:error=rd.buffer_get_data_async(slot.output,_completed.bind(id.duplicate(true),callback),0,L.COMPLETION_BYTES+decoded.commands.size()*L.RESULT_BYTES)
	if error!=OK:
		fault=&"readback_submit_failed";return {"error":fault,"recorded":true}
	return {"error":&"","recorded":true}

func _completed(bytes: PackedByteArray, id: Dictionary, callback: Callable) -> void:
	if rd==null or not _matches(id) or resources[id.slot_id].identity!=id:return
	resources[id.slot_id].readback_done=true
	if not inject_completion_fault_once.is_empty():
		var mode:=inject_completion_fault_once;inject_completion_fault_once="";bytes=bytes.duplicate()
		if mode=="truncate":bytes=bytes.slice(0,16)
		elif mode=="identity":bytes.encode_s64(L.COMPLETION_I64.batch_seq,id.batch_seq+1)
		elif mode=="unknown_state":bytes.encode_u32(L.COMPLETION_U32.state,99)
	if inject_reorder_first_completion and id.batch_seq==1:
		_held_completion={"bytes":bytes.duplicate(),"identity":id.duplicate(true),"callback":callback};return
	callback.call(bytes,id)
	if inject_duplicate_completion_once:inject_duplicate_completion_once=false;callback.call(bytes,id)
	if not _held_completion.is_empty():
		var held:=_held_completion;_held_completion={};inject_reorder_first_completion=false
		held.callback.call(held.bytes,held.identity)

func retire(id: Dictionary) -> bool:
	if rd==null or not _matches(id):return false
	var slot: Dictionary=resources[id.slot_id]
	if slot.identity!=id or not slot.readback_done:return false
	slot.identity={};return true

func request_terminal(id: Dictionary, callback: Callable) -> void:
	if rd==null or not _matches(id) or resources[id.slot_id].identity!=id:callback.call(id,false);return
	var slot: Dictionary=resources[id.slot_id]
	if slot.readback_done:callback.call(id,true);return
	if slot.terminal_pending:return
	if inject_terminal_unavailable:callback.call(id,false);return
	slot.terminal_pending=true
	if rd.buffer_get_data_async(control,_terminal.bind(id.duplicate(true),callback),0,L.CONTROL_BYTES)!=OK:
		slot.terminal_pending=false;callback.call(id,false)

func _terminal(_bytes: PackedByteArray, id: Dictionary, callback: Callable) -> void:
	if rd==null or not _matches(id) or resources[id.slot_id].identity!=id:return
	resources[id.slot_id].readback_done=true;resources[id.slot_id].terminal_pending=false
	callback.call(id,true)

func has_owned() -> bool:
	for slot in resources:
		if not slot.identity.is_empty():return true
	return false

# Private initialization/idle lifetime proof. No work/command completion, clock,
# revision or lease is fabricated. Unknown submission retains every resource.
func request_idle_proof(callback: Callable) -> void:
	if _idle_pending:return
	if rd==null or has_owned() or not kernels.has("idle_fence") or not idle_fence_set.is_valid() or inject_idle_fence_unavailable or _idle_serial==L.INT64_MAX:callback.call(false);return
	_idle_serial+=1;_idle_pending=true
	var push:=PackedByteArray();push.resize(16);push.encode_s64(0,_idle_serial)
	dispatch("idle_fence",idle_fence_set,Vector3i.ONE,push)
	if rd.buffer_get_data_async(idle_fence,_idle_arrived.bind(_idle_serial,callback),0,16)!=OK:
		_idle_pending=false;callback.call(false)

func _idle_arrived(bytes: PackedByteArray, serial: int, callback: Callable) -> void:
	_idle_pending=false
	idle_receipt=bytes.duplicate()
	callback.call(bytes.size()==16 and bytes.decode_u32(0)==0x31464c49 and bytes.decode_u32(4)==0 and bytes.decode_s64(8)==serial)

func try_release() -> bool:
	if has_owned() or _idle_pending:return false
	_held_completion.clear();resources.clear();super.release();return true

func release() -> void:
	if not try_release():push_error("unified transport release before last consumer")

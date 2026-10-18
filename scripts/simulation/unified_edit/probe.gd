extends "res://scripts/simulation/unified_edit/gpu.gd"

# Owned exclusively by Views; one independent bounded reader on the common RD.
const Codec=preload("res://scripts/simulation/unified_edit/probe_codec.gd")
const SOURCES=["res://scripts/simulation/unified_edit/probe.gd","res://scripts/simulation/unified_edit/probe_codec.gd","res://scripts/simulation/unified_edit/probe.glsl"]
var input:=RID()
var output:=RID()
var query_set:=RID()
var generation:=0
var domain:=""
var serial:=0
var owner_token:=0
var pose_seq:=0
var request_highwater:=0
var closing:=false
var pending:=false
var unknown:=false
var query: Dictionary={}
var hold_delivery:=false
var held: Dictionary={}
var inject_readback_failure_once:=false
var inject_upload_failure_once:=false
var accepted_count:=0
var completed_count:=0
var unknown_count:=0

func initialize(views, dirty: RID) -> bool:
	rd=views.rd;generation=views.generation;domain=String(views.configuration.domain_id)
	input=own(rd.storage_buffer_create(Codec.INPUT_BYTES));output=own(rd.storage_buffer_create(Codec.OUTPUT_BYTES))
	if not compile("probe",SOURCES[2]):return false
	query_set=binding("probe",{0:input,1:output,2:views.state.published_stamp,3:dirty},{4:views.textures.rock,5:views.textures.sand,6:views.textures.water,7:views.textures.momentum_x,8:views.textures.momentum_z,9:views.textures.clock})
	return input.is_valid() and output.is_valid() and query_set.is_valid()

# Invalidate a consumer/pose without releasing its in-flight GPU reader.
func set_context(owner: int, pose: int) -> StringName:
	if owner<1 or pose<1:return &"invalid_request"
	if owner<owner_token:return &"stale_owner"
	if owner==owner_token and pose<pose_seq:return &"stale_pose"
	if owner>owner_token:request_highwater=0
	owner_token=owner;pose_seq=pose;return &""

func request(value: Dictionary, callback: Callable) -> Dictionary:
	if closing or rd==null:return {"accepted":false,"error":&"closing"}
	if pending:return {"accepted":false,"error":&"probe_busy"}
	var error:=Codec.validate(value,domain,generation)
	if not error.is_empty():return {"accepted":false,"error":error}
	if not callback.is_valid() or serial==L.INT64_MAX:return {"accepted":false,"error":&"invalid_request"}
	error=set_context(value.owner_token,value.pose_seq)
	if not error.is_empty():return {"accepted":false,"error":error}
	if value.request_id<=request_highwater:return {"accepted":false,"error":&"invalid_request"}
	request_highwater=value.request_id
	serial+=1;pending=true;unknown=false;accepted_count+=1
	query={"request":value.duplicate(true),"serial":serial,"callback":callback}
	RenderingServer.call_on_render_thread(_record_render.bind(Codec.encode(value,serial),serial))
	return {"accepted":true,"error":&"","request_id":value.request_id}

func _record_render(bytes: PackedByteArray, id: int) -> void:
	if inject_upload_failure_once:inject_upload_failure_once=false;call_deferred("_upload_failed",id);return
	if rd.buffer_update(input,0,bytes.size(),bytes)!=OK:call_deferred("_upload_failed",id);return
	dispatch("probe",query_set,Vector3i.ONE);_read_render(id)

func _upload_failed(id: int) -> void:
	if pending and query.serial==id:_complete({"error":&"readback_failed","recorded":false})

func _read_render(id: int) -> void:
	var error: Error=ERR_UNAVAILABLE
	if inject_readback_failure_once:inject_readback_failure_once=false
	else:error=rd.buffer_get_data_async(output,_arrived.bind(id),0,Codec.OUTPUT_BYTES)
	if error!=OK:call_deferred("_unknown",id)

func _unknown(id: int) -> void:
	if pending and query.serial==id:unknown=true;unknown_count+=1

func retry_readback() -> void:
	if pending and unknown:unknown=false;RenderingServer.call_on_render_thread(_read_render.bind(query.serial))

func _arrived(bytes: PackedByteArray, id: int) -> void:call_deferred("_received",bytes,id)

func _received(bytes: PackedByteArray, id: int) -> void:
	if not pending or query.serial!=id:return
	if hold_delivery:held={"bytes":bytes.duplicate(),"serial":id};return
	var result:=Codec.decode(bytes,query.request,id)
	if closing:result.error=&"closing"
	elif query.request.owner_token!=owner_token:result.error=&"stale_owner"
	elif query.request.pose_seq!=pose_seq:result.error=&"stale_pose"
	_complete(result)

func deliver_held() -> void:
	var packet:=held;held={};hold_delivery=false
	if not packet.is_empty():_received(packet.bytes,packet.serial)

func _complete(result: Dictionary) -> void:
	for key in ["request_id","owner_token","domain_id","generation","pose_seq"]:result[key]=query.request[key]
	var callback: Callable=query.callback
	pending=false;unknown=false;query={};completed_count+=1
	if callback.is_valid():callback.call(result)

func close() -> void:closing=true
func can_release() -> bool:return not pending
func release_if_idle() -> bool:
	if not can_release():return false
	query_set=RID();input=RID();output=RID();super.release();return true

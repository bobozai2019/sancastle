extends RefCounted

# Low-frequency final-stream lifetime proof. It is independent of a fully
# initialized solver/transport and never supplies authority or receipt data.
var rd: RenderingDevice
var anchor:=RID()
var required:=false
var pending:=false
var confirmed:=false
var unconfirmed_ownership:=false
var inject_unavailable:=false
var sequence:=0
var proofs:=0
var events:=[]

func begin(stage: String) -> void:
	required=true;pending=true;confirmed=false;sequence+=1
	RenderingServer.call_on_render_thread(_request.bind(sequence,stage))

func _request(serial: int, stage: String) -> void:
	if rd==null:rd=RenderingServer.get_rendering_device()
	if rd!=null and not anchor.is_valid():anchor=rd.storage_buffer_create(16)
	if rd==null or not anchor.is_valid() or inject_unavailable or rd.buffer_get_data_async(anchor,_arrived.bind(serial,stage),0,16)!=OK:
		call_deferred("_record",serial,stage,false)

func _arrived(_bytes: PackedByteArray, serial: int, stage: String) -> void:
	call_deferred("_record",serial,stage,true)

func _record(serial: int, stage: String, ok: bool) -> void:
	if serial!=sequence:return
	pending=false;unconfirmed_ownership=not ok
	confirmed=ok and stage=="final"
	if ok:proofs+=1
	events.append({"sequence":serial,"stage":stage,"confirmed":ok,"at_us":Time.get_ticks_usec()})
	if events.size()>128:events.pop_front()

func release_render() -> bool:
	if pending or (required and not confirmed):return false
	if rd!=null and anchor.is_valid():rd.free_rid(anchor)
	anchor=RID();rd=null
	return true

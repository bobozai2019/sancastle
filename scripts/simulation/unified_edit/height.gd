extends "res://scripts/simulation/unified_edit/gpu.gd"

# One versioned complete-height channel for collision/worker consumers. The GPU
# owns dirty flags; borrowed flags are acknowledged only after the last consumer.
const Codec=preload("res://scripts/simulation/unified_edit/height_codec.gd")
const Job=preload("res://scripts/collision/collision_prepare_job.gd")
const SOURCES=["res://scripts/simulation/unified_edit/height.gd","res://scripts/simulation/unified_edit/height.glsl","res://scripts/simulation/unified_edit/height_codec.gd","res://scripts/collision/collision_prepare_job.gd"]
var proxy
var state
var transport
var generation:=0
var dirty:=RID()
var before:=RID()
var gpu_slots: Array[Dictionary]=[]
var slots: Array[Dictionary]=[]
var serial:=0
var hinted:=false
var closing:=false
var applied_state_seq: Dictionary={}
var applied_tick: Dictionary={}
var applied_revision: Dictionary={}
var events: Array[Dictionary]=[]
var invalid_results:=0
var inject_readback_failure_once:=false
var inject_packet_fault_once:=""
var hold_readbacks:=false
var held: Array[Dictionary]=[]
var hold_physics:=false

func _init() -> void:
	for index in L.HEIGHT_SLOTS:slots.append(_free())

func _free() -> Dictionary:return {"identity":{},"phase":&"free","result":{},"job":null,"task":-1}

func initialize(bundle, channel, epoch: int) -> bool:
	if rd!=null:return false
	state=bundle;transport=channel;rd=channel.rd;generation=epoch
	var zero:=PackedByteArray();zero.resize(1040)
	dirty=own(rd.storage_buffer_create(zero.size(),zero))
	before=state._create_texture(RenderingDevice.DATA_FORMAT_R32_SFLOAT,PackedByteArray())
	if not compile("height",SOURCES[1]):return false
	for index in L.HEIGHT_SLOTS:
		var bytes:=PackedByteArray();bytes.resize(Codec.MAX_BYTES)
		var output:=own(rd.storage_buffer_create(bytes.size(),bytes))
		var set:=binding("height",{0:dirty,1:channel.control,5:output},{2:before,3:state.textures.sand[0],4:state.textures.rock})
		gpu_slots.append({"output":output,"set":set,"identity":{},"phase":&""})
		if not output.is_valid() or not set.is_valid():return false
	dispatch("height",gpu_slots[0].set,Vector3i.ONE,_push(0))
	return true

func _push(mode: int, snapshot: int=0) -> PackedByteArray:
	var push:=PackedByteArray();push.resize(32);push.encode_u32(0,mode);push.encode_s64(4,generation);push.encode_s64(12,snapshot);return push

func begin_work() -> void:dispatch("height",gpu_slots[0].set,Vector3i(1024,1,1),_push(1))
func finish_work() -> void:dispatch("height",gpu_slots[0].set,Vector3i(1024,1,1),_push(2))

func notify_complete() -> void:hinted=true

func _event(name: StringName, id: Dictionary, detail: Dictionary={}) -> void:
	var row:={"event":name,"identity":id.duplicate(true),"frame":Engine.get_process_frames(),"detail":detail.duplicate(true)}
	events.append(row)
	if events.size()>128:events.pop_front()

func pump() -> int:
	if closing or rd==null or proxy==null or not hinted:return 0
	var submitted:=0
	for index in slots.size():
		if not slots[index].identity.is_empty():continue
		if serial==L.INT64_MAX:last_error="height_identity_exhausted";return submitted
		serial+=1
		var id:={"generation":generation,"snapshot_seq":serial,"slot_id":index}
		slots[index]={"identity":id,"phase":&"read_pending","result":{},"job":null,"task":-1}
		_event(&"request",id)
		RenderingServer.call_on_render_thread(_capture_render.bind(id.duplicate(true)))
		submitted+=1
	if submitted>0:hinted=false
	return submitted

func _capture_render(id: Dictionary) -> void:
	var slot: Dictionary=gpu_slots[id.slot_id];slot.identity=id.duplicate(true);slot.phase=&"read"
	dispatch("height",slot.set,Vector3i.ONE,_push(3,id.snapshot_seq))
	dispatch("height",slot.set,Vector3i(273,1,1),_push(4,id.snapshot_seq))
	_read_render(id)

func _gpu_matches(id: Dictionary) -> bool:return rd!=null and id.generation==generation and gpu_slots[id.slot_id].identity==id
func _matches(id: Dictionary) -> bool:return id.generation==generation and id.slot_id>=0 and id.slot_id<slots.size() and slots[id.slot_id].identity==id

func _read_render(id: Dictionary) -> void:
	if not _gpu_matches(id):return
	var slot: Dictionary=gpu_slots[id.slot_id]
	var callback: Callable=_read_arrived.bind(id) if slot.phase==&"read" else _ack_arrived.bind(id)
	var error: Error=ERR_UNAVAILABLE
	if inject_readback_failure_once:inject_readback_failure_once=false
	else:error=rd.buffer_get_data_async(slot.output,callback,0,Codec.MAX_BYTES if slot.phase==&"read" else 4)
	if error!=OK:call_deferred("_unknown",id,slot.phase)

func _unknown(id: Dictionary, phase: StringName) -> void:
	if not _matches(id):return
	slots[id.slot_id].phase=StringName(String(phase)+"_unknown");_event(&"readback_unknown",id,{"phase":phase})

func retry_readbacks() -> void:
	for slot in slots:
		if slot.phase in [&"read_unknown",&"ack_unknown"]:
			slot.phase=&"read_pending" if slot.phase==&"read_unknown" else &"ack_pending"
			RenderingServer.call_on_render_thread(_read_render.bind(slot.identity.duplicate(true)))

func _read_arrived(bytes: PackedByteArray, id: Dictionary) -> void:
	if not _gpu_matches(id):return
	call_deferred("_received",bytes,id)

func _received(bytes: PackedByteArray, id: Dictionary) -> void:
	if not _matches(id) or slots[id.slot_id].phase!=&"read_pending":return
	if hold_readbacks:
		held.append({"bytes":bytes.duplicate(),"identity":id.duplicate(true)});return
	if not inject_packet_fault_once.is_empty():
		bytes=bytes.duplicate()
		match inject_packet_fault_once:
			"nan":bytes.encode_float(Codec.PREFIX_BYTES,NAN)
			"identity":bytes.encode_s64(8,generation-1)
			"truncate":bytes=bytes.slice(0,16)
		inject_packet_fault_once=""
	var result:=Codec.decode(bytes,id)
	var slot: Dictionary=slots[id.slot_id]
	if not result.error.is_empty():_invalid(id,result.error);return
	slot.result=result
	_event(&"capture",id,{"state_seq":result.state_seq,"tick":result.sim_tick,"revision":result.revision,"chunks":result.chunks})
	if closing or result.chunks.is_empty():_ack(id,false);return
	hinted=hinted or result.chunks.size()==16
	var request:={"schema_version":1,"request_id":id.snapshot_seq,"generation":generation,"captured_revision":result.state_seq,"grid_size":256,"chunks":result.chunks,"raw_heights":result.raw,"queued_usec":PackedInt64Array(),"requested_usec":0,"readback_done_usec":0,"task_policy":"serial"}
	var error:=Job.validate(request)
	if not error.is_empty():_invalid(id,error);return
	var job:=Job.new(request);slot.job=job;slot.phase=&"worker"
	slot.task=WorkerThreadPool.add_task(job.prepare_serial,false,"unified complete height")

func deliver_held(reverse: bool=false) -> void:
	var packets:=held.duplicate(true);held.clear();hold_readbacks=false
	if reverse:packets.reverse()
	for packet in packets:_received(packet.bytes,packet.identity)

func _invalid(id: Dictionary, error: StringName) -> void:
	invalid_results+=1;last_error=String(error);_event(&"invalid",id,{"error":error});hinted=true;_ack(id,true)

# Called only by the owner's _physics_process, even when collecting workers
# during shutdown. No work-slot retirement waits for collision convergence.
func physics_consume(order: PackedInt32Array=PackedInt32Array([0,1])) -> int:
	if hold_physics:return 0
	var count:=0
	for index in order:
		if index<0 or index>=slots.size():continue
		var slot: Dictionary=slots[index]
		if slot.phase!=&"worker" or not WorkerThreadPool.is_task_completed(slot.task):continue
		WorkerThreadPool.wait_for_task_completion(slot.task)
		var prepared: Dictionary=slot.job.result();var id: Dictionary=slot.identity
		if prepared.status!=&"prepared":_invalid(id,&"height_nonfinite");continue
		if not closing and proxy!=null:
			var accepted:=true
			for chunk in prepared.chunks:
				var version: int=slot.result.state_seq;var chunk_id: int=chunk.chunk_id
				if version<int(applied_state_seq.get(chunk_id,-1)):continue
				if not proxy._replace_chunk_shape(chunk_id,version,chunk.heights,generation):accepted=false;break
				applied_state_seq[chunk_id]=version;applied_tick[chunk_id]=slot.result.sim_tick;applied_revision[chunk_id]=slot.result.revision;count+=1
			if not accepted:_invalid(id,&"height_proxy_rejected");continue
			_event(&"physics",id,{"state_seq":slot.result.state_seq,"chunks":slot.result.chunks})
		_ack(id,false)
	return count

func _ack(id: Dictionary, retry: bool) -> void:
	slots[id.slot_id].phase=&"ack_pending"
	RenderingServer.call_on_render_thread(_ack_render.bind(id.duplicate(true),retry))

func _ack_render(id: Dictionary, retry: bool) -> void:
	if not _gpu_matches(id):return
	var slot: Dictionary=gpu_slots[id.slot_id]
	dispatch("height",slot.set,Vector3i.ONE,_push(6 if retry else 5,id.snapshot_seq));slot.phase=&"ack"
	_read_render(id)

func _ack_arrived(_bytes: PackedByteArray, id: Dictionary) -> void:
	if not _gpu_matches(id):return
	gpu_slots[id.slot_id].identity={};call_deferred("_reclaimed",id)

func _reclaimed(id: Dictionary) -> void:
	if not _matches(id):return
	var result: Dictionary=slots[id.slot_id].result
	hinted=hinted or not result.get("chunks",PackedInt32Array()).is_empty()
	_event(&"last_consumer",id);slots[id.slot_id]=_free()

func active_count() -> int:
	var count:=0
	for slot in slots:
		if not slot.identity.is_empty():count+=1
	return count

func close() -> void:closing=true;hinted=false

func release_if_idle() -> bool:
	if active_count()!=0:return false
	for slot in gpu_slots:
		if not slot.identity.is_empty():return false
	gpu_slots.clear();state=null;transport=null;super.release();return true

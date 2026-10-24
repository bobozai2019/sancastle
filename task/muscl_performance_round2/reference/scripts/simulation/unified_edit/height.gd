extends "res://scripts/simulation/unified_edit/gpu.gd"

# One versioned complete-height channel for collision/worker consumers. The GPU
# owns dirty flags; borrowed flags are acknowledged only after the last consumer.
const Codec=preload("res://scripts/simulation/unified_edit/height_codec.gd")
const Job=preload("res://scripts/collision/collision_prepare_job.gd")
const Diagnostics=preload("res://scripts/simulation/unified_edit/diagnostics.gd")
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
var applied_physics_frame: Dictionary={}
var applied_change_bounds: Dictionary={}
var priority_owner:=0
var priority_mask:=PackedByteArray()
var events: Array[Dictionary]=[]
var invalid_results:=0
var inject_readback_failure_once:=false
var inject_packet_fault_once:=""
var hold_readbacks:=false
var held: Array[Dictionary]=[]
var hold_physics:=false
var diagnostics: Diagnostics
# A budget belongs to one height owner and one rendered frame, including all
# physics catch-up notifications in that frame. One native shape call is atomic.
const APPLY_BUDGET_USEC:=1500
const APPLY_MAX_CHUNKS:=8
var _apply_frame: int=-1
var _apply_usec:=0
var _apply_count:=0
var _next_apply_slot:=0
var _apply_slice:=0

func _init() -> void:
	priority_mask.resize(8)
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

func _push(mode: int, snapshot: int=0, priority: PackedByteArray=PackedByteArray()) -> PackedByteArray:
	var push:=PackedByteArray();push.resize(32);push.encode_u32(0,mode);push.encode_s64(4,generation);push.encode_s64(12,snapshot)
	if priority.size()==8:
		push.encode_u32(20,priority.decode_u32(0));push.encode_u32(24,priority.decode_u32(4))
	return push

func begin_work() -> void:dispatch("height",gpu_slots[0].set,Vector3i(1024,1,1),_push(1))
func finish_work() -> void:dispatch("height",gpu_slots[0].set,Vector3i(64,1,1),_push(2))

func notify_complete() -> void:hinted=true

func _event(name: StringName, id: Dictionary, detail: Dictionary={}) -> void:
	if diagnostics!=null:diagnostics.mark(StringName("height_"+String(name)),id.snapshot_seq,detail.duplicate(true))
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
		RenderingServer.call_on_render_thread(_capture_priority_render.bind(id.duplicate(true),priority_mask.duplicate()))
		submitted+=1
	if submitted>0:hinted=false
	return submitted

func _capture_priority_render(id: Dictionary, priority: PackedByteArray) -> void:
	gpu_slots[id.slot_id].priority=priority
	_capture_render(id)

func _capture_render(id: Dictionary) -> void:
	if diagnostics!=null:diagnostics.mark(&"height_capture_render",id.snapshot_seq)
	var slot: Dictionary=gpu_slots[id.slot_id];slot.identity=id.duplicate(true);slot.phase=&"read"
	dispatch("height",slot.set,Vector3i.ONE,_push(3,id.snapshot_seq,slot.get("priority",PackedByteArray())))
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
	if diagnostics!=null:diagnostics.mark(&"height_readback_callback",id.snapshot_seq)
	if not _gpu_matches(id):return
	call_deferred("_received",bytes,id)

func _received(bytes: PackedByteArray, id: Dictionary) -> void:
	if diagnostics!=null:diagnostics.mark(&"height_receive",id.snapshot_seq)
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
	if diagnostics!=null:diagnostics.mark(&"height_worker_queued",id.snapshot_seq)
	slot.task=WorkerThreadPool.add_task(job.prepare_serial,false,"unified complete height")

func deliver_held(reverse: bool=false) -> void:
	var packets:=held.duplicate(true);held.clear();hold_readbacks=false
	if reverse:packets.reverse()
	for packet in packets:_received(packet.bytes,packet.identity)

func _invalid(id: Dictionary, error: StringName) -> void:
	invalid_results+=1;last_error=String(error);_event(&"invalid",id,{"error":error});hinted=true;_ack(id,true)

# Called only by the owner's _physics_process, even when collecting workers
# during shutdown. No work-slot retirement waits for collision convergence.
func physics_consume(order: PackedInt32Array=PackedInt32Array()) -> int:
	if hold_physics:return 0
	var frame:=Engine.get_process_frames()
	if _apply_frame!=frame:
		_apply_frame=frame;_apply_usec=0;_apply_count=0
	if order.is_empty():order=PackedInt32Array([_next_apply_slot,1-_next_apply_slot])
	var count:=0
	for index in order:
		if index<0 or index>=slots.size():continue
		var slot: Dictionary=slots[index]
		if slot.phase==&"worker":
			if not WorkerThreadPool.is_task_completed(slot.task):continue
			WorkerThreadPool.wait_for_task_completion(slot.task)
			slot.prepared=slot.job.result();slot.job=null;slot.task=-1
			slot.next_chunk=0;slot.phase=&"applying"
			if slot.prepared.status!=&"prepared":_invalid(slot.identity,&"height_nonfinite");continue
		if slot.phase!=&"applying":continue
		var prepared: Dictionary=slot.prepared;var id: Dictionary=slot.identity
		if not closing and proxy!=null:
			if _apply_usec>=APPLY_BUDGET_USEC or _apply_count>=APPLY_MAX_CHUNKS:break
			_apply_slice+=1
			if diagnostics!=null:diagnostics.mark(&"height_apply_begin",id.snapshot_seq,{"slice_id":_apply_slice,"timings":prepared.timings if slot.next_chunk==0 else [],"chunks":prepared.chunks.size()-slot.next_chunk,"state_seq":slot.result.state_seq})
			var accepted:=true
			while slot.next_chunk<prepared.chunks.size():
				if _apply_usec>=APPLY_BUDGET_USEC or _apply_count>=APPLY_MAX_CHUNKS:break
				var chunk: Dictionary=prepared.chunks[slot.next_chunk]
				slot.next_chunk+=1
				var version: int=slot.result.state_seq;var chunk_id: int=chunk.chunk_id
				if version<int(applied_state_seq.get(chunk_id,-1)):continue
				var started:=Time.get_ticks_usec()
				var replaced: bool=proxy._replace_chunk_shape(chunk_id,version,chunk.heights,generation)
				_apply_usec+=Time.get_ticks_usec()-started;_apply_count+=1
				if not replaced:accepted=false;break
				applied_state_seq[chunk_id]=version;applied_tick[chunk_id]=slot.result.sim_tick;applied_revision[chunk_id]=slot.result.revision;applied_physics_frame[chunk_id]=Engine.get_physics_frames();count+=1
				applied_change_bounds[chunk_id]=slot.result.change_bounds[chunk_id]
			if diagnostics!=null:diagnostics.mark(&"height_apply_end",id.snapshot_seq,{"slice_id":_apply_slice,"next_chunk":slot.next_chunk,"frame_apply_usec":_apply_usec,"frame_apply_count":_apply_count})
			_next_apply_slot=1-index
			if not accepted:_invalid(id,&"height_proxy_rejected");continue
			# Keep the real reader lease and borrowed dirty bits until every
			# chunk is consumed. Closing may discard the remaining CPU shapes.
			if slot.next_chunk<prepared.chunks.size():break
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

# Shape assignment and motion queries are synchronous on the physics thread.
# A grant made later in this notification uses that shape in its next world
# quantum (completion callback is numbered frame+1). Native phase probe proves
# both immediate queries and first-quantum contact; no extra idle frame needed.
func footprint_ready(required: Dictionary, epoch: int) -> Dictionary:
	if epoch!=generation:return {"ready":false,"error":&"stale_generation","waiting":[]}
	if required.is_empty() or required.size()>64:return {"ready":false,"error":&"invalid_footprint","waiting":[]}
	var waiting: Array=[];var frame:=Engine.get_physics_frames()
	for chunk in required:
		if typeof(chunk)!=TYPE_INT or chunk<0 or chunk>=64 or typeof(required[chunk])!=TYPE_INT or required[chunk]<0:return {"ready":false,"error":&"invalid_footprint","waiting":[]}
		var applied: int=applied_state_seq.get(chunk,-1);var assigned_frame: int=applied_physics_frame.get(chunk,-1)
		if applied<required[chunk] or assigned_frame<0 or frame<assigned_frame:waiting.append({"chunk":chunk,"required":required[chunk],"applied":applied,"assigned_frame":assigned_frame,"current_frame":frame})
	return {"ready":waiting.is_empty(),"error":&"","waiting":waiting,"physics_frame":frame}

# A force may use an older assigned shape only with an independently bounded
# temporal discrepancy inside the already frozen contact tolerance. Initial
# placement and edit recovery still require strict footprint_ready().
func footprint_compatible(required: Dictionary, bounds: Dictionary, epoch: int, tolerance_m: float) -> Dictionary:
	var strict:=footprint_ready(required,epoch)
	if not strict.error.is_empty() or tolerance_m<0.0 or not is_finite(tolerance_m):return {"ready":false,"error":strict.error}
	var maximum:=0.0;var differences:={}
	for chunk in required:
		var applied: int=applied_state_seq.get(chunk,-1)
		if applied<0 or int(applied_physics_frame.get(chunk,-1))<0:return {"ready":false,"error":&"support_not_ready"}
		if applied>=required[chunk]:continue
		var upper: float=applied_change_bounds.get(chunk,-1.0);var lower:=Codec.lower_change_bound(upper);var newer: float=bounds.get(chunk,-1.0)
		if lower<0.0 or newer<0.0 or newer<lower or newer-lower>tolerance_m:return {"ready":false,"error":&"support_change_bound"}
		maximum=maxf(maximum,newer-lower)
		differences[chunk]=newer-lower
	return {"ready":true,"error":&"","maximum_temporal_difference_m":maximum,"older_shape_differences_m":differences,"strict_versions_ready":strict.ready}

# At most twelve chunks for the three MVP footprints. Captures still contain
# at most sixteen chunks and always reserve four selections for the ordinary
# fair cursor when live footprints are present (up to twelve priority chunks).
# The mask is frozen into each existing reader lease's push constants.
func set_footprint_priority(chunks: Array[int], epoch: int, owner: int) -> StringName:
	if closing:return &"closing"
	if epoch!=generation:return &"stale_generation"
	if owner<1 or owner<priority_owner:return &"stale_owner"
	if chunks.size()>12:return &"invalid_footprint"
	var seen:={};var masks:=[0,0]
	for chunk in chunks:
		if chunk<0 or chunk>=64 or seen.has(chunk):return &"invalid_footprint"
		seen[chunk]=true;masks[chunk/32]=int(masks[chunk/32])|(1<<(chunk%32))
	var bytes:=PackedByteArray();bytes.resize(8);bytes.encode_u32(0,masks[0]);bytes.encode_u32(4,masks[1])
	priority_owner=owner;priority_mask=bytes
	return &""

# Read the existing collision consumer data, never a second CPU terrain state.
# Includes adjacent vertices so the result bounds the triangles in the rect.
func maximum_bed(bounds: Rect2, required: Dictionary, epoch: int) -> Dictionary:
	var ready:=footprint_ready(required,epoch)
	if not ready.ready:return {"error":&"support_not_ready"}
	if proxy==null or not is_instance_valid(proxy) or not bounds.position.is_finite() or not bounds.size.is_finite() or bounds.size.x<=0 or bounds.size.y<=0:return {"error":&"invalid_footprint"}
	var highest:=-INF;var count:=0
	for chunk in required:
		var node: CollisionShape3D=proxy.shapes[chunk];var shape: HeightMapShape3D=node.shape
		if shape==null:return {"error":&"support_not_ready"}
		var transform:=node.global_transform;var inverse:=transform.affine_inverse()
		var low:=Vector2(INF,INF);var high:=Vector2(-INF,-INF)
		for corner in [bounds.position,Vector2(bounds.end.x,bounds.position.y),bounds.end,Vector2(bounds.position.x,bounds.end.y)]:
			var local: Vector3=inverse*Vector3(corner.x,transform.origin.y,corner.y)
			low=low.min(Vector2(local.x,local.z));high=high.max(Vector2(local.x,local.z))
		var half_x:=0.5*float(shape.map_width-1);var half_z:=0.5*float(shape.map_depth-1)
		if high.x< -half_x or low.x>half_x or high.y< -half_z or low.y>half_z:continue
		var x0:=clampi(floori(low.x+half_x),0,shape.map_width-1);var x1:=clampi(ceili(high.x+half_x),0,shape.map_width-1)
		var z0:=clampi(floori(low.y+half_z),0,shape.map_depth-1);var z1:=clampi(ceili(high.y+half_z),0,shape.map_depth-1)
		var data: PackedFloat32Array=shape.map_data
		for z in range(z0,z1+1):
			for x in range(x0,x1+1):
				var world: Vector3=transform*Vector3(float(x)-half_x,data[z*shape.map_width+x],float(z)-half_z)
				if not world.is_finite():return {"error":&"invalid_sample"}
				highest=maxf(highest,world.y);count+=1
	return {"error":&"" if count>0 else &"out_of_domain","maximum_m":highest,"vertices":count,"physics_frame":Engine.get_physics_frames()}

func close() -> void:closing=true;hinted=false

func release_if_idle() -> bool:
	if active_count()!=0:return false
	for slot in gpu_slots:
		if not slot.identity.is_empty():return false
	gpu_slots.clear();state=null;transport=null;super.release();return true

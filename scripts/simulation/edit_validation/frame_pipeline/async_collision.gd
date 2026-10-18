extends RefCounted

const Codec=preload("res://scripts/simulation/edit_validation/frame_pipeline/async_height_codec.gd")
const PrepareJob=preload("res://scripts/collision/collision_prepare_job.gd")
var proxy
var solver
var generation:=0
var serial:=0
var pending:={}
var slots: Array[Dictionary]=[]
var applied_state_seq:={}
var applied_sim_tick:={}
var events: Array[Dictionary]=[]
var invalid_results:=0
var closing:=false
var rd: RenderingDevice
var shader:=RID()
var pipeline:=RID()
var control_set:=RID()
var gpu_slots: Array[Dictionary]=[]
var last_error:=""
var failure_callback: Callable
var inject_readback_failure_once:=false
var blocked_fences:={}
var unconfirmed_ownership:=false
var observe:=false
var selection_cursor:=0

func _init(target=null) -> void:
	proxy=target
	for index in 2:slots.append({"identity":{},"result":{},"job":null,"task":-1})

# Render thread only. All requests use the same ordered device as state writes.
func initialize(owner) -> bool:
	if owner==null or owner.rd==null or not owner.async_active:return false
	solver=owner
	generation=owner.owner_generation
	rd=owner.rd
	var source:=RDShaderSource.new()
	source.source_compute=FileAccess.get_file_as_string("res://scripts/simulation/edit_validation/frame_pipeline/async_height_pack.glsl").trim_prefix("#[compute]")
	var spirv:=rd.shader_compile_spirv_from_source(source)
	last_error=spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
	if not last_error.is_empty():return false
	shader=rd.shader_create_from_spirv(spirv)
	pipeline=rd.compute_pipeline_create(shader)
	control_set=_binding(1,[],[owner.async_transport.control])
	for index in 2:
		var output:=rd.storage_buffer_create(Codec.MAX_BYTES)
		var ids:=rd.storage_buffer_create(16*4)
		var binding:=_binding(0,[owner.textures.rock,owner.textures.sand[0]],[output,ids])
		gpu_slots.append({"output":output,"ids":ids,"binding":binding,"identity":{},"fence_pending":false})
		if not output.is_valid() or not ids.is_valid() or not binding.is_valid():return false
	return pipeline.is_valid() and control_set.is_valid()

func _binding(set_index: int, images: Array, buffers: Array) -> RID:
	var uniforms: Array[RDUniform]=[]
	var binding:=0
	for group in [images,buffers]:
		for rid in group:
			var uniform:=RDUniform.new()
			uniform.binding=binding
			uniform.uniform_type=RenderingDevice.UNIFORM_TYPE_IMAGE if group==images else RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
			uniform.add_id(rid)
			uniforms.append(uniform)
			binding+=1
	return rd.uniform_set_create(uniforms,shader,set_index)

func _event(name: String, id: Dictionary, state_seq: int=-1) -> void:
	if not observe:return
	var row:=id.duplicate(true)
	row.event=name
	row.state_seq=state_seq
	row.frame_id=Engine.get_process_frames()
	events.append(row)
	if events.size()>128:events.pop_front()

# Main-thread dirty ownership: removing one request's prefix never clears a
# later edit of the same chunk. Failed snapshots merge their chunk set back.
func mark_chunks(chunks: PackedInt32Array) -> void:
	if closing:return
	for chunk in chunks:
		if chunk>=0 and chunk<64:pending[chunk]=true

func mark_all() -> void:
	mark_chunks(PackedInt32Array(range(64)))

func mark_command(data: PackedByteArray) -> void:
	if data.size()!=128:return
	var a:=Vector2(data.decode_float(48),data.decode_float(52))
	var b:=a if data.decode_u32(44)==0 else Vector2(data.decode_float(56),data.decode_float(60))
	var radius:=data.decode_float(64)
	if not a.is_finite() or not b.is_finite() or not is_finite(radius):mark_all();return
	var lo:=(a.min(b)-Vector2.ONE*(radius+0.25)+Vector2.ONE*16.0)/0.125
	var hi:=(a.max(b)+Vector2.ONE*(radius+0.25)+Vector2.ONE*16.0)/0.125
	var dirty:=Rect2i(Vector2i(floori(lo.x),floori(lo.y)),Vector2i(ceili(hi.x)-floori(lo.x)+1,ceili(hi.y)-floori(lo.y)+1))
	for chunk in 64:
		if dirty.intersects(Rect2i((chunk%8)*32,(chunk/8)*32,33,33)):pending[chunk]=true

func pump() -> int:
	if closing or rd==null or pending.is_empty():return 0
	var submitted:=0
	for slot_id in slots.size():
		if pending.is_empty():break
		if not slots[slot_id].identity.is_empty():continue
		var chunks:=_take_pending_chunks()
		serial+=1
		var id:={"generation":generation,"snapshot_seq":serial,"slot_id":slot_id,"chunks":chunks}
		slots[slot_id]={"identity":id,"result":{},"job":null,"task":-1}
		_event("snapshot_request",id)
		RenderingServer.call_on_render_thread(_capture_render.bind(id))
		submitted+=1
	return submitted

func _take_pending_chunks() -> PackedInt32Array:
	var keys:=PackedInt32Array(pending.keys())
	keys.sort()
	var split:=keys.bsearch(selection_cursor)
	var chunks:=keys.slice(split,split+16)
	if chunks.size()<16:chunks.append_array(keys.slice(0,mini(split,16-chunks.size())))
	if not chunks.is_empty():selection_cursor=(chunks[chunks.size()-1]+1)%64
	for chunk in chunks:pending.erase(chunk)
	return chunks

func _capture_render(id: Dictionary) -> void:
	var resources: Dictionary=gpu_slots[id.slot_id]
	var chunks: PackedInt32Array=id.chunks
	if rd.buffer_update(resources.ids,0,chunks.size()*4,chunks.to_byte_array())!=OK:
		call_deferred("_receive",PackedByteArray(),id)
		return
	resources.identity=id.duplicate(true)
	resources.fence_pending=false
	var push:=PackedByteArray()
	push.resize(32)
	push.encode_u64(0,id.generation)
	push.encode_u64(8,id.snapshot_seq)
	push.encode_u32(16,chunks.size())
	push.encode_u32(20,256)
	push.encode_float(24,0.125)
	if solver.profile_passes:rd.capture_timestamp("sandcastle_collision_start")
	var list:=rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list,pipeline)
	rd.compute_list_bind_uniform_set(list,resources.binding,0)
	rd.compute_list_bind_uniform_set(list,control_set,1)
	rd.compute_list_set_push_constant(list,push,32)
	rd.compute_list_dispatch(list,ceili(float(chunks.size()*1089)/64.0),1,1)
	rd.compute_list_end()
	if solver.profile_passes:rd.capture_timestamp("sandcastle_collision_end")
	var size:=Codec.PREFIX_BYTES+chunks.size()*Codec.SAMPLES*4
	var error: Error=ERR_UNAVAILABLE
	if inject_readback_failure_once:inject_readback_failure_once=false
	else:error=rd.buffer_get_data_async(resources.output,_arrived.bind(id),0,size)
	if error!=OK:_request_failed_terminal(id)

func _gpu_matches(id: Dictionary) -> bool:
	return rd!=null and id.get("slot_id",-1)>=0 and id.slot_id<gpu_slots.size() and gpu_slots[id.slot_id].identity.get("snapshot_seq",-1)==id.get("snapshot_seq",-2) and gpu_slots[id.slot_id].identity.get("generation",-1)==id.get("generation",-2)

func _request_failed_terminal(id: Dictionary) -> void:
	if not _gpu_matches(id) or gpu_slots[id.slot_id].fence_pending:return
	gpu_slots[id.slot_id].fence_pending=true
	if solver.async_transport.request_fence(_failed_terminal_done.bind(id))!=OK:
		gpu_slots[id.slot_id].fence_pending=false
		call_deferred("_terminal_unavailable",id)

func _failed_terminal_done(_bytes: PackedByteArray, id: Dictionary) -> void:
	if not _gpu_matches(id):return
	gpu_slots[id.slot_id].identity={};gpu_slots[id.slot_id].fence_pending=false
	call_deferred("_failed_readback_drained",id)

func _terminal_unavailable(id: Dictionary) -> void:
	if not _matches(id):return
	blocked_fences[id.snapshot_seq]=id.duplicate(true)
	unconfirmed_ownership=true;last_error="height_terminal_unavailable"
	_event("ownership_unconfirmed",id)
	if failure_callback.is_valid():failure_callback.call(last_error)

func _failed_readback_drained(id: Dictionary) -> void:
	if not _matches(id):return
	blocked_fences.erase(id.snapshot_seq);unconfirmed_ownership=not blocked_fences.is_empty()
	_event("terminal_proof",id)
	_receive(PackedByteArray(),id)

func retry_failed_fences() -> void:
	for id in blocked_fences.values():RenderingServer.call_on_render_thread(_request_failed_terminal.bind(id))

func _arrived(bytes: PackedByteArray, id: Dictionary) -> void:
	if not _gpu_matches(id):return
	gpu_slots[id.slot_id].identity={};gpu_slots[id.slot_id].fence_pending=false
	call_deferred("_receive",bytes,id)

func _matches(id: Dictionary) -> bool:
	if id.get("generation",-1)!=generation or id.get("slot_id",-1)<0 or id.slot_id>=slots.size():return false
	return slots[id.slot_id].identity.get("snapshot_seq",-1)==id.get("snapshot_seq",-2)

func _receive(bytes: PackedByteArray, id: Dictionary) -> void:
	if not _matches(id):return
	blocked_fences.erase(id.snapshot_seq);unconfirmed_ownership=not blocked_fences.is_empty()
	var slot: Dictionary=slots[id.slot_id]
	if slot.task>=0 or not slot.result.is_empty():return
	var result:=Codec.decode(bytes,id)
	if not result.error.is_empty():
		invalid_results+=1
		if not closing:mark_chunks(id.chunks)
		_event("snapshot_invalid",id)
		slots[id.slot_id]={"identity":{},"result":{},"job":null,"task":-1}
		return
	slot.result=result
	_event("snapshot_capture",id,result.state_seq)
	var request:={"schema_version":1,"request_id":id.snapshot_seq,"generation":generation,"captured_revision":result.state_seq,"grid_size":256,"chunks":result.chunks,"raw_heights":result.raw,"queued_usec":PackedInt64Array(),"requested_usec":0,"readback_done_usec":0,"task_policy":"serial"}
	var error:=PrepareJob.validate(request)
	if not error.is_empty():
		last_error=String(error);invalid_results+=1
		if not closing:mark_chunks(id.chunks)
		slots[id.slot_id]={"identity":{},"result":{},"job":null,"task":-1}
		return
	var job:=PrepareJob.new(request)
	slot.job=job
	slot.task=WorkerThreadPool.add_task(job.prepare_serial,false,"pipeline height decode")

# Invoke only from the owning node's _physics_process on the main thread.
func physics_consume(slot_order: PackedInt32Array=PackedInt32Array([0,1])) -> int:
	var applied:=0
	for slot_id in slot_order:
		if slot_id<0 or slot_id>=slots.size():continue
		var slot: Dictionary=slots[slot_id]
		if slot.task<0 or not WorkerThreadPool.is_task_completed(slot.task):continue
		WorkerThreadPool.wait_for_task_completion(slot.task)
		var prepared: Dictionary=slot.job.result()
		var id: Dictionary=slot.identity
		if not closing and prepared.status==&"prepared" and id.generation==generation:
			for chunk in prepared.chunks:
				var chunk_id: int=chunk.chunk_id
				var version: int=slot.result.state_seq
				if version<int(applied_state_seq.get(chunk_id,-1)):continue
				proxy._replace_chunk_shape(chunk_id,version,chunk.heights)
				applied_state_seq[chunk_id]=version
				applied_sim_tick[chunk_id]=slot.result.sim_tick
				applied+=1
			_event("collision_apply",id,slot.result.state_seq)
		elif not closing:
			invalid_results+=1
			mark_chunks(id.chunks)
		slots[slot_id]={"identity":{},"result":{},"job":null,"task":-1}
	return applied

func active_count() -> int:
	var count:=0
	for slot in slots:
		if not slot.identity.is_empty():count+=1
	return count

func release_render() -> bool:
	if active_count()!=0:return false
	if rd==null:return true
	for resource in gpu_slots:
		if not resource.identity.is_empty():return false
	for resources in gpu_slots:
		for key in ["binding","ids","output"]:
			if resources[key].is_valid():rd.free_rid(resources[key])
	gpu_slots.clear()
	for rid in [control_set,pipeline,shader]:
		if rid.is_valid():rd.free_rid(rid)
	rd=null
	solver=null
	return true

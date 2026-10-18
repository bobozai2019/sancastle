extends RefCounted

# Main-thread work-slot ownership. GPU callbacks are marshalled to this owner.
# CPU consumption and render-owner retirement are separate acknowledgements.
const L=preload("res://scripts/simulation/unified_edit/layout.gd")
const Wire=preload("res://scripts/simulation/unified_edit/protocol.gd")
const Intent=preload("res://scripts/simulation/unified_edit/intent.gd")
enum State { FREE, CPU_FILLING, GPU_QUEUED, GPU_COMPLETE, CPU_RECLAIM, UNKNOWN, FATAL }
var _generation:=0
var _domain_hash:=""
var _batch_seq:=0
var _lease_seq:=0
var _slots: Array[Dictionary]=[]
var _accepting:=false
var _initialized:=false
var _fault: StringName=&""
var _events: Array[Dictionary]=[]

func initialize(domain: Variant, generation: Variant, batch_seq: Variant=0, lease_seq: Variant=0) -> StringName:
	if _initialized:return &"slots_already_initialized"
	if typeof(domain) not in [TYPE_STRING,TYPE_STRING_NAME] or String(domain).is_empty() or String(domain).length()>128 or not Intent.counter(generation,1) or not Intent.counter(batch_seq) or not Intent.counter(lease_seq):return &"invalid_slot_identity"
	_generation=generation;_domain_hash=String(domain).sha256_text();_batch_seq=batch_seq;_lease_seq=lease_seq
	for index in L.WORK_SLOTS:_slots.append(_free())
	_initialized=true;_accepting=true
	return &""

func _free() -> Dictionary:
	return {"state":State.FREE,"identity":{},"completion":{},"commands":[],"work_kind":L.WorkKind.EDIT,"last_consumer":false,"reason":&""}

func _event(name: StringName, id: Dictionary) -> void:
	_events.append({"event":name,"identity":id.duplicate(true),"frame_id":Engine.get_process_frames()})
	if _events.size()>128:_events.pop_front()

func _matches(id: Dictionary) -> bool:
	return _initialized and Wire.identity_valid(id) and id.generation==_generation and id.domain_hash==_domain_hash and _slots[id.slot_id].identity==id

func acquire() -> Dictionary:
	if not _initialized:return {"error":&"slots_not_initialized"}
	if not _fault.is_empty():return {"error":&"backend_failed"}
	if not _accepting:return {"error":&"closing"}
	if _batch_seq==L.INT64_MAX or _lease_seq==L.INT64_MAX:
		fail(&"identity_exhausted");return {"error":&"identity_exhausted"}
	for index in _slots.size():
		if _slots[index].state!=State.FREE:continue
		_batch_seq+=1;_lease_seq+=1
		var id:={"generation":_generation,"batch_seq":_batch_seq,"slot_id":index,"lease_id":_lease_seq,"domain_hash":_domain_hash}
		_slots[index]=_free();_slots[index].state=State.CPU_FILLING;_slots[index].identity=id.duplicate(true)
		_event(&"acquire",id)
		return {"error":&"","identity":id}
	return {"error":&"no_slot"}

func queued(id: Dictionary, commands: Array, work_kind: int=L.WorkKind.EDIT) -> StringName:
	if not _matches(id) or _slots[id.slot_id].state!=State.CPU_FILLING:return &"slot_not_filling"
	if (work_kind not in L.WorkKind.values() and work_kind!=Wire.Display.WORK_KIND) or (work_kind==Wire.Display.WORK_KIND and commands.size()!=1) or (work_kind==L.WorkKind.EDIT and (commands.is_empty() or commands.size()>L.MAX_COMMANDS)) or (work_kind==L.WorkKind.WATER_TICK and not commands.is_empty()):return &"invalid_work_kind_or_count"
	var previous:=0
	for command in commands:
		if not command is Dictionary or not Intent.counter(command.get("command_id"),1) or command.command_id<=previous or command.get("generation")!=_generation or command.get("domain_hash")!=_domain_hash:return &"invalid_work_commands"
		previous=command.command_id
	var slot: Dictionary=_slots[id.slot_id]
	slot.commands=commands.duplicate(true);slot.work_kind=work_kind;slot.state=State.GPU_QUEUED
	_event(&"queued",id)
	return &""

func cancel_unsubmitted(id: Dictionary) -> bool:
	if not _matches(id) or _slots[id.slot_id].state!=State.CPU_FILLING:return false
	_event(&"cancel_unsubmitted",id);_slots[id.slot_id]=_free()
	return true

# Only the trusted render owner can report this before recording any work.
# An upload failure after recording starts must use unknown(), never this path.
func abandon_unrecorded(id: Dictionary) -> bool:
	if not _matches(id) or _slots[id.slot_id].state!=State.GPU_QUEUED:return false
	_event(&"abandon_unrecorded",id);_slots[id.slot_id]=_free()
	return true

func completed(bytes: PackedByteArray, expected: Dictionary) -> StringName:
	if not _matches(expected):return &"stale_lease"
	var slot: Dictionary=_slots[expected.slot_id]
	if slot.state!=State.GPU_QUEUED:return &"duplicate_or_wrong_state"
	var decoded:=Wire.decode_completion(bytes,expected,slot.commands,slot.work_kind)
	# A successful ordered callback proves the last buffer consumer completed,
	# even when its payload is invalid. It does not authorize state publication.
	slot.last_consumer=true
	if not decoded.error.is_empty():
		slot.state=State.UNKNOWN;slot.reason=decoded.error;fail(decoded.error)
		_event(&"invalid_completion",expected);return decoded.error
	slot.completion=decoded.duplicate(true)
	if decoded.fatal:
		slot.state=State.FATAL;slot.reason=&"gpu_fatal";fail(&"gpu_fatal")
		_event(&"fatal_completion",expected);return &"gpu_fatal"
	slot.state=State.GPU_COMPLETE;_event(&"gpu_complete",expected)
	return &""

func consume(id: Dictionary) -> Dictionary:
	if not _matches(id) or _slots[id.slot_id].state!=State.GPU_COMPLETE:return {"error":&"not_complete"}
	var slot: Dictionary=_slots[id.slot_id]
	var result: Dictionary=slot.completion.duplicate(true)
	slot.state=State.CPU_RECLAIM
	_event(&"cpu_consume",id)
	return result

# This acknowledgement follows transport.retire(same_lease) on the render
# thread. Merely scheduling that retirement does not permit slot reuse.
func retired(id: Dictionary) -> bool:
	if not _matches(id):return false
	var slot: Dictionary=_slots[id.slot_id]
	if slot.state!=State.CPU_RECLAIM or not slot.last_consumer:return false
	_event(&"render_retired",id);_slots[id.slot_id]=_free()
	return true

func unknown(id: Dictionary, reason: StringName) -> bool:
	if not _matches(id) or _slots[id.slot_id].state!=State.GPU_QUEUED or reason.is_empty():return false
	_slots[id.slot_id].state=State.UNKNOWN;_slots[id.slot_id].reason=reason
	fail(reason);_event(&"unknown",id)
	return true

# Used only after a trusted terminal fence and render-owner retirement. The
# fence is a lifetime proof, never a replacement receipt or replay permission.
func abort_after_retired(id: Dictionary, last_consumer_confirmed: bool) -> bool:
	if not _matches(id) or not last_consumer_confirmed:return false
	if _slots[id.slot_id].state not in [State.GPU_QUEUED,State.GPU_COMPLETE,State.UNKNOWN,State.FATAL]:return false
	_event(&"abort_after_retired",id);_slots[id.slot_id]=_free()
	return true

func fail(reason: StringName) -> void:
	if _fault.is_empty():_fault=reason
	_accepting=false

func stop_admission() -> void:
	_accepting=false

func active_count() -> int:
	var count:=0
	for slot in _slots:
		if slot.state!=State.FREE:count+=1
	return count

func can_release() -> bool:
	return _initialized and not _accepting and active_count()==0

func slot_snapshot(index: int) -> Dictionary:
	return _slots[index].duplicate(true) if index>=0 and index<_slots.size() else {}

func events() -> Array[Dictionary]:
	return _events.duplicate(true)

func fault_reason() -> StringName:
	return _fault

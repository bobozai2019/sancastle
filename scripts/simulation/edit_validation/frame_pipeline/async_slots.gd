extends RefCounted

const Wire = preload("res://scripts/simulation/edit_validation/frame_pipeline/async_protocol.gd")
enum State { FREE, CPU_FILLING, GPU_QUEUED, GPU_COMPLETE, CPU_RECLAIM }
var generation: int
var batch_seq := 0
var lease_seq := 0
var slots: Array[Dictionary] = []
var accepting := true
var events: Array[Dictionary] = []

func _init(epoch: int) -> void:
	generation = epoch
	for index in Wire.BATCH_SLOTS: slots.append({"state":State.FREE,"identity":{},"completion":{}})

func _event(name: String, id: Dictionary) -> void:
	var item := id.duplicate()
	item.event = name
	item.frame_id = Engine.get_process_frames()
	events.append(item)
	if events.size() > 128: events.pop_front()

func acquire() -> Dictionary:
	if not accepting: return {"error":"closing"}
	if batch_seq==9223372036854775807 or lease_seq==9223372036854775807:return {"error":"identity_exhausted"}
	for index in slots.size():
		if slots[index].state != State.FREE: continue
		batch_seq += 1
		lease_seq += 1
		var id := {"generation":generation,"batch_seq":batch_seq,"slot_id":index,"lease_id":lease_seq}
		slots[index] = {"state":State.CPU_FILLING,"identity":id.duplicate(),"completion":{}}
		_event("acquire", id)
		return {"error":"","identity":id}
	return {"error":"no_slot"}

func _matches(id: Dictionary) -> bool:
	return Wire.identity_valid(id) and id.generation == generation and Wire.same_lease(slots[id.slot_id].identity, id)

func submitted(id: Dictionary) -> bool:
	if not _matches(id) or slots[id.slot_id].state != State.CPU_FILLING: return false
	slots[id.slot_id].state = State.GPU_QUEUED
	_event("submit", id)
	return true

func cancel_unsubmitted(id: Dictionary) -> bool:
	if not _matches(id) or slots[id.slot_id].state != State.CPU_FILLING: return false
	_event("cancel", id)
	slots[id.slot_id] = {"state":State.FREE,"identity":{},"completion":{}}
	return true

# Only for a render submission that is known to have failed before recording
# any work. Unknown outcomes keep their lease and are never retried.
func abandon_unrecorded(id: Dictionary) -> bool:
	if not _matches(id) or slots[id.slot_id].state!=State.GPU_QUEUED:return false
	_event("submit_error",id)
	slots[id.slot_id]={"state":State.FREE,"identity":{},"completion":{}}
	return true

func completed(bytes: PackedByteArray, expected: Dictionary) -> String:
	# A corrupt payload must never release a slot. The out-of-band expected
	# identity belongs to the callback closure, not to untrusted GPU bytes.
	if not _matches(expected): return "stale_lease"
	if slots[expected.slot_id].state != State.GPU_QUEUED: return "duplicate_or_wrong_state"
	var result := Wire.decode_completion(bytes)
	if not result.error.is_empty(): return result.error
	if not Wire.same_lease(result, expected): return "completion_identity"
	slots[expected.slot_id].state = State.GPU_COMPLETE
	slots[expected.slot_id].completion = result
	_event("gpu_complete", expected)
	return ""

func consume(id: Dictionary) -> Dictionary:
	if not _matches(id) or slots[id.slot_id].state != State.GPU_COMPLETE: return {"error":"not_complete"}
	var result: Dictionary = slots[id.slot_id].completion.duplicate()
	slots[id.slot_id].state = State.CPU_RECLAIM
	_event("cpu_consume", id)
	# Resources are persistent. Only their lease is retired here; the GPU
	# completion readback is the final consumer of this batch's buffers.
	slots[id.slot_id] = {"state":State.FREE,"identity":{},"completion":{}}
	_event("release", id)
	return result

# Called only after the render owner has acknowledged retirement following a
# trusted final-consumer callback. No GPU payload is accepted as a normal result.
func abort_after_last_consumer(id: Dictionary) -> bool:
	if not _matches(id) or slots[id.slot_id].state not in [State.GPU_QUEUED,State.GPU_COMPLETE]:return false
	_event("error_abort",id)
	slots[id.slot_id]={"state":State.FREE,"identity":{},"completion":{}}
	return true

func active_count() -> int:
	var count := 0
	for slot in slots:
		if slot.state != State.FREE: count += 1
	return count

func stop_admission() -> void:
	accepting = false

func can_release() -> bool:
	return not accepting and active_count() == 0

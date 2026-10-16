extends RefCounted

# Immutable batch input; each fixed Slot has exactly one writer while preparing.
# No Node, Shape, solver, RenderingDevice, or scene ownership enters this object.
const SAMPLES := 33 * 33
const CHUNK_BYTES := SAMPLES * 4
const MAX_CHUNKS := 16

class Slot extends RefCounted:
	var status: StringName = &"pending"
	var heights := PackedFloat32Array()
	var start_usec := 0
	var end_usec := 0
	var thread_id := 0

var request: Dictionary
var slots: Array[Slot] = []
var scheduled_usec := 0
var collected_usec := 0
var worker_count := 0

static func decode_heights(bytes: PackedByteArray, detailed: bool = false) -> Dictionary:
	var start := Time.get_ticks_usec() if detailed else 0
	var heights := bytes.to_float32_array()
	var decoded := Time.get_ticks_usec() if detailed else 0
	for height in heights:
		if not is_finite(height):
			return {"status":&"non_finite", "heights":PackedFloat32Array()}
	return {"status":&"prepared", "heights":heights,
		"decode_us":decoded-start,
		"finite_us":Time.get_ticks_usec()-decoded if detailed else 0}

static func validate(value: Dictionary) -> StringName:
	for key in ["schema_version", "request_id", "generation", "captured_revision", "grid_size"]:
		if typeof(value.get(key)) != TYPE_INT:
			return &"invalid_request"
	if value.schema_version != 1 or value.request_id < 1 or value.generation < 1 or \
			value.captured_revision < 0 or value.grid_size < 32 or value.grid_size % 32 != 0:
		return &"invalid_request"
	if not value.get("chunks") is PackedInt32Array or not value.get("raw_heights") is PackedByteArray:
		return &"invalid_request"
	if value.chunks.is_empty() or value.chunks.size() > MAX_CHUNKS:
		return &"invalid_chunk"
	if value.raw_heights.size() != value.chunks.size() * CHUNK_BYTES:
		return &"invalid_length"
	var per_row: int = value.grid_size / 32
	# Avoid integer overflow in an untrusted domain descriptor.
	if per_row > 3037000499:
		return &"invalid_request"
	var seen := {}
	for chunk in value.chunks:
		if chunk < 0 or chunk >= per_row * per_row or seen.has(chunk):
			return &"invalid_chunk"
		seen[chunk] = true
	if value.get("task_policy") not in ["serial", "worker1", "worker2", "worker4"]:
		return &"invalid_request"
	if not value.get("queued_usec") is PackedInt64Array or \
			(value.queued_usec.size() != 0 and value.queued_usec.size() != value.chunks.size()):
		return &"invalid_request"
	for key in ["requested_usec", "readback_done_usec"]:
		if typeof(value.get(key)) != TYPE_INT:
			return &"invalid_request"
	return &""

func _init(value: Dictionary) -> void:
	request = value.duplicate(true)
	# Explicit packed copies isolate callers mutating their buffers after admission.
	request.chunks = value.chunks.duplicate()
	request.raw_heights = value.raw_heights.duplicate()
	request.queued_usec = value.queued_usec.duplicate()
	slots.resize(request.chunks.size())
	for index in slots.size():
		slots[index] = Slot.new()

func prepare_slot(index: int) -> void:
	var slot := slots[index]
	slot.start_usec = Time.get_ticks_usec()
	slot.thread_id = OS.get_thread_caller_id()
	var offset := index * CHUNK_BYTES
	var decoded := decode_heights(request.raw_heights.slice(offset, offset + CHUNK_BYTES))
	slot.status = decoded.status
	slot.heights = decoded.heights
	slot.end_usec = Time.get_ticks_usec()

func prepare_serial() -> void:
	for index in slots.size():
		prepare_slot(index)

func result() -> Dictionary:
	var status: StringName = &"prepared"
	var prepared := []
	var timings := []
	for index in slots.size():
		var slot := slots[index]
		if slot.status == &"non_finite":
			status = &"non_finite"
		elif slot.status != &"prepared" and status != &"non_finite":
			status = &"worker_failed"
		prepared.append({"chunk_id":request.chunks[index], "heights":slot.heights})
		timings.append({"start_usec":slot.start_usec, "end_usec":slot.end_usec,
			"thread_id":slot.thread_id})
	return {"request_id":request.request_id, "generation":request.generation,
		"captured_revision":request.captured_revision, "status":status,
		"chunks":prepared if status == &"prepared" else [], "timings":timings,
		"scheduled_usec":scheduled_usec, "collected_usec":collected_usec,
		"worker_count":worker_count, "bytes_copied":request.raw_heights.size() * 2,
		"queued_usec":request.queued_usec, "requested_usec":request.requested_usec,
		"readback_done_usec":request.readback_done_usec}

extends RefCounted

# pipeline_v1. Little endian; uint64 = low uint32 followed by high uint32.
# No shaderInt64 or identity encoded in floats. Integers use Godot's positive
# signed 64-bit range, including values above the float32/uint32 boundaries.
const VERSION := 1
const COMMAND_BYTES := 128
const HEADER_BYTES := 64
const COMPLETION_BYTES := 80
const CONTROL_BYTES := 128
const SNAPSHOT_HEADER_BYTES := 64
const MAX_COMMANDS := 64
const QUEUE_CAPACITY := 64
const BATCH_SLOTS := 3
const SNAPSHOT_SLOTS := 2
const INPUT_BYTES := HEADER_BYTES + MAX_COMMANDS * COMMAND_BYTES

static func identity_valid(id: Dictionary) -> bool:
	for key in ["generation", "batch_seq", "slot_id", "lease_id"]:
		if typeof(id.get(key)) != TYPE_INT or id[key] < 0: return false
	return id.generation > 0 and id.batch_seq > 0 and id.lease_id > 0 and id.slot_id < BATCH_SLOTS

static func pack_header(id: Dictionary, count: int) -> PackedByteArray:
	if not identity_valid(id) or count < 1 or count > MAX_COMMANDS: return PackedByteArray()
	var bytes := PackedByteArray()
	bytes.resize(HEADER_BYTES)
	bytes.encode_u32(0, VERSION)
	bytes.encode_u32(4, count)
	bytes.encode_u64(8, id.generation)
	bytes.encode_u64(16, id.batch_seq)
	bytes.encode_u32(24, id.slot_id)
	bytes.encode_u64(32, id.lease_id)
	return bytes

static func decode_completion(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() != COMPLETION_BYTES: return {"error":"completion_size"}
	if bytes.decode_u32(0) != VERSION: return {"error":"completion_protocol"}
	var result := {"error":"", "protocol_version":bytes.decode_u32(0), "error_flags":bytes.decode_u32(4),
		"generation":bytes.decode_u64(8), "batch_seq":bytes.decode_u64(16),
		"slot_id":bytes.decode_u32(24), "lease_id":bytes.decode_u64(32),
		"state_seq":bytes.decode_u64(40), "sim_tick":bytes.decode_u64(48),
		"advanced_time_s":bytes.decode_float(56), "actual_dt":bytes.decode_float(60),
		"revision":bytes.decode_u64(64),"accepted_commands":bytes.decode_u32(72),"rejected_commands":bytes.decode_u32(76)}
	if not identity_valid(result): return {"error":"completion_identity"}
	for key in ["state_seq","sim_tick","revision"]:
		if result[key] < 0: return {"error":"completion_counter_range"}
	if not is_finite(result.advanced_time_s) or result.advanced_time_s < 0.0 or not is_finite(result.actual_dt) or result.actual_dt < 0.0:
		return {"error":"completion_time"}
	return result

static func same_lease(a: Dictionary, b: Dictionary) -> bool:
	for key in ["generation", "batch_seq", "slot_id", "lease_id"]:
		if a.get(key, -1) != b.get(key, -2): return false
	return true

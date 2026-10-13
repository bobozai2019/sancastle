extends RefCounted

const GRID_CELLS := 256 * 256
const FIELD_BYTES := {
	"water": GRID_CELLS * 4,
	"momentum_x": GRID_CELLS * 4,
	"momentum_z": GRID_CELLS * 4,
	"foam_history": GRID_CELLS * 8,
	"local_front_history": GRID_CELLS * 8,
}


static func compare(received: Dictionary, expected: Dictionary,
		target_tick: int) -> Dictionary:
	var equal_fields := {}
	for side in ["original", "restored"]:
		if not expected.has(side) or not expected[side] is Dictionary:
			return {"ok": false, "error": "missing expected stamp " + side}
		var stamp: Dictionary = expected[side]
		if stamp.get("tick", -1) != target_tick or \
				typeof(stamp.get("revision")) != TYPE_INT or stamp.revision < 0 or \
				typeof(stamp.get("generation")) != TYPE_INT or stamp.generation < 0:
			return {"ok": false, "error": "invalid expected stamp " + side}
		var key: String = side + "_stamp"
		if not received.has(key) or not received[key] is Dictionary or \
				received[key] != stamp:
			return {"ok": false, "error": "missing/stale readback stamp " + side}
		for field in FIELD_BYTES:
			key = side + "_" + field
			if not received.has(key) or not received[key] is PackedByteArray or \
				received[key].size() != FIELD_BYTES[field]:
				return {"ok": false, "error": "missing/wrong-size GPU field " + key}
	for field in FIELD_BYTES:
		var first: PackedByteArray = received["original_" + field]
		var second: PackedByteArray = received["restored_" + field]
		if first != second:
			return {"ok": false, "error": "GPU field mismatch " + field}
		equal_fields[field] = true
	return {"ok": true, "equal_gpu_fields": equal_fields}

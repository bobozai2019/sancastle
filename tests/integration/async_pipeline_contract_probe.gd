extends SceneTree

const Wire = preload("res://scripts/simulation/edit_validation/frame_pipeline/async_protocol.gd")
const Slots = preload("res://scripts/simulation/edit_validation/frame_pipeline/async_slots.gd")
var checks := []
var failed := false
var output := ""

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	call_deferred("_run")

func check(label: String, value: bool) -> void:
	checks.append({"name":label,"pass":value})
	failed = failed or not value
	print("ASYNC_CONTRACT ", label, " ", value)

func completion(id: Dictionary) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(Wire.COMPLETION_BYTES)
	bytes.encode_u32(0, Wire.VERSION)
	bytes.encode_u64(8, id.generation)
	bytes.encode_u64(16, id.batch_seq)
	bytes.encode_u32(24, id.slot_id)
	bytes.encode_u64(32, id.lease_id)
	bytes.encode_u64(40, 0x100000002)
	bytes.encode_u64(48, 0x200000003)
	bytes.encode_float(56, 4.5)
	bytes.encode_float(60, 0.01)
	bytes.encode_u64(64, 0x300000004)
	return bytes

func _run() -> void:
	var epoch := 0x10000000d
	var pool := Slots.new(epoch)
	pool.batch_seq = 0x200000000
	pool.lease_seq = 0x300000000
	var ids := []
	for index in Wire.BATCH_SLOTS:
		var acquired := pool.acquire()
		check("acquire_%d" % index, acquired.error.is_empty())
		var id: Dictionary = acquired.identity
		ids.append(id)
		var bytes := Wire.pack_header(id, 64)
		check("header_offsets_%d" % index, bytes.size() == 64 and bytes.decode_u32(0) == 1 and bytes.decode_u32(4) == 64 and bytes.decode_u64(8) == epoch and bytes.decode_u64(16) == id.batch_seq and bytes.decode_u32(24) == index and bytes.decode_u64(32) == id.lease_id)
		check("header_low_high_%d" % index, bytes.decode_u32(8) == 13 and bytes.decode_u32(12) == 1)
		check("cannot_consume_before_gpu_%d" % index, pool.consume(id).error == "not_complete")
		check("submitted_%d" % index, pool.submitted(id) and not pool.submitted(id))
	check("bounded_no_slot", pool.acquire().error == "no_slot" and pool.active_count() == 3)
	check("cannot_release_queued", not pool.can_release())
	var raw := completion(ids[0])
	var decoded := Wire.decode_completion(raw)
	check("completion_high_words", decoded.error.is_empty() and decoded.state_seq == 0x100000002 and decoded.sim_tick == 0x200000003 and decoded.revision == 0x300000004)
	check("invalid_count", Wire.pack_header(ids[0], 0).is_empty() and Wire.pack_header(ids[0], 65).is_empty())
	check("truncated_keeps_lease", pool.completed(raw.slice(0,79), ids[0]) == "completion_size" and pool.active_count() == 3)
	var corrupt := raw.duplicate()
	corrupt.encode_float(56, NAN)
	check("nan_keeps_lease", pool.completed(corrupt, ids[0]) == "completion_time")
	corrupt = raw.duplicate()
	corrupt.encode_u64(32, ids[0].lease_id + 1)
	check("mismatched_payload_keeps_lease", pool.completed(corrupt, ids[0]) == "completion_identity")
	corrupt = raw.duplicate()
	corrupt.encode_u32(0, 2)
	check("wrong_protocol_keeps_lease", pool.completed(corrupt, ids[0]) == "completion_protocol")
	corrupt = raw.duplicate()
	corrupt.encode_s64(40, -1)
	check("counter_range_keeps_lease", pool.completed(corrupt, ids[0]) == "completion_counter_range")
	check("completion_accepted", pool.completed(raw, ids[0]).is_empty())
	check("complete_still_owns_slot", pool.acquire().error == "no_slot")
	check("duplicate_before_consume", pool.completed(raw, ids[0]) == "duplicate_or_wrong_state")
	check("consume_once", pool.consume(ids[0]).error.is_empty() and pool.consume(ids[0]).error == "not_complete")
	var replacement: Dictionary = pool.acquire().identity
	check("reuse_new_lease", replacement.slot_id == ids[0].slot_id and replacement.lease_id > ids[0].lease_id)
	check("late_notification_cannot_free_replacement", pool.completed(raw, ids[0]) == "stale_lease" and pool.active_count() == 3)
	check("cancel_only_unsubmitted", pool.cancel_unsubmitted(replacement) and not pool.cancel_unsubmitted(ids[1]))
	var old: Dictionary = ids[1].duplicate()
	old.generation += 1
	check("old_generation", pool.completed(completion(old), old) == "stale_lease")
	pool.stop_admission()
	check("closing_keeps_queued", pool.acquire().error == "closing" and not pool.can_release())
	for index in [2,1]:
		check("out_of_order_%d" % index, pool.completed(completion(ids[index]), ids[index]).is_empty() and pool.consume(ids[index]).error.is_empty())
	check("drained_release", pool.can_release() and pool.active_count() == 0)
	if not output.is_empty():
		var file := FileAccess.open(output,FileAccess.WRITE)
		if file != null: file.store_string(JSON.stringify({"pass":not failed,"checks":checks,"events":pool.events},"\t"))
	quit(1 if failed else 0)

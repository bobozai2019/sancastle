extends SceneTree

## T08 G01: consistent-tick snapshot and the save-format version gate.
##
## The store writes MAGIC + u32 format_version + u32 payload_size + sha256 +
## payload. Only v1 exists, so there is nothing to migrate *from*; the policy (see
## ADR-012) is a hard gate: an unknown version is refused and the live scene is
## left alone, and any future format change must ship a migration function with an
## ADR rather than being inferred here.
##
## This probe writes a real checkpoint from a running preview and then tampers
## with it three ways, checking each is refused:
##   * outer format_version bumped, digest recomputed so only the gate can catch it
##   * inner shadow format_version bumped, envelope re-serialised and re-hashed
##   * a payload byte flipped without fixing the digest
##
## It also re-loads the untouched file to show a good snapshot still round-trips.

const STORE = preload("res://scripts/simulation/checkpoint_store.gd")
const SAVE_PATH := "user://t08_version_probe.scp"
const MAGIC_BYTES := 8
const HEADER_BYTES := MAGIC_BYTES + 4 + 4 + 32

var preview: Node3D
var finished := false
var started_ms := 0
var failures: Array[String] = []
var results: Array[String] = []
var stage := 0


func _init() -> void:
	call_deferred("_watchdog")
	call_deferred("_begin")


func _begin() -> void:
	started_ms = Time.get_ticks_msec()
	var scene: PackedScene = load("res://scenes/gpu_water_preview.tscn")
	if scene == null:
		_fail("preview scene unavailable")
		return
	preview = scene.instantiate()
	preview.preset_index = 1
	preview.enable_erosion = true
	preview.hide_hud = true
	root.add_child(preview)
	call_deferred("_wait_ready")


func _wait_ready() -> void:
	while not finished:
		if not preview.last_error.is_empty():
			_fail(preview.last_error)
			return
		if preview.ready_for_ticks and preview.completed_ticks >= 60:
			break
		await process_frame
	if finished:
		return
	preview.playing = false
	var waited := 0
	while not finished and preview.tick_pending and waited < 600:
		await process_frame
		waited += 1
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	var error: StringName = preview.request_checkpoint_save(SAVE_PATH)
	if not error.is_empty():
		_fail("checkpoint save refused: " + String(error))
		return
	waited = 0
	while not finished and preview.checkpoint_capture_pending and waited < 900:
		await process_frame
		waited += 1
	waited = 0
	while not finished and preview.last_save_path.is_empty() and \
			preview.last_save_error.is_empty() and waited < 900:
		await process_frame
		waited += 1
	if not preview.last_save_error.is_empty():
		_fail("checkpoint save failed: " + String(preview.last_save_error))
		return
	if preview.last_save_path.is_empty():
		_fail("checkpoint save never completed")
		return
	_check_round_trip()


func _check_round_trip() -> void:
	var loaded: Dictionary = STORE.load(SAVE_PATH)
	if not loaded.get("error", &"invalid").is_empty():
		failures.append("a fresh checkpoint did not load back: " + String(loaded.error))
		_run_tamper_cases()
		return
	results.append("ROUNDTRIP_OK tick=%d preset=%d enable_erosion=%s" % [
		loaded.checkpoint.tick, loaded.checkpoint.preset_index,
		str(loaded.enable_erosion)])
	_run_tamper_cases()


func _run_tamper_cases() -> void:
	var original := FileAccess.get_file_as_bytes(SAVE_PATH)
	if original.size() < HEADER_BYTES + 16:
		failures.append("checkpoint file too small to tamper with: %d bytes" % original.size())
		_report()
		return
	var payload_size := original.decode_u32(MAGIC_BYTES + 4)
	var payload := original.slice(HEADER_BYTES)

	## Case A: bump the outer version and recompute the digest, so nothing but the
	## version gate can reject it.
	var version_bumped := original.duplicate()
	version_bumped.encode_u32(MAGIC_BYTES, 99)
	var digest_a := _digest(payload)
	for i in 32:
		version_bumped[MAGIC_BYTES + 8 + i] = digest_a[i]
	results.append("TAMPER_A outer_version_99 rejected=%s" % str(
		not STORE.load(_write_case(version_bumped, "a")).get("error", &"").is_empty()))

	## Case B: bump the version inside the payload, re-serialise and re-hash.
	var envelope: Variant = bytes_to_var(payload)
	if typeof(envelope) != TYPE_DICTIONARY:
		failures.append("payload did not decode to a dictionary")
		_report()
		return
	envelope["format_version"] = 99
	var payload_b: PackedByteArray = var_to_bytes(envelope)
	var file_b := original.slice(0, MAGIC_BYTES + 8)
	file_b.encode_u32(MAGIC_BYTES + 4, payload_b.size())
	var digest_b := _digest(payload_b)
	file_b.append_array(digest_b)
	file_b.append_array(payload_b)
	results.append("TAMPER_B inner_version_99 rejected=%s" % str(
		not STORE.load(_write_case(file_b, "b")).get("error", &"").is_empty()))

	## Case C: flip a payload byte and leave the digest alone.
	var byte_flipped := original.duplicate()
	byte_flipped[HEADER_BYTES + 8] = byte_flipped[HEADER_BYTES + 8] ^ 0xFF
	results.append("TAMPER_C corrupt_payload rejected=%s" % str(
		not STORE.load(_write_case(byte_flipped, "c")).get("error", &"").is_empty()))

	## The untouched file must still load.
	results.append("UNTOUCHED_OK still_loads=%s payload_bytes=%d" % [
		str(STORE.load(SAVE_PATH).get("error", &"").is_empty()), payload_size])
	_report()


func _write_case(bytes: PackedByteArray, tag: String) -> String:
	var path := SAVE_PATH + "." + tag
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return path
	file.store_buffer(bytes)
	file.close()
	return path


func _digest(payload: PackedByteArray) -> PackedByteArray:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(payload)
	return hash.finish()


func _report() -> void:
	if finished:
		return
	var rejected_all := true
	for line in results:
		if line.contains("rejected=false") or line.contains("still_loads=false"):
			rejected_all = false
	if not rejected_all:
		failures.append("at least one tampered checkpoint was accepted")
	if not failures.is_empty():
		for failure in failures:
			printerr("FAIL: " + failure)
		for line in results:
			print(line)
		_finish(1)
		return
	for line in results:
		print(line)
	print("PASS: T08 save version gate cases=%d" % results.size())
	_finish(0)


func _watchdog() -> void:
	while not finished:
		if Time.get_ticks_msec() - started_ms > 600000:
			_fail("save version probe timed out")
			return
		await process_frame


func _fail(message: String) -> void:
	if finished:
		return
	printerr("FAIL: " + message)
	_finish(1)


func _finish(code: int) -> void:
	finished = true
	if preview != null:
		preview.queue_free()
	for _frame in 3:
		await process_frame
	quit(code)

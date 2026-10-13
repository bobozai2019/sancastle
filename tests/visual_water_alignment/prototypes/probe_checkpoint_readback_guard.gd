extends SceneTree

const Guard := preload("res://tests/visual_water_alignment/prototypes/checkpoint_readback_guard.gd")

var output_dir := ""


func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			output_dir = arg.trim_prefix("--output=")
	call_deferred("_run")


func _run() -> void:
	if not DirAccess.dir_exists_absolute(output_dir):
		_fail("output directory")
		return
	var expected := {
		"original": {"tick": 240, "revision": 240, "generation": 7},
		"restored": {"tick": 240, "revision": 240, "generation": 8},
	}
	var data := {
		"original_stamp": expected.original.duplicate(true),
		"restored_stamp": expected.restored.duplicate(true),
	}
	for field in Guard.FIELD_BYTES:
		var bytes := PackedByteArray()
		bytes.resize(Guard.FIELD_BYTES[field])
		bytes.fill(0)
		data["original_" + field] = bytes
		data["restored_" + field] = bytes.duplicate()
	var results := {}
	var normal: Dictionary = Guard.compare(data, expected, 240)
	if not normal.get("ok", false) or normal.equal_gpu_fields.size() != 5:
		_fail("valid readback rejected")
		return
	results["valid_different_generations"] = "PASS"
	var missing: Dictionary = data.duplicate(true)
	missing.erase("restored_foam_history")
	if not _expect_failure(missing, expected, 240, "missing/wrong-size GPU field",
			"missing_foam_field", results):
		return
	var empty_both: Dictionary = data.duplicate(true)
	empty_both["original_foam_history"] = PackedByteArray()
	empty_both["restored_foam_history"] = PackedByteArray()
	if not _expect_failure(empty_both, expected, 240, "missing/wrong-size GPU field",
			"both_empty_foam", results):
		return
	var short_both: Dictionary = data.duplicate(true)
	var short_bytes := PackedByteArray()
	short_bytes.resize(Guard.FIELD_BYTES.foam_history - 8)
	short_both["original_foam_history"] = short_bytes
	short_both["restored_foam_history"] = short_bytes.duplicate()
	if not _expect_failure(short_both, expected, 240, "missing/wrong-size GPU field",
			"both_equal_truncated_foam", results):
		return
	var short_water: Dictionary = data.duplicate(true)
	short_water["original_water"] = PackedByteArray()
	if not _expect_failure(short_water, expected, 240, "missing/wrong-size GPU field",
			"wrong_size_water", results):
		return
	var no_stamp: Dictionary = data.duplicate(true)
	no_stamp.erase("restored_stamp")
	if not _expect_failure(no_stamp, expected, 240, "missing/stale readback stamp",
			"missing_stamp", results):
		return
	var stale_stamp: Dictionary = data.duplicate(true)
	stale_stamp["restored_stamp"]["revision"] = 239
	if not _expect_failure(stale_stamp, expected, 240, "missing/stale readback stamp",
			"stale_revision", results):
		return
	if not _expect_failure(data, expected, 270, "invalid expected stamp",
			"wrong_target_tick", results):
		return
	var mismatch: Dictionary = data.duplicate(true)
	mismatch["restored_foam_history"][0] = 1
	if not _expect_failure(mismatch, expected, 240, "GPU field mismatch",
			"foam_content_mismatch", results):
		return
	var path := output_dir.path_join("readback_guard_negative_manifest.json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_fail("manifest write")
		return
	file.store_string(JSON.stringify(results, "\t"))
	file.close()
	print("PASS: checkpoint readback guard accepts real shape and rejects eight negatives")
	quit(0)


func _expect_failure(data: Dictionary, expected: Dictionary, target: int,
		needle: String, label: String, results: Dictionary) -> bool:
	var result: Dictionary = Guard.compare(data, expected, target)
	if result.get("ok", false) or not String(result.get("error", "")).contains(needle):
		_fail(label + " accepted or wrong reason: " + str(result))
		return false
	results[label] = result.error
	return true


func _fail(message: String) -> void:
	push_error("FAIL: checkpoint readback guard " + message)
	quit(1)

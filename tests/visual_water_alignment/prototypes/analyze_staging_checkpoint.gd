extends SceneTree

const Store := preload("res://scripts/simulation/checkpoint_store.gd")

var output_dir := ""
var run_id := ""
var old_dir := ""


func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			output_dir = arg.trim_prefix("--output=")
		elif arg.begins_with("--run-id="):
			run_id = arg.trim_prefix("--run-id=")
		elif arg.begins_with("--old-dir="):
			old_dir = arg.trim_prefix("--old-dir=")
	call_deferred("_run")


func _run() -> void:
	if output_dir.is_empty() or run_id.is_empty() or old_dir.is_empty():
		_fail("arguments")
		return
	var cases := {}
	for case_name in ["fixed", "coupled"]:
		var path := output_dir.path_join("%s_%s.sandcp" % [run_id, case_name])
		var loaded: Dictionary = Store.load(path)
		var old_path := old_dir.path_join("staging_active75_%s.sandcp" % case_name)
		var old_loaded: Dictionary = Store.load(old_path)
		if not loaded.error.is_empty() or old_loaded.error != &"invalid_local_front_history":
			_fail(case_name + " checkpoint load/version: " + String(loaded.error) +
				" / " + String(old_loaded.error))
			return
		var foam: PackedFloat32Array = loaded.checkpoint.foam_history
		var front: PackedFloat32Array = loaded.checkpoint.local_front_history
		var foam_cells := 0
		var front_cells := 0
		var max_foam := 0.0
		var max_front_peak := 0.0
		for i in 256 * 256:
			var foam_value: float = foam[2 * i]
			var front_peak: float = front[2 * i + 1]
			foam_cells += int(foam_value > 0.01)
			front_cells += int(front_peak > 0.000001)
			max_foam = maxf(max_foam, foam_value)
			max_front_peak = maxf(max_front_peak, front_peak)
		if foam_cells < 100 or front_cells < 100:
			_fail(case_name + " inactive saved visual fields foam=" +
				str(foam_cells) + " front=" + str(front_cells) +
				" max=" + str(max_foam) + "/" + str(max_front_peak))
			return
		cases[case_name] = {"foam_cells_gt_0_01": foam_cells,
			"local_front_cells_gt_1e_6": front_cells,
			"max_foam": max_foam, "max_local_front_peak": max_front_peak,
			"old_checkpoint_rejected_as": String(old_loaded.error)}
	var manifest := output_dir.path_join(run_id + "_coverage.json")
	var file := FileAccess.open(manifest, FileAccess.WRITE)
	if file == null:
		_fail("manifest write")
		return
	file.store_string(JSON.stringify({"run_id": run_id, "cases": cases}, "\t"))
	file.close()
	print("PASS: W08 staging checkpoint active coverage " + JSON.stringify(cases))
	quit(0)


func _fail(message: String) -> void:
	printerr("FAIL: W08 staging checkpoint coverage " + message)
	quit(1)

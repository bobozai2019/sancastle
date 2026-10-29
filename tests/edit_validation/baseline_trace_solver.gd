extends "res://scripts/simulation/gpu_shallow_solver.gd"

var record := Callable()
var patch_serial := 0
var output := ""

func request_data(field: String, callback: Callable) -> Error:
	if field == "sand":
		record.call("sand_readback_request", null, {"revision": state_revision,
			"callback": String(callback.get_method())})
	return super.request_data(field, callback)

func dispatch_tool_patch(data: PackedByteArray, count: int) -> bool:
	patch_serial += 1
	var serial := patch_serial
	record.call("patch_cpu_dispatch_begin", null, {"serial": serial, "count": count,
		"revision": state_revision})
	var ok := super.dispatch_tool_patch(data, count)
	record.call("patch_cpu_dispatch_end", null, {"serial": serial, "ok": ok,
		"revision": state_revision})
	if ok:
		# Diagnostic readback is an upper bound on completion, not GPU duration.
		var error := super.request_data("sand", _patch_complete.bind(serial, state_revision))
		if error != OK:
			record.call("patch_completion_error", null, {"serial": serial, "error": error})
	return ok

func _patch_complete(data: PackedByteArray, serial: int, revision: int) -> void:
	var path := "patch_%03d_sand.bin" % serial
	var file := FileAccess.open(output.path_join(path), FileAccess.WRITE)
	file.store_buffer(data)
	record.call("patch_readback_completion_upper_bound", null,
		{"serial": serial, "revision": revision, "bytes": data.size(), "path": path})

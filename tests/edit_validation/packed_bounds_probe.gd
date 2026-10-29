extends "res://tests/edit_validation/connected_runs_probe.gd"

func _write(ok: bool, error := "") -> void:
	var file := FileAccess.open(output.path_join("packed_bounds_probe.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass":ok,"rows":rows,"error":error,"scope":"33 disconnected components, <=6 runs per row; packed bound fallback and 3 tick continuation"},"\t"))

func _seed(size: int, _name: String) -> Dictionary:
	var fields := super._seed(size,"suspended_flow")
	for key in ["water","sediment","momentum_x","momentum_z"]: fields[key].fill(0.0)
	for i in 33:
		var x: int=size/2-24+(i%6)*8
		var z: int=size/2-24+(i/6)*8
		fields.water[z*size+x]=0.12
	return fields

func _run() -> void:
	var failure := ""
	var cases := ["component_overflow"]
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--case-filter="):
			var selected := arg.trim_prefix("--case-filter=")
			cases = [selected] if selected in cases else []
	for size in [64, 256]:
		lab = load("res://tests/edit_validation/edit_gpu_water_" + ("numeric" if size == 64 else "brush") + "_lab.tscn").instantiate()
		root.add_child(lab)
		while not lab.ready_for_ticks and lab.last_error.is_empty(): await process_frame
		if not lab.last_error.is_empty():
			failure = lab.last_error
			break
		for name in cases:
			await _case(name, size)
			if not lab.last_error.is_empty():
				failure = lab.last_error
				break
		await lab.shutdown()
		lab.queue_free()
		await process_frame
		lab = null
		if not failure.is_empty(): break
	var ok := failure.is_empty() and not cases.is_empty() and rows.size() == cases.size() * 4
	for row in rows: ok = ok and row.pass
	_write(ok, failure)
	if lab != null:
		await lab.shutdown()
		lab.queue_free()
	finished = true
	print("WATER_BRIDGE_COMPLETE pass=%s rows=%d" % [str(ok), rows.size()])
	quit(0 if ok else 1)



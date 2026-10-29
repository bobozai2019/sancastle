extends "res://tests/edit_validation/water_bridge_probe.gd"

func _write(ok: bool, error := "") -> void:
	var file := FileAccess.open(output.path_join("connected_runs_probe.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass":ok,"rows":rows,"error":error,"scope":"native C topology and 3 tick continuation; original CPU oracle and binary baseline comparison; no performance"},"\t"))

func _seed(size: int, name: String) -> Dictionary:
	var fields := super._seed(size,"suspended_flow")
	if name=="natural_snapshot":
		var base := "res://tests/fixtures/gpu_edit_validation/natural_snapshot/initial_"
		for field in fields:
			var file := FileAccess.open(base+field+".bin",FileAccess.READ)
			var bytes := file.get_buffer(file.get_length())
			var source := PackedFloat32Array()
			if field=="obstacle":
				source.resize(bytes.size())
				for i in bytes.size(): source[i]=float(bytes[i])/255.0
			else: source=bytes.to_float32_array()
			for z in size:
				for x in size: fields[field][z*size+x]=source[(z*256/size)*256+x*256/size]
		return fields
	for z in size:
		for x in size:
			var active := true
			match name:
				"coast_holes", "island_pool":
					active=x<size*3/4
					if x>=size/3 and x<size/3+4 and z>=size/3 and z<size/3+4: active=false
					if name=="island_pool" and x>=size*7/8 and z>=size/3 and z<size*2/3: active=true
				"diagonal_pools": active=(x<size/2 and z<size/2) or (x>=size/2 and z>=size/2)
				"run_overflow": active=x%4<2
				"gap_rows": active=z<size/2-1 or z>size/2+1
				"one_cell_bridge": active=x!=size/2 or z==size/2
			if not active:
				fields.water[z*size+x]=0.0
				fields.sediment[z*size+x]=0.0
				fields.momentum_x[z*size+x]=0.0
				fields.momentum_z[z*size+x]=0.0
	return fields

func _run() -> void:
	var failure := ""
	var cases := ["coast_holes", "island_pool", "diagonal_pools", "run_overflow", "gap_rows", "one_cell_bridge", "natural_snapshot"]
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



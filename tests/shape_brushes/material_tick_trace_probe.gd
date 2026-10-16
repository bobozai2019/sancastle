extends "res://tests/shape_brushes/retention_probe.gd"

# Diagnosis adds completed-tick readbacks; this is not the uninstrumented gate.
var tick_trace := []

func _ticks(count: int) -> void:
	for i in count:
		await super._ticks(1)
		if not preview.last_error.is_empty(): return
		readbacks.clear()
		RenderingServer.call_on_render_thread(read_all)
		var deadline := Time.get_ticks_msec()+30000
		while readbacks.size()<pair_fields and Time.get_ticks_msec()<deadline: await process_frame
		if readbacks.size()!=pair_fields:
			_check("trace_readbacks_complete",false,preview.completed_ticks)
			return
		var fields := {}
		for name in readbacks:
			var bytes: PackedByteArray=readbacks[name]
			var hash := HashingContext.new(); hash.start(HashingContext.HASH_SHA256); hash.update(bytes)
			var entry := {"bytes":bytes.size(),"sha256":hash.finish().hex_encode()}
			if name in ["sediment","spare_sediment"]:
				var path := output.path_join("trace_%04d_%s.bin"%[preview.completed_ticks,name])
				var file := FileAccess.open(path,FileAccess.WRITE); file.store_buffer(bytes); file.close()
				entry["path"]=path
			fields[name]=entry
		tick_trace.append({"tick":preview.completed_ticks,"revision":preview.solver.state_revision,"index":preview.solver.current_index,"fields":fields})
		if preview.completed_ticks%150==0: print("MATERIAL_TICK_TRACE ",preview.completed_ticks)

func capture(tick: int) -> void:
	await super.capture(tick)
	var file := FileAccess.open(output.path_join("tick_trace.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"scope":"Completed-tick diagnosis; extra readback may affect scheduling. Non-sediment fields have hashes only, not retained raw payloads.","ticks":tick_trace},"\t")); file.close()

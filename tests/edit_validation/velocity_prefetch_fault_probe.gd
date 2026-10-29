extends "res://tests/edit_validation/velocity_probe.gd"

var private_backup := {}
var fault_receipt := PackedByteArray()
var private_restored := false

func _write(ok: bool, error := "") -> void:
	var file := FileAccess.open(output.path_join("velocity_prefetch_fault_probe.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass":ok,"rows":rows,"error":error,"scope":"actual GPU private candidate corruption at warp/tile/end boundaries; direct reduction, not a committed transaction"},"\t"))

func _read_private() -> void:
	lab.solver.rd.buffer_get_data_async(lab.solver.water_candidate,_private_callback.bind("candidate"))
	lab.solver.rd.buffer_get_data_async(lab.solver.water_receipt,_private_callback.bind("receipt"))

func _private_callback(bytes: PackedByteArray, key: String) -> void:
	call_deferred("_private_record",bytes,key)

func _private_record(bytes: PackedByteArray, key: String) -> void:
	private_backup[key]=bytes

func _render_fault(offset: int, value: float) -> void:
	var rd: RenderingDevice=lab.solver.rd
	rd.buffer_update(lab.solver.water_candidate,0,private_backup.candidate.size(),private_backup.candidate)
	rd.buffer_update(lab.solver.water_receipt,0,128,private_backup.receipt)
	var patch := PackedByteArray();patch.resize(4);patch.encode_float(0,value)
	rd.buffer_update(lab.solver.water_candidate,offset,4,patch)
	lab.solver._water_dispatch(6)
	rd.buffer_get_data_async(lab.solver.water_receipt,_fault_callback)

func _fault_callback(bytes: PackedByteArray) -> void:
	call_deferred("_fault_record",bytes)

func _fault_record(bytes: PackedByteArray) -> void:
	fault_receipt=bytes

func _restore_private() -> void:
	var rd: RenderingDevice=lab.solver.rd
	rd.buffer_update(lab.solver.water_candidate,0,private_backup.candidate.size(),private_backup.candidate)
	rd.buffer_update(lab.solver.water_receipt,0,128,private_backup.receipt)
	call_deferred("_restore_record")

func _restore_record() -> void:
	private_restored=true

func _run() -> void:
	var ok := true
	for size in [64,256]:
		lab=load("res://tests/edit_validation/edit_gpu_water_"+("numeric" if size==64 else "brush")+"_lab.tscn").instantiate()
		root.add_child(lab)
		while not lab.ready_for_ticks and lab.last_error.is_empty(): await process_frame
		await lab.seed_test_fields(_seed(size,"still"))
		lab.water_policy=2;lab.signed_speed_m_s=0.25
		var result: Dictionary=await lab.apply_gpu_command(_command(1,0.01))
		if result.get("status")!=1: _write(false,"fixture command rejected");finished=true;quit(1);return
		var before: Dictionary=await _snapshot("%d_baseline" % size)
		var stock: float=lab.domain.tool_inventory_m3
		var revision: int=lab.solver.state_revision
		private_backup.clear();RenderingServer.call_on_render_thread(_read_private)
		while private_backup.size()<2: await process_frame
		_save("%d_candidate.bin" % size,private_backup.candidate)
		_save("%d_receipt.bin" % size,private_backup.receipt)
		var faults := [[63,0,NAN],[64,2,INF],[size*size-1,0,-1.0],[0,1,-1.0]]
		for i in faults.size():
			fault_receipt.clear()
			RenderingServer.call_on_render_thread(_render_fault.bind(int(faults[i][0])*16+int(faults[i][1])*4,float(faults[i][2])))
			while fault_receipt.is_empty(): await process_frame
			_save("%d_fault%d_receipt.bin" % [size,i],fault_receipt)
			var after: Dictionary=await _snapshot("%d_fault%d" % [size,i])
			var unchanged := true
			for key in before:
				if key!="water_receipt": unchanged=unchanged and before[key]==after[key]
			var passed: bool=fault_receipt.decode_u32(0)==2 and fault_receipt.decode_u32(4)==4 and fault_receipt.slice(8)==private_backup.receipt.slice(8) and unchanged and stock==lab.domain.tool_inventory_m3 and revision==lab.solver.state_revision
			rows.append({"grid":size,"fault":i,"cell":faults[i][0],"component":faults[i][1],"pass":passed,"physical_fields_unchanged":unchanged})
			ok=ok and passed
		private_restored=false;RenderingServer.call_on_render_thread(_restore_private)
		while not private_restored: await process_frame
		await lab.shutdown();lab.queue_free();await process_frame;lab=null
	_write(ok);finished=true;print("VELOCITY_PREFETCH_FAULT_COMPLETE pass=%s rows=%d" % [str(ok),rows.size()]);quit(0 if ok else 1)

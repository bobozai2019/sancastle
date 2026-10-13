extends "res://tests/edit_validation/connected_runs_probe.gd"

func _write(ok: bool,error := "") -> void:
	var file:=FileAccess.open(output.path_join("sand_audit_probe.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass":ok,"rows":rows,"error":error,"scope":"natural native transaction plus post-case sand candidate/control readback; no performance or root claim"},"\t"))

func _read_sand_audit() -> void:
	lab.solver.rd.buffer_get_data_async(lab.solver.cells_buffer,_on_extra.bind("sand_cells"))
	lab.solver.rd.buffer_get_data_async(lab.solver.control_buffer,_on_extra.bind("sand_control"))
	lab.solver.rd.buffer_get_data_async(lab.solver.water_input,_on_extra.bind("water_input"))
	lab.solver.rd.buffer_get_data_async(lab.solver.water_candidate,_on_extra.bind("water_candidate"))

func _case(name: String,size: int) -> void:
	await super._case(name,size)
	extras.clear();RenderingServer.call_on_render_thread(_read_sand_audit)
	while extras.size()<4: await process_frame
	for key in extras: _save("%s_%d_%s.bin"%[name,size,key],extras[key])

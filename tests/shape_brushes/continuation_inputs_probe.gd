extends "res://tests/shape_brushes/continuation_probe.gd"

var input_rows:Array=[]
var input_branch:=0
var last_input_tick:=-1

func _ticks(count:int) -> void:
	for tick in count:
		if preview.completed_ticks<last_input_tick:input_branch+=1
		preview.observe_coupled_parameters=true
		preview.coupled_parameter_trace.clear()
		preview.sediment_coupler.observe_pushes=true
		preview.sediment_coupler.bound_pushes.clear()
		preview.material_coupler.local_pushes.clear()
		await super._ticks(1)
		var coupled:Array=[]
		for row in preview.coupled_parameter_trace:
			coupled.append({"revision":row.revision,"index":row.index,"float64_hex":PackedFloat64Array([row.delta_s,row.cell_size_m,row.cohesion]).to_byte_array().hex_encode()})
		input_rows.append({"branch":input_branch,"tick":preview.completed_ticks,"substeps":preview.last_substeps,"coupled":coupled,"erosion_pushes":preview.sediment_coupler.bound_pushes.duplicate(true),"slope_pushes":preview.material_coupler.local_pushes.duplicate(true),"profile_sha256":preview.material_coupler.profile_sha256,"ordinary_shader_sha256":preview.material_coupler.ordinary_shader_hash})
		last_input_tick=preview.completed_ticks

func _finish() -> void:
	var file:=FileAccess.open(output.path_join("continuation_inputs.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"rows":input_rows,"scope":"Actual CPU substep float64 bytes, erosion push bytes, and local slope push bytes for each tick in original 10->310 mixed continuation. Reuses existing bounded CPU observers, clears after each completed tick. No shader changes or extra state readbacks. Does not record material-step push bytes or prove GPU inputs equal at every stage."},"\t"));file.close()
	super._finish()

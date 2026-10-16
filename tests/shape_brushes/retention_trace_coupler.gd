extends "res://scripts/simulation/edit_validation/staged_slope_coupler.gd"

var actual_pushes := []
var last_traced_tick := -1
var owner_entry: WeakRef

func _slope_push(delta_s: float) -> PackedByteArray:
	var bytes := super._slope_push(delta_s)
	var tick: int=owner_entry.get_ref().completed_ticks
	if tick!=last_traced_tick and (tick%150==0 or tick==899):
		actual_pushes.append({"tick":tick,"revision":solver.state_revision,"current_index":solver.current_index,"bytes_hex":bytes.hex_encode(),"values":Array(bytes.to_float32_array())})
		last_traced_tick=tick
	return bytes

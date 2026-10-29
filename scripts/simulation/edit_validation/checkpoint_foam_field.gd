extends "res://scripts/visual/gpu_foam_field.gd"

var native_history := {}

func _initial_texture_data(fallback: PackedByteArray, index: int, bed: bool) -> PackedByteArray:
	if native_history.is_empty(): return fallback
	current_index=native_history.current_index
	return native_history["bed_%d" % index] if bed else native_history["foam_%d" % index]

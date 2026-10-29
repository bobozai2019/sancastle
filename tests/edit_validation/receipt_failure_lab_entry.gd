extends "res://tests/edit_validation/gpu_brush_lab_entry.gd"

func _fail(message: String) -> void:
	if message == "GPU command dispatch failed":
		last_error = message
		ready_for_ticks = false
		print("EXPECTED_RECEIPT_FAILURE quarantine")
	else:
		super._fail(message)

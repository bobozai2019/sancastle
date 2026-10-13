extends "res://tests/edit_validation/gpu_water_lab_entry.gd"
signal dispatch_observed
var dispatch_state := {}
var exit_gpu_receipt := PackedByteArray()

func _render_command(data: PackedByteArray, token: int) -> void:
	super._render_command(data,token)
	call_deferred("_notify_dispatch",{"at_us":Time.get_ticks_usec(),"pending":solver.receipt_pending,"generation":token})

func _notify_dispatch(state: Dictionary) -> void:
	dispatch_state=state
	dispatch_observed.emit()

func _on_receipt(data: PackedByteArray, token: int) -> void:
	exit_gpu_receipt=data.duplicate()
	super._on_receipt(data,token)

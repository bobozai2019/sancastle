extends "res://tests/shape_brushes/brush_lab.gd"

var legacy_packet := PackedByteArray()
var legacy_packet_epoch := 0

func _on_gpu_receipt(bytes: PackedByteArray, token: int) -> void:
	if bytes.size()==128: legacy_packet=bytes.duplicate(); legacy_packet_epoch=token
	super._on_gpu_receipt(bytes,token)

extends "res://tests/shape_brushes/ui_lab.gd"

var hold_shape_receipt:=false
var held_shape_receipts:=[]
func _on_gpu_receipt(bytes:PackedByteArray,token:int) -> void:
	if bytes.size()==256 and hold_shape_receipt:call_deferred("hold_receipt",bytes,token)
	else:super._on_gpu_receipt(bytes,token)
func hold_receipt(bytes:PackedByteArray,token:int) -> void:held_shape_receipts.append({"bytes":bytes,"token":token})
func release_shape_receipts() -> void:
	hold_shape_receipt=false
	while not held_shape_receipts.is_empty():
		var item:Dictionary=held_shape_receipts.pop_front();_settle_gpu_receipt(item.bytes,item.token)

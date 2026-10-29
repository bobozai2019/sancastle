extends "res://scripts/simulation/edit_validation/collision_proxy.gd"

# Delays actual readback delivery in this test scene, preserving real bytes.
var hold_data:=false
var held_data:=[]
func _apply_data(data:PackedByteArray,chunks:PackedInt32Array,revision:int,token:int,elapsed_ms:float,queued_usec:PackedInt64Array,requested_usec:int,readback_done_usec:int) -> void:
	if hold_data:
		held_data.append([data,chunks,revision,token,elapsed_ms,queued_usec,requested_usec,readback_done_usec]);return
	super._apply_data(data,chunks,revision,token,elapsed_ms,queued_usec,requested_usec,readback_done_usec)
func release_data() -> void:
	hold_data=false
	while not held_data.is_empty():
		var row:Array=held_data.pop_front()
		super._apply_data(row[0],row[1],row[2],row[3],row[4],row[5],row[6],row[7])

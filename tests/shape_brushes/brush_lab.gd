extends "res://scripts/beach/shape_brush_entry.gd"

const Fixtures = preload("res://tests/shape_brushes/fixtures.gd")
@export_enum("dry_flat", "dry_slope", "thin_sand", "shallow_water", "submerged", "isolated_pool", "boundary") var brush_fixture := "dry_flat"
var hold_shape_receipt := false
var held_shape_receipts: Array = []

func _on_gpu_receipt(bytes: PackedByteArray, token: int) -> void:
	if bytes.size()==256 and hold_shape_receipt: call_deferred("_hold_receipt",bytes,token)
	else: super._on_gpu_receipt(bytes,token)

func _hold_receipt(bytes: PackedByteArray, token: int) -> void:
	held_shape_receipts.append({"bytes":bytes,"token":token})

func release_shape_receipts() -> void:
	hold_shape_receipt=false
	while not held_shape_receipts.is_empty():
		var item: Dictionary=held_shape_receipts.pop_front()
		_settle_gpu_receipt(item.bytes,item.token)

func _initialize_domain(target: SandWaterDomain) -> bool:
	var data := Fixtures.build(brush_fixture)
	if data.is_empty(): return false
	for field in ["rock", "sand", "water", "sediment", "wetness", "compaction", "obstacle"]: target.set(field, data.fields[field])
	target.set_meta("edit_validation_initial_qx", data.fields.momentum_x)
	target.set_meta("edit_validation_initial_qz", data.fields.momentum_z)
	target.sim_tick = 0
	return true

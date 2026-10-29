extends "res://tests/shape_brushes/water_lab.gd"
@export var guard_mode:="clamp"
func _initialize_domain(target:SandWaterDomain) -> bool:
	if not super._initialize_domain(target):return false
	var qx:=PackedFloat32Array();var qz:=PackedFloat32Array();qx.resize(65536);qz.resize(65536)
	qx.fill(1.95 if guard_mode=="clamp" else 50.0)
	target.set_meta("edit_validation_initial_qx",qx);target.set_meta("edit_validation_initial_qz",qz)
	return true

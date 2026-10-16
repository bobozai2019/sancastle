extends "res://scripts/beach/shape_brush_playable_entry.gd"

const Fixtures=preload("res://tests/shape_brushes/fixtures.gd")
func _initialize_domain(target:SandWaterDomain) -> bool:
	var data:=Fixtures.build("dry_flat")
	for field in ["rock","sand","water","sediment","wetness","compaction","obstacle"]:target.set(field,data.fields[field])
	target.set_meta("edit_validation_initial_qx",data.fields.momentum_x);target.set_meta("edit_validation_initial_qz",data.fields.momentum_z)
	target.sim_tick=0;return true

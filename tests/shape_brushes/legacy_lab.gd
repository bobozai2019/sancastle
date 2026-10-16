extends "res://scripts/beach/beach_playable_entry.gd"

const Fixtures = preload("res://tests/shape_brushes/fixtures.gd")
@export_enum("dry_flat", "dry_slope", "thin_sand", "shallow_water", "submerged", "isolated_pool", "boundary") var brush_fixture := "dry_flat"

func _initialize_domain(target: SandWaterDomain) -> bool:
	var data := Fixtures.build(brush_fixture)
	if data.is_empty(): return false
	for field in ["rock", "sand", "water", "sediment", "wetness", "compaction", "obstacle"]: target.set(field,data.fields[field])
	target.set_meta("edit_validation_initial_qx",data.fields.momentum_x)
	target.set_meta("edit_validation_initial_qz",data.fields.momentum_z)
	target.sim_tick=0
	return true

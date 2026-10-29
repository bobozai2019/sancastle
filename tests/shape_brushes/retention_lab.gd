extends "res://tests/shape_brushes/brush_lab.gd"

const RetentionFixture = preload("res://tests/shape_brushes/retention_fixture.gd")
@export_enum("baseline","compact","cohesion") var retention_mode := "baseline"
var cfl_inputs := []

func _on_cfl(data: PackedByteArray, revision: int, token: int) -> void:
	var hash := HashingContext.new(); hash.start(HashingContext.HASH_SHA256); hash.update(data)
	cfl_inputs.append({"tick":completed_ticks+1,"revision":revision,"generation":token,"sha256":hash.finish().hex_encode()})
	super._on_cfl(data,revision,token)

func _create_material_coupler() -> SandcastleGpuMaterialCoupler:
	var coupler=preload("res://tests/shape_brushes/retention_trace_coupler.gd").new()
	coupler.owner_entry=weakref(self)
	return coupler

func _initialize_domain(target: SandWaterDomain) -> bool:
	var data := RetentionFixture.build(retention_mode)
	for field in ["rock","sand","water","sediment","wetness","compaction","obstacle"]: target.set(field,data.fields[field])
	target.set_meta("edit_validation_initial_qx",data.fields.momentum_x)
	target.set_meta("edit_validation_initial_qz",data.fields.momentum_z)
	target.sim_tick=0
	return true

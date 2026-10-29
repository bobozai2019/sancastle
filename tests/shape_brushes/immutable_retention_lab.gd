extends "res://tests/shape_brushes/original_retention_lab.gd"

func _create_material_coupler() -> SandcastleGpuMaterialCoupler:
	var coupler=preload("res://tests/shape_brushes/immutable_material_coupler.gd").new()
	coupler.owner_entry=weakref(self)
	return coupler

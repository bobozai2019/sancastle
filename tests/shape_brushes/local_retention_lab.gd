extends "res://tests/shape_brushes/retention_lab.gd"

@export var use_local_support := true

func _create_material_coupler() -> SandcastleGpuMaterialCoupler:
	return preload("res://scripts/simulation/brushes/brush_material_coupler.gd").new()

func _initialize_domain(target: SandWaterDomain) -> bool:
	retention_mode="compact"
	if not super._initialize_domain(target): return false
	var tags := PackedFloat32Array(); tags.resize(target.sand.size()); tags.fill(0.0)
	if use_local_support:
		for z in 256:
			for x in 256:
				var p := Vector2((x+0.5-128)*0.125,(z+0.5-128)*0.125)
				if (absf(p.x)<=2.0 and absf(p.y)<=2.0) or (p.x<-4.0 and absf(p.y)<=1.0):
					tags[z*256+x]=maxf(0.0,target.sand[z*256+x]-1.0)
	target.set_meta("brush_initial_mold_depth",tags)
	return true

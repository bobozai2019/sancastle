extends "res://tests/shape_brushes/brush_lab.gd"

@export_enum("wrong_type","short","negative","overflow","nan") var invalid_mode := "wrong_type"

func _initialize_domain(target: SandWaterDomain) -> bool:
	if not super._initialize_domain(target): return false
	if invalid_mode=="wrong_type": target.set_meta("brush_initial_mold_depth",[0.0]);return true
	var tags:=PackedFloat32Array();tags.resize(65535 if invalid_mode=="short" else 65536);tags.fill(0.0)
	if invalid_mode=="negative": tags[0]=-0.1
	elif invalid_mode=="overflow": tags[0]=target.sand[0]+1.0
	elif invalid_mode=="nan": tags[0]=NAN
	target.set_meta("brush_initial_mold_depth",tags)
	return true

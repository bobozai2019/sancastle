extends "res://tests/shape_brushes/brush_lab.gd"

@export_enum("erosion","deposition","slope_dry","slope_wet","slope_thin","slope_obstacle") var operator_case := "erosion"

func _initialize_domain(target: SandWaterDomain) -> bool:
	brush_fixture="dry_flat"
	if not super._initialize_domain(target): return false
	var tags:=PackedFloat32Array();tags.resize(65536);tags.fill(0.0)
	var peak:=128*256+128
	for i in 65536:
		target.compaction[i]=0.9501953125
		target.wetness[i]=1.0 if operator_case=="slope_wet" else 0.0
	if operator_case in ["erosion","deposition"]:
		for i in 65536:
			target.water[i]=1.0
			target.sediment[i]=0.1 if operator_case=="deposition" else 0.0
		for z in range(127,130):
			for x in range(127,130): tags[z*256+x]=0.3
	else:
		target.sand[peak]=3.0
		tags[peak]=0.02 if operator_case=="slope_thin" else 0.3
		if operator_case=="slope_obstacle": target.obstacle[peak]=1.0
	target.set_meta("brush_initial_mold_depth",tags)
	return true

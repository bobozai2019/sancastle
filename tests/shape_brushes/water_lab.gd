extends "res://tests/shape_brushes/brush_lab.gd"

@export var water_fixture_mode := ""

func _initialize_domain(target:SandWaterDomain) -> bool:
	if not super._initialize_domain(target):return false
	if water_fixture_mode=="obstacle":target.obstacle[128*256+128]=1.0
	if water_fixture_mode in ["disconnected","capacity"]:
		for z in 256:
			for x in 256:
				var point:=Vector2((x+0.5-128)*0.125,(z+0.5-128)*0.125)
				var near:=point.length()<(0.5 if water_fixture_mode=="capacity" else 2.0)
				var remote:=water_fixture_mode=="disconnected" and point.distance_to(Vector2(8,0))<1.0
				var i:=z*256+x
				target.water[i]=0.1 if near or remote else 0.0
				target.rock[i]=-1.0 if near or remote else 0.5
	if water_fixture_mode=="loaded":
		var qx:=PackedFloat32Array();var qz:=PackedFloat32Array();qx.resize(65536);qz.resize(65536)
		for i in 65536:
			target.sediment[i]=0.001;qx[i]=0.002;qz[i]=-0.001
		target.set_meta("edit_validation_initial_qx",qx);target.set_meta("edit_validation_initial_qz",qz)
	return true

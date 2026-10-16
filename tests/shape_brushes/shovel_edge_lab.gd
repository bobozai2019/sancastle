extends "res://tests/shape_brushes/water_lab.gd"
@export var edge_mode:=""
func _initialize_domain(target:SandWaterDomain) -> bool:
	if not super._initialize_domain(target):return false
	if edge_mode in ["low","high"]:
		var depth:=0.0001 if edge_mode=="low" else 1024.0
		target.sand.fill(depth);target.rock.fill(-depth)
	if edge_mode=="left_blocked":
		for z in 256:
			for x in 256:
				var point:=Vector2((x+0.5-128)*0.125,(z+0.5-128)*0.125)
				var closest:=Vector2(clampf(point.x,-0.5,0.5),0)
				if point.y>0.0 and point.distance_to(closest)>=0.25:target.obstacle[z*256+x]=1.0
	if edge_mode=="donor_blocked":target.obstacle[128*256+128]=1.0
	return true

extends "res://tests/shape_brushes/brush_lab.gd"

@export var block_right_shoulder := false

func _initialize_domain(target: SandWaterDomain) -> bool:
	if not super._initialize_domain(target):return false
	if block_right_shoulder:
		for z in 256:
			for x in 256:
				var pos:=Vector2((x+0.5-128)*0.125,(z+0.5-128)*0.125)
				var closest:=Vector2(clampf(pos.x,-1,1),0)
				if pos.y<0.0 and pos.distance_to(closest)>=0.25:target.obstacle[z*256+x]=1.0
	return true

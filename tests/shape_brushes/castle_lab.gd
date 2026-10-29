extends "res://tests/shape_brushes/brush_lab.gd"

@export var steep_foundation := false
@export var foundation_obstacle := false
@export var fixed_height_case := ""

func _initialize_domain(target: SandWaterDomain) -> bool:
	if not super._initialize_domain(target):return false
	if steep_foundation:
		for z in 256:
			for x in 256:target.rock[z*256+x]=0.1*(x+0.5-128)*0.125-target.sand[z*256+x]
	if foundation_obstacle:target.obstacle[128*256+128]=1.0
	if fixed_height_case=="deep":
		for i in target.rock.size():target.rock[i]-=1.0
	if fixed_height_case=="mixed":
		for z in range(120,136):
			for x in range(120,136):
				var i:=z*256+x
				if x<124:target.sand[i]=3.0 # Existing high pile: retain exactly.
				elif x<128:target.rock[i]=1.5;target.sand[i]=0.0 # High rock: retain exactly.
				elif x<132:target.rock[i]=-0.1;target.sand[i]=0.0 # Low rock: cover with sand.
				else:target.sand[i]=0.2 # Low existing sand: fill the deficit.
	return true

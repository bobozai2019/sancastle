extends "res://tests/shape_brushes/water_lab.gd"
@export var dry_elevated:=false
func _initialize_domain(target:SandWaterDomain) -> bool:
	if not super._initialize_domain(target):return false
	# Keep the real boundary solver active. Bed=1 is above its water level;
	# bed=0 in the original dry initializer receives boundary water over time.
	if dry_elevated:target.rock.fill(0.0)
	return true

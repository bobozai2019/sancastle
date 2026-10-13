class_name SandcastleBrushIndicator
extends MeshInstance3D

## T07 G04: shows where the sand brush will act and how wide it is.
##
## The brush is a 0.38 m circle in world XZ, so the indicator is a thin ring of
## that radius sitting just above the bed at the cursor. It is presentation only:
## it reads the cursor and the shadow bed to place itself and never writes state.

const BRUSH_RADIUS_M := 0.38
const RING_WIDTH_M := 0.075
const LIFT_M := 0.025

const DIG_COLOR := Color(0.92, 0.35, 0.20, 0.85)
const PLACE_COLOR := Color(0.25, 0.62, 0.95, 0.85)
const IDLE_COLOR := Color(0.16, 0.18, 0.22, 0.75)

@onready var material: StandardMaterial3D = material_override as StandardMaterial3D


## `kind` is the brush's command kind (`remove_sand`, `place_sand`, or empty).
func aim(world: Vector3, surface_y: float, kind: StringName) -> void:
	position = Vector3(world.x, surface_y + LIFT_M, world.z)
	visible = true
	match kind:
		&"remove_sand":
			material.albedo_color = DIG_COLOR
		&"place_sand":
			material.albedo_color = PLACE_COLOR
		_:
			material.albedo_color = IDLE_COLOR


func hide_indicator() -> void:
	visible = false

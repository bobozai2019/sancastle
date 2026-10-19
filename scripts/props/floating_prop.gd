extends RigidBody3D

@export var body_id: int=1
@export var profile: Resource
@export var footprint_radius_m: float=0.38
var service
var in_inventory:=false

func set_in_inventory(value: bool) -> void:
	in_inventory=value
	visible=not value
	collision_layer=0 if value else 2
	collision_mask=0 if value else 3
	if value:
		freeze=true
		linear_velocity=Vector3.ZERO
		angular_velocity=Vector3.ZERO

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if service!=null:service.observe_step(self,state)

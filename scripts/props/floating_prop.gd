extends RigidBody3D

@export var body_id: int=1
@export var profile: Resource
@export var footprint_radius_m: float=0.38
var service

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if service!=null:service.observe_step(self,state)

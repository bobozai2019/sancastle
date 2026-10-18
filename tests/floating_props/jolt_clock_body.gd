extends RigidBody3D

var steps: Array=[]
var total_time:=0.0

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	total_time+=state.step
	steps.append({"step":state.step,"time":total_time,"position":state.transform.origin,"velocity":state.linear_velocity,"frame":Engine.get_physics_frames()})

extends RigidBody3D

var steps: Array=[]

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	steps.append({"frame":Engine.get_physics_frames(),"y":state.transform.origin.y,"velocity_y":state.linear_velocity.y,"contacts":state.get_contact_count(),"step":state.step})

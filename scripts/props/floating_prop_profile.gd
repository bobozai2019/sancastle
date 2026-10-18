extends Resource

# Declarative physical data only. The consumer validates an exact script binding.
@export var type_id: StringName
@export var version: int=1
@export var mass_kg: float=0.1
@export var center_of_mass_m: Vector3=Vector3.ZERO
@export var point_positions_m: Array[Vector3]=[]
@export var point_half_heights_m: PackedFloat32Array
@export var point_volumes_m3: PackedFloat32Array
@export var point_mass_weights: PackedFloat32Array
@export var drag_time_horizontal_s: float=0.5
@export var drag_time_vertical_s: float=0.3
@export var friction: float=0.6
@export var angular_damping: float=0.5
@export var max_speed_m_s: float=4.0
@export var max_angular_speed_rad_s: float=8.0
@export var max_sample_age_s: float=0.15
@export var max_pose_distance_m: float=0.15
@export var max_pose_angle_rad: float=0.35

func validate() -> StringName:
	if String(type_id).is_empty() or version<1 or not center_of_mass_m.is_finite():return &"invalid_profile"
	for value in [mass_kg,drag_time_horizontal_s,drag_time_vertical_s,max_speed_m_s,max_angular_speed_rad_s,max_sample_age_s,max_pose_distance_m,max_pose_angle_rad]:
		if not is_finite(value) or value<=0.0:return &"invalid_profile"
	if not is_finite(friction) or friction<0.0 or friction>1.0 or not is_finite(angular_damping) or angular_damping<0.0:return &"invalid_profile"
	var count:=point_positions_m.size()
	if count<1 or count>32 or point_half_heights_m.size()!=count or point_volumes_m3.size()!=count or point_mass_weights.size()!=count:return &"invalid_profile"
	var weight:=0.0
	for index in count:
		if not point_positions_m[index].is_finite():return &"invalid_profile"
		for values in [point_half_heights_m,point_volumes_m3,point_mass_weights]:
			if not is_finite(values[index]) or values[index]<=0:return &"invalid_profile"
		weight+=point_mass_weights[index]
	if absf(weight-1.0)>0.000001:return &"invalid_profile"
	return &""

func snapshot() -> Dictionary:
	if not validate().is_empty():return {}
	var points: Array=[]
	for index in point_positions_m.size():points.append({"local_position_m":point_positions_m[index],"half_height_m":point_half_heights_m[index],"effective_volume_m3":point_volumes_m3[index],"mass_weight":point_mass_weights[index]})
	return {"type_id":type_id,"version":version,"mass_kg":mass_kg,"center_of_mass_m":center_of_mass_m,"points":points,"drag_time_horizontal_s":drag_time_horizontal_s,"drag_time_vertical_s":drag_time_vertical_s,"friction":friction,"angular_damping":angular_damping,"max_speed_m_s":max_speed_m_s,"max_angular_speed_rad_s":max_angular_speed_rad_s,"max_sample_age_s":max_sample_age_s,"max_pose_distance_m":max_pose_distance_m,"max_pose_angle_rad":max_pose_angle_rad}

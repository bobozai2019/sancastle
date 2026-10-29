extends Resource

@export var reference_height_m := 0.0
@export_range(0.125,1.0,0.025) var radius_m := 0.3
@export_range(0.0001,0.06,0.0001) var dig_amount_m3 := 0.015
@export_range(0.0001,0.06,0.0001) var fill_amount_m3 := 0.015
@export_enum("none","amount_template","amount_velocity_template") var water_mode := 2
@export var diagnostics := false
@export var exact_backend := false
@export_range(0,3,1) var exact_water_policy := 3

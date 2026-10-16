extends Node3D

@onready var castle:MeshInstance3D=$CastleGhost
@onready var footprint:MeshInstance3D=$Footprint

func configure(tool:StringName,params:Dictionary,position_xz:Vector2,base:float,start:Vector2,finish:Vector2,state:StringName) -> void:
	castle.visible=tool==&"castle_v1";footprint.visible=tool in [&"wall_v1",&"shovel_v1"]
	var color:=Color(1,0.25,0.2,0.45) if state==&"invalid" else (Color(1,0.75,0.2,0.4) if state==&"waiting" else Color(0.2,1,0.5,0.4))
	if castle.visible:
		castle.position=Vector3(position_xz.x,base,position_xz.y);castle.rotation.y=-params.yaw_rad
		castle.scale=Vector3(params.scale_xz,1,params.scale_xz)
		castle.material_override.set_shader_parameter("height_m",params.height_m);castle.material_override.set_shader_parameter("tint",color)
	if footprint.visible:
		footprint.position=Vector3(position_xz.x,0,position_xz.y)
		var material:ShaderMaterial=footprint.material_override
		material.set_shader_parameter("operation",2 if tool==&"wall_v1" else 3)
		material.set_shader_parameter("start_xz",start);material.set_shader_parameter("end_xz",finish);material.set_shader_parameter("tint",color)
		for key in params:material.set_shader_parameter(key,params[key])

func bind_fields(rock:Texture2D,sand:Texture2D,baseline:Texture2D) -> void:
	var material:ShaderMaterial=footprint.material_override
	material.set_shader_parameter("rock_state",rock);material.set_shader_parameter("sand_state",sand);material.set_shader_parameter("stroke_baseline",baseline)

func hide_preview() -> void:
	castle.visible=false;footprint.visible=false

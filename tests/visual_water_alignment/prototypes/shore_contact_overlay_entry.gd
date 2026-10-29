extends "res://tests/visual_water_alignment/prototypes/rock_reflection_candidate_entry.gd"

@onready var contact_overlay: MeshInstance3D = $ShoreContactOverlay


func _configure_scene() -> void:
	super._configure_scene()
	contact_overlay.mesh = ($GpuWaterSurface as MeshInstance3D).mesh
	var material := contact_overlay.material_override as ShaderMaterial
	material.set_shader_parameter("rock_state", rock_texture)
	material.set_shader_parameter("sand_state", sand_texture)
	material.set_shader_parameter("water_state", water_texture)
	material.set_shader_parameter("foam_state", foam_texture)
	material.set_shader_parameter("local_front_state", local_front_texture)

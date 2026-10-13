extends "res://scripts/visual/test1_beach_fixed_entry.gd"


func _configure_scene() -> void:
	super._configure_scene()
	var overlay := $DrySandLightOverlay as MeshInstance3D
	overlay.mesh = ($GpuSandTerrain as MeshInstance3D).mesh
	var material := overlay.material_override as ShaderMaterial
	material.set_shader_parameter("rock_state", rock_texture)
	material.set_shader_parameter("sand_state", sand_texture)
	material.set_shader_parameter("wetness_state", wetness_texture)
	material.set_shader_parameter("compaction_state", compaction_texture)
	material.set_shader_parameter("water_state", water_texture)
	material.set_shader_parameter("display_reconstruction", render_subdivision > 1)

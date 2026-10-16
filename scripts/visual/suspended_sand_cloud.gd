extends MeshInstance3D

@onready var beach = get_parent()
var source_material: ShaderMaterial
var cloud_material: ShaderMaterial

func _process(_delta: float) -> void:
	if not beach.ready_for_ticks or beach.closing:
		visible = false
		return
	if cloud_material == null:
		var water: MeshInstance3D = beach.get_node("GpuWaterSurface")
		mesh = water.mesh
		custom_aabb = water.custom_aabb
		source_material = water.material_override
		cloud_material = material_override.duplicate()
		material_override = cloud_material
		# Share the water geometry's reconstruction, crest and contact inputs.
		for uniform in cloud_material.shader.get_shader_uniform_list():
			var value: Variant = source_material.get_shader_parameter(uniform.name)
			if value != null: cloud_material.set_shader_parameter(uniform.name, value)
		cloud_material.set_shader_parameter("suspended_sand_state", beach.sediment_texture)
		var bias: Variant = source_material.get_shader_parameter("water_surface_bias_m")
		cloud_material.set_shader_parameter("water_surface_bias_m", (float(bias) if bias != null else 0.006) + 0.001)
	cloud_material.set_shader_parameter("visual_time_s", beach.visual_time_s)
	cloud_material.set_shader_parameter("debug_mode", beach.debug_view)
	visible = true

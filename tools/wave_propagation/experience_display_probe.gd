extends "res://tools/wave_propagation/experience_body_probe.gd"
# A single visual factor. No field, force or tool parameters are changed.
func _process(delta: float) -> bool:
	if scene != null:
		var surface = scene.get_node_or_null("GpuWaterSurface")
		if surface != null and surface.material_override is ShaderMaterial:
			surface.material_override.set_shader_parameter("use_detail_normals",false)
	return super._process(delta)

func snapshot(label: String) -> void:
	await super.snapshot(label)
	var material: ShaderMaterial=scene.get_node("GpuWaterSurface").material_override
	check("detail_off:"+label,material.get_shader_parameter("use_detail_normals")==false)
	current.snapshots[-1].display_override={"use_detail_normals":false,"node":"GpuWaterSurface","scope":"single factor display diagnostic; production material unchanged"}

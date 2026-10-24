extends "res://docs/competitor/tools/probe_foam_comparison.gd"

# No material replacement: validate what the formal scene actually starts with.
func _capture(label: String) -> void:
	await super._capture(label)
	if label!="t0":return
	var material: ShaderMaterial=scene.get_node("GpuWaterSurface").material_override
	var texture: Texture2D=material.get_shader_parameter("foam_detail_texture")
	check("formal_new_mode_enabled",material.get_shader_parameter("foam_detail_mode")==1)
	check("formal_texture_static_binding",texture!=null and texture.resource_path=="res://assets/water_foam/foam_detail.png")
	if texture!=null:
		var image:=texture.get_image()
		check("formal_texture_mips_and_budget",image.get_width()==512 and image.get_height()==512 and image.get_mipmap_count()==9 and image.get_data_size()<=2097152)
		observations.formal_texture={"path":texture.resource_path,"source_sha256":FileAccess.get_sha256(texture.resource_path),"format":image.get_format(),"mipmap_count":image.get_mipmap_count(),"bytes":image.get_data_size()}
	check("formal_flow_cycle",is_equal_approx(float(material.get_shader_parameter("foam_flow_cycle_s")),4.0))
	check("formal_detail_scale",is_equal_approx(float(material.get_shader_parameter("foam_detail_scale_per_m")),1.0))
	check("formal_diagnostic_disabled",material.get_shader_parameter("foam_flow_debug")==false)
	check("formal_sparse_foam_hidden",not scene.get_node("PrototypeFrontFoamDense").visible)
	var contact: ShaderMaterial=scene.get_node("ShoreContactOverlay").material_override
	check("formal_contact_gain",is_equal_approx(float(contact.get_shader_parameter("natural_contact_gain")),0.55))

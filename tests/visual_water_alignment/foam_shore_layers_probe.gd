extends "res://tests/visual_water_alignment/foam_natural_sequence.gd"

func _capture(label: String) -> void:
	await super._capture(label)
	if label not in ["natural_040","natural_080","natural_120"]:return
	var contact: Node3D=scene.get_node("ShoreContactOverlay")
	var visible:=contact.visible
	contact.hide()
	await super._capture(label+"_no_shore_contact")
	contact.visible=visible
	var material: ShaderMaterial=scene.get_node("GpuWaterSurface").material_override
	var gain: Variant=material.get_shader_parameter("natural_main_foam_gain")
	material.set_shader_parameter("natural_main_foam_gain",0.0)
	await super._capture(label+"_no_water_foam")
	material.set_shader_parameter("natural_main_foam_gain",gain)
	material.set_shader_parameter("foam_detail_mode",0)
	await super._capture(label+"_legacy_foam")
	material.set_shader_parameter("foam_detail_mode",1)
	await super._capture(label+"_layers_restored")
	check(label+"_layer_toggle_exact_restore",FileAccess.get_sha256(output+"/"+label+".png")==FileAccess.get_sha256(output+"/"+label+"_layers_restored.png"))

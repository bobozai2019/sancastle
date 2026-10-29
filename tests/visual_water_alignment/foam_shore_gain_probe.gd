extends "res://tests/visual_water_alignment/foam_natural_sequence.gd"

func _capture(label: String) -> void:
	await super._capture(label)
	if label not in ["natural_040","natural_080","natural_120"]:return
	var material: ShaderMaterial=scene.get_node("ShoreContactOverlay").material_override
	var original: Variant=material.get_shader_parameter("natural_contact_gain")
	if not observations.has("shore_gain_scan"):observations.shore_gain_scan=[]
	for gain in [0.35,0.55,0.75,1.0]:
		material.set_shader_parameter("natural_contact_gain",gain)
		var file:=label+"_shore_gain_%03d"%int(round(gain*100))
		await super._capture(file)
		observations.shore_gain_scan.append({"file":file+".png","gain":gain,"tick":scene.runtime.current.completed_tick,"time_s":scene.runtime.current.advanced_time_s})
	material.set_shader_parameter("natural_contact_gain",original)
	await super._capture(label+"_gain_restored")
	check(label+"_gain_restore_exact",FileAccess.get_sha256(output+"/"+label+".png")==FileAccess.get_sha256(output+"/"+label+"_gain_restored.png"))

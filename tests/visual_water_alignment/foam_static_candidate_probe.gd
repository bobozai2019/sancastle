extends "res://docs/competitor/tools/probe_foam_comparison.gd"

func _capture(label: String) -> void:
	await super._capture(label)
	if label not in ["t240","t360"]:return
	var material: ShaderMaterial=scene.get_node("GpuWaterSurface").material_override
	var original:=material.shader
	var values:={}
	for uniform in original.get_shader_uniform_list():
		values[uniform.name]=material.get_shader_parameter(uniform.name)
	var shader_path:="res://assets/water_foam/static_candidate.gdshader"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--foam-shader="):shader_path=arg.trim_prefix("--foam-shader=")
	var candidate: Shader=load(shader_path)
	var texture_path:="res://assets/water_foam/foam_cells.png"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--foam-texture="):texture_path=arg.trim_prefix("--foam-texture=")
	var texture: Texture2D=load(texture_path)
	check("candidate_texture_imported",texture!=null and texture.get_width()==512)
	if texture==null:return
	material.shader=candidate
	for key in values:material.set_shader_parameter(key,values[key])
	material.set_shader_parameter("foam_detail_texture",texture)
	material.set_shader_parameter("foam_detail_mode",1)
	await super._capture(label+"_candidate")
	if not observations.has("candidate"):observations.candidate={"material":_material(material),"frames":[]}
	observations.candidate.frames.append({"label":label,"tick":scene.runtime.current.completed_tick,"time_s":scene.runtime.current.advanced_time_s})
	material.set_shader_parameter("foam_detail_mode",0)
	await super._capture(label+"_candidate_disabled")
	check(label+"_mode0_matches_baseline",FileAccess.get_sha256(output+"/"+label+".png")==FileAccess.get_sha256(output+"/"+label+"_candidate_disabled.png"))
	material.shader=original
	for key in values:material.set_shader_parameter(key,values[key])

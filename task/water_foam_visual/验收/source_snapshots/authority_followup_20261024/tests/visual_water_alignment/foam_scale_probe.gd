extends "res://tests/visual_water_alignment/foam_static_candidate_probe.gd"

func _capture(label: String) -> void:
	await super._capture(label)
	if label!="t240":return
	var material: ShaderMaterial=scene.get_node("GpuWaterSurface").material_override
	var original:=material.shader
	var values:={}
	for uniform in original.get_shader_uniform_list():values[uniform.name]=material.get_shader_parameter(uniform.name)
	material.shader=load("res://assets/water_foam/static_candidate.gdshader")
	for key in values:material.set_shader_parameter(key,values[key])
	var texture_path:="res://assets/water_foam/foam_cells.png"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--foam-texture="):texture_path=arg.trim_prefix("--foam-texture=")
	material.set_shader_parameter("foam_detail_texture",load(texture_path))
	material.set_shader_parameter("foam_detail_mode",1)
	var image:=Image.create(4,4,false,Image.FORMAT_RF)
	image.fill(Color(0.4,0,0,1))
	material.set_shader_parameter("foam_state",ImageTexture.create_from_image(image))
	observations.scale_scan=[]
	for scale in [0.5,0.75,1.0,2.0,3.0]:
		material.set_shader_parameter("foam_detail_scale_per_m",scale)
		var file:="scale_%03d"%int(scale*100)
		await super._capture(file)
		observations.scale_scan.append({"file":file+".png","scale_per_m":scale,"history":0.4,"tick":scene.runtime.current.completed_tick})
	material.shader=original
	for key in values:material.set_shader_parameter(key,values[key])

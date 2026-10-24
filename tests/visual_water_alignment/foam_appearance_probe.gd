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
	material.set_shader_parameter("foam_detail_texture",load("res://assets/water_foam/foam_cells_organic.png"))
	material.set_shader_parameter("foam_detail_mode",1)
	var image:=Image.create(4,4,false,Image.FORMAT_RF)
	image.fill(Color(0.4,0,0,1))
	material.set_shader_parameter("foam_state",ImageTexture.create_from_image(image))
	var clock: float=scene.runtime.current.advanced_time_s
	await super._capture("appearance_720")
	await create_timer(1.0).timeout
	await super._capture("appearance_720_paused")
	check("paused_static_identical",FileAccess.get_sha256(output+"/appearance_720.png")==FileAccess.get_sha256(output+"/appearance_720_paused.png"))
	var camera: Camera3D=scene.get_viewport().get_camera_3d()
	var fov:=camera.fov
	camera.fov=fov*0.6
	await super._capture("appearance_near")
	camera.fov=min(fov*1.3,110.0)
	await super._capture("appearance_far")
	camera.fov=fov
	DisplayServer.window_set_size(Vector2i(1920,1080));root.content_scale_size=Vector2i(1920,1080)
	await super._capture("appearance_1080")
	observations.appearance={"camera_fov":fov,"near_fov":fov*0.6,"far_fov":min(fov*1.3,110.0),"viewport_1080":var_to_str(root.size),"history_fixture":0.4,"material":_material(material)}
	DisplayServer.window_set_size(Vector2i(1280,720));root.content_scale_size=Vector2i(1280,720)
	var sun: DirectionalLight3D=scene.get_node("SandFixtureSun")
	var energy:=sun.light_energy
	sun.light_energy=0.0
	await super._capture("appearance_sun_off")
	sun.light_energy=energy*2
	await super._capture("appearance_sun_double")
	sun.light_energy=energy
	material.set_shader_parameter("natural_lighting_debug",4)
	await super._capture("appearance_foam_direct_only")
	material.set_shader_parameter("natural_lighting_debug",0)
	image=Image.create(4,4,false,Image.FORMAT_RF);image.fill(Color(0,0,0,1))
	material.set_shader_parameter("water_state",ImageTexture.create_from_image(image))
	await super._capture("appearance_dry")
	material.set_shader_parameter("natural_main_foam_gain",0.0)
	await super._capture("appearance_dry_gain_zero")
	check("dry_has_no_candidate_foam",FileAccess.get_sha256(output+"/appearance_dry.png")==FileAccess.get_sha256(output+"/appearance_dry_gain_zero.png"))
	check("appearance_clock_unchanged",scene.runtime.current.advanced_time_s==clock)
	material.shader=original
	for key in values:material.set_shader_parameter(key,values[key])

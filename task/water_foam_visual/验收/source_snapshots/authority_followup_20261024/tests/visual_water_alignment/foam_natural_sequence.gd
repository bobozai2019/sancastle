extends "res://docs/competitor/tools/probe_foam_comparison.gd"

func _initialize() -> void:
	super._initialize()
	RenderingServer.frame_pre_draw.connect(_hide_brush_overlays)

func _hide_brush_overlays() -> void:
	if not is_instance_valid(scene):return
	for path in ["BrushIndicator","BrushPreview"]:
		var node: Node3D=scene.get_node_or_null(path)
		if node!=null:node.hide()
	observations.capture_ui="HUD and cursor brush overlays hidden; all water/sand/environment layers retained"

# Production initialization and physical inputs; only the candidate material changes.
func _run() -> void:
	orphan_baseline=int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	DisplayServer.window_set_size(Vector2i(1280,720))
	scene=load("res://scenes/main.tscn" if scene_key=="main" else "res://scenes/playable/test1_geometry.tscn").instantiate()
	scene.playing=false;scene.generation=1001;root.add_child(scene)
	var deadline:=Time.get_ticks_msec()+90000
	while (not scene.ready_for_ticks or scene._booting) and scene.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	check("entry_ready",scene.ready_for_ticks and scene.last_error.is_empty())
	if not scene.ready_for_ticks:observations.error=String(scene.last_error);await _close();return
	scene.hide_hud=true;scene.get_node("Interface").hide()
	observations.configuration=scene.configuration.duplicate(true)
	var material: ShaderMaterial=scene.get_node("GpuWaterSurface").material_override
	var values:={}
	for uniform in material.shader.get_shader_uniform_list():values[uniform.name]=material.get_shader_parameter(uniform.name)
	material.shader=load("res://assets/water_foam/flow_candidate.gdshader")
	for key in values:material.set_shader_parameter(key,values[key])
	material.set_shader_parameter("foam_detail_texture",load("res://assets/water_foam/foam_cells_organic.png"))
	material.set_shader_parameter("foam_detail_mode",1)
	material.set_shader_parameter("foam_flow_debug",false)
	var contact: ShaderMaterial=scene.get_node("ShoreContactOverlay").material_override
	if "--foam-baseline" in OS.get_cmdline_user_args():
		material.shader=load("res://task/water_foam_visual/验收/G4/before_integration/assets/water_material_natural_candidate/async_rdc_water.gdshader")
		for key in values:material.set_shader_parameter(key,values[key])
		contact.set_shader_parameter("natural_contact_gain",1.0)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--contact-gain="):contact.set_shader_parameter("natural_contact_gain",float(arg.trim_prefix("--contact-gain=")))
	observations.contact_material=_material(contact)
	observations.candidate={"material":_material(material)}
	var camera: Camera3D=scene.get_viewport().get_camera_3d()
	observations.camera={"transform":var_to_str(camera.global_transform),"fov":camera.fov}
	observations.render={"adapter":RenderingServer.get_video_adapter_name(),"engine":Engine.get_version_info(),"driver":RenderingServer.get_current_rendering_driver_name(),"size":var_to_str(root.size)}
	observations.frames=[]
	for index in 121:
		var target:=index*6
		while scene.runtime.current.completed_tick<target:
			var error: StringName=scene.runtime.current.request_tick(1.0/30.0)
			if not error.is_empty():check("request_tick",false);await _close();return
			await _wait_tick()
		check("target_"+str(target),scene.runtime.current.completed_tick==target)
		if "--layer-only" in OS.get_cmdline_user_args() and target%120!=0:continue
		var file:="natural_%03d"%index
		await _capture(file)
		var row:={"file":file+".png","tick":target,"time_s":scene.runtime.current.advanced_time_s,"state_seq":scene.runtime.current.completed_state_seq,"generation":scene.generation}
		if target%120==0:
			var texture: Texture2D=material.get_shader_parameter("foam_state")
			var field:=texture.get_image().get_data().to_float32_array()
			var peak:=0.0;var sum:=0.0;var counts:=[0,0,0,0]
			for cell in 65536:
				var f:=field[cell*2]
				peak=max(peak,f);sum+=f
				for level in 4:
					if f>=[0.03,0.15,0.4,0.8][level]:counts[level]+=1
			row.foam_history={"max":peak,"mean":sum/65536.0,"cells_above_003_015_04_08":counts}
		observations.frames.append(row)
		if target==240:
			await create_timer(1.0).timeout
			await _capture("natural_paused_repeat")
			check("natural_paused_same_clock_same_pixels",FileAccess.get_sha256(output+"/"+file+".png")==FileAccess.get_sha256(output+"/natural_paused_repeat.png"))
	await _after_sequence()
	await _close()

func _after_sequence() -> void:
	pass

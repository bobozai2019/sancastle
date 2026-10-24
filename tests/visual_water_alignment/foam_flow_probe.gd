extends "res://tests/visual_water_alignment/foam_static_candidate_probe.gd"

func _run() -> void:
	if "--standalone-flow" not in OS.get_cmdline_user_args():
		await super._run()
		return
	orphan_baseline=int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	DisplayServer.window_set_size(Vector2i(1280,720))
	scene=load("res://scenes/main.tscn" if scene_key=="main" else "res://scenes/playable/test1_geometry.tscn").instantiate()
	scene.playing=false;scene.generation=1001;root.add_child(scene)
	var deadline:=Time.get_ticks_msec()+90000
	while (not scene.ready_for_ticks or scene._booting) and scene.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	check("entry_ready",scene.ready_for_ticks and scene.last_error.is_empty())
	if not scene.ready_for_ticks:await _close();return
	scene.hide_hud=true;scene.get_node("Interface").hide()
	observations.configuration=scene.configuration.duplicate(true)
	observations.render={"engine":Engine.get_version_info(),"adapter":RenderingServer.get_video_adapter_name(),"driver":RenderingServer.get_current_rendering_driver_name(),"size":var_to_str(root.size)}
	while scene.runtime.current.completed_tick<360:
		var error: StringName=scene.runtime.current.request_tick(1.0/30.0)
		if not error.is_empty():check("request_tick",false);await _close();return
		await _wait_tick()
	await _capture("fixture_start")
	await _close()

func _field(values: PackedFloat32Array) -> ImageTexture:
	return ImageTexture.create_from_image(Image.create_from_data(256,256,false,Image.FORMAT_RF,values.to_byte_array()))

func _capture(label: String) -> void:
	await super._capture(label)
	# Run camera/slow-frame fixtures after the historical baseline comparisons.
	# Reframing can change a few unrelated gravel rasterization pixels.
	if label not in ["t360_restored","fixture_start"]:return
	var quick: bool="--quick-flow" in OS.get_cmdline_user_args()
	var sides: Node3D=scene.get_node("WaterSides")
	var sides_processing:=sides.is_processing()
	var sides_visible:=sides.visible
	sides.set_process(false);sides.hide()
	var material: ShaderMaterial=scene.get_node("GpuWaterSurface").material_override
	var original:=material.shader
	var values:={}
	for uniform in original.get_shader_uniform_list():values[uniform.name]=material.get_shader_parameter(uniform.name)
	material.shader=load("res://assets/water_foam/flow_candidate.gdshader")
	for key in values:material.set_shader_parameter(key,values[key])
	material.set_shader_parameter("foam_detail_texture",load("res://assets/water_foam/foam_cells_organic.png"))
	material.set_shader_parameter("foam_detail_mode",1)
	material.set_shader_parameter("foam_flow_debug",true)
	observations.candidate={"material":_material(material)}
	var image:=Image.create(4,4,false,Image.FORMAT_RF);image.fill(Color(0.4,0,0,1))
	material.set_shader_parameter("foam_state",ImageTexture.create_from_image(image))
	var water_texture: Texture2D=values[&"water_state"]
	var depth:=water_texture.get_image().get_data().to_float32_array()
	check("depth_fixture_size",depth.size()==65536)
	if depth.size()!=65536:return
	var zeros:=PackedFloat32Array();zeros.resize(65536)
	material.set_shader_parameter("momentum_z_state",_field(zeros))
	var physical_clock: float=scene.runtime.current.advanced_time_s
	var physical_tick: int=scene.runtime.current.completed_tick
	var camera: Camera3D=scene.get_viewport().get_camera_3d()
	observations.flow_fixture={"type":"Read-only material overrides after baseline comparison; authoritative state frozen","completed_tick":physical_tick,"completed_time_s":physical_clock,"generation":scene.generation,"state_seq":scene.runtime.current.completed_state_seq,"camera":var_to_str(camera.global_transform),"screen_world_x":var_to_str(camera.unproject_position(Vector3(1,0,0))-camera.unproject_position(Vector3.ZERO)),"frames":[]}
	observations.flow_fixture.quick=quick
	observations.flow_fixture.isolation="WaterSides temporarily hidden and its process suspended only for grayscale foam fixture; its clock-driven ripple is independent of foam velocity. Natural production sequences retain it."
	for fixture in ["positive","negative","zero","near_zero"]:
		var velocity:=0.3 if fixture=="positive" else (-0.3 if fixture=="negative" else (0.0001 if fixture=="near_zero" else 0.0))
		var flux:=PackedFloat32Array();flux.resize(65536)
		for i in flux.size():flux[i]=max(depth[i],0.02)*velocity
		material.set_shader_parameter("momentum_x_state",_field(flux))
		var count:=81 if fixture in ["positive","negative"] and not quick else 3
		for frame in count:
			var time: float=float(frame)*0.1 if fixture in ["positive","negative"] else [0.0,1.37,8.23][frame]
			var clock_image:=Image.create(1,1,false,Image.FORMAT_RF);clock_image.fill(Color(time,0,0,1))
			material.set_shader_parameter("async_clock",ImageTexture.create_from_image(clock_image))
			var file:="flow_%s_%03d"%[fixture,frame]
			await super._capture(file)
			observations.flow_fixture.frames.append({"file":file+".png","fixture":fixture,"time_s":time,"velocity_x_m_s":velocity,"authoritative_tick":physical_tick})
		if fixture=="zero":check("zero_flow_two_cycles_identical",FileAccess.get_sha256(output+"/flow_zero_000.png")==FileAccess.get_sha256(output+"/flow_zero_002.png"))
	await super._capture("flow_pause_start")
	await create_timer(1.0).timeout
	await super._capture("flow_pause_end")
	check("flow_paused_clock_identical",FileAccess.get_sha256(output+"/flow_pause_start.png")==FileAccess.get_sha256(output+"/flow_pause_end.png"))
	var moving_flux:=PackedFloat32Array();moving_flux.resize(65536)
	for i in moving_flux.size():moving_flux[i]=max(depth[i],0.02)*0.3
	material.set_shader_parameter("momentum_x_state",_field(moving_flux))
	var saved_clock:=Image.create(1,1,false,Image.FORMAT_RF);saved_clock.fill(Color(1.37,0,0,1))
	var saved_bytes:=saved_clock.get_data()
	FileAccess.open(output+"/fixture_clock.bin",FileAccess.WRITE).store_buffer(saved_bytes)
	material.set_shader_parameter("async_clock",ImageTexture.create_from_image(saved_clock))
	await super._capture("clock_restore_reference")
	var other_clock:=Image.create(1,1,false,Image.FORMAT_RF);other_clock.fill(Color(6.7,0,0,1))
	material.set_shader_parameter("async_clock",ImageTexture.create_from_image(other_clock))
	await super._capture("clock_restore_other_time")
	material.set_shader_parameter("async_clock",ImageTexture.create_from_image(Image.create_from_data(1,1,false,Image.FORMAT_RF,FileAccess.get_file_as_bytes(output+"/fixture_clock.bin"))))
	await super._capture("clock_restored_bytes")
	check("clock_bytes_restore_same_phase",FileAccess.get_sha256(output+"/clock_restore_reference.png")==FileAccess.get_sha256(output+"/clock_restored_bytes.png"))
	var max_fps:=Engine.max_fps
	Engine.max_fps=5
	await super._capture("clock_slow_frames")
	Engine.max_fps=max_fps
	check("slow_frame_same_completed_time_phase",FileAccess.get_sha256(output+"/clock_restore_reference.png")==FileAccess.get_sha256(output+"/clock_slow_frames.png"))
	var original_fov:=camera.fov
	observations.flow_fixture.dynamic_views=[]
	for view in ["near","far"]:
		camera.fov=original_fov*(0.6 if view=="near" else 1.3)
		for time in [1.9,2.0,2.1,3.9,4.0,4.1]:
			var frame_clock:=Image.create(1,1,false,Image.FORMAT_RF);frame_clock.fill(Color(time,0,0,1))
			material.set_shader_parameter("async_clock",ImageTexture.create_from_image(frame_clock))
			var file:="flow_%s_t%03d"%[view,int(round(time*10))]
			await super._capture(file)
			observations.flow_fixture.dynamic_views.append({"file":file+".png","fov":camera.fov,"time_s":time})
	camera.fov=original_fov
	check("flow_authoritative_state_not_advanced",scene.runtime.current.completed_tick==physical_tick and scene.runtime.current.advanced_time_s==physical_clock)
	material.set_shader_parameter("foam_flow_debug",false)
	material.shader=original
	for key in values:material.set_shader_parameter(key,values[key])
	sides.visible=sides_visible;sides.set_process(sides_processing)

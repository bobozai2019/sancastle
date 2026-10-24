extends "res://tests/integration/unified_edit_playable_probe.gd"

var baseline_kernel: Dictionary
var baseline_set := RID()
var candidate_kernel: Dictionary
var candidate_set := RID()
var swap_done := false
var wet_rid := RID()
var installed := false
var install_error := ""
var wet_wrapper: Texture2DRD
var base_shader: Shader
var trial_shader: Shader

func _install() -> void:
	var state = scene.runtime.current.state
	var water_bytes: PackedByteArray = state.rd.texture_get_data(state.textures.water[0],0)
	var sand_bytes: PackedByteArray = state.rd.texture_get_data(state.textures.sand[0],0)
	var seed := PackedFloat32Array();seed.resize(65536)
	for i in 65536:
		seed[i] = 0.4*smoothstep(0.001,0.003,water_bytes.decode_float(i*4)) if sand_bytes.decode_float(i*4)>0.02 else 0.0
	wet_rid=state._create_texture(RenderingDevice.DATA_FORMAT_R32_SFLOAT,seed.to_byte_array())
	if not state.compile("wet_trial","res://task/wet_sand_visual/fused_publish.glsl"):
		install_error=state.last_error;call_deferred("_install_done");return
	var binding: RID=state.binding("wet_trial",{0:scene.runtime.current.transport.control,1:state.published_stamp},{2:state.textures.sand[0],3:state.textures.water[0],4:state.published_sand,5:state.published_water,6:wet_rid})
	baseline_kernel=state.kernels.publish;baseline_set=state.publish_set
	candidate_kernel=state.kernels.wet_trial;candidate_set=binding
	state.kernels.publish=state.kernels.wet_trial
	state.publish_set=binding
	call_deferred("_install_done")

func _install_done() -> void:installed=true

var read_done := false
var read_result := {}

func _read_fields(label: String) -> void:
	var owner = scene.runtime.current
	var result := {}
	for field in ["rock", "sand", "water", "wetness", "compaction"]:
		var rid: RID = owner.state.textures[field] if field == "rock" else owner.state.textures[field][0]
		var bytes: PackedByteArray = owner.state.rd.texture_get_data(rid, 0)
		var path: String = output + "/" + label + "_" + field + ".bin"
		FileAccess.open(path, FileAccess.WRITE).store_buffer(bytes)
		result[field] = {"path": path, "sha256": FileAccess.get_sha256(path), "bytes": bytes.size()}
	var view_bytes: PackedByteArray = owner.state.rd.texture_get_data(owner.views.textures.wetness, 0)
	var path := output + "/" + label + "_view_wetness.bin"
	FileAccess.open(path, FileAccess.WRITE).store_buffer(view_bytes)
	result.view_wetness = {"path": path, "sha256": FileAccess.get_sha256(path), "bytes": view_bytes.size()}
	var wet_bytes: PackedByteArray = owner.state.rd.texture_get_data(wet_rid,0)
	var wet_path := output + "/" + label + "_surface.bin"
	FileAccess.open(wet_path,FileAccess.WRITE).store_buffer(wet_bytes)
	result.surface={"path":wet_path,"sha256":FileAccess.get_sha256(wet_path),"bytes":wet_bytes.size()}
	call_deferred("_received", result)

func _received(result: Dictionary) -> void:
	read_result = result
	read_done = true

func _snapshot(label: String) -> void:
	read_done = false
	RenderingServer.call_on_render_thread(_read_fields.bind(label))
	while not read_done: await process_frame
	check(label + "_view_matches_authority", read_result.wetness.sha256 == read_result.view_wetness.sha256)
	observations.snapshots.append({"label": label, "tick": scene.runtime.current.completed_tick, "time": scene.runtime.current.advanced_time_s, "fields": read_result.duplicate(true)})

func _capture(label: String) -> void:
	for frame in 6:
		await process_frame
		await RenderingServer.frame_post_draw
	check("capture_" + label, root.get_texture().get_image().save_png(output + "/" + label + ".png") == OK)

func _run() -> void:
	orphan_baseline = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	DisplayServer.window_set_size(Vector2i(1280, 720))
	scene = load("res://scenes/main.tscn" if scene_key == "main" else "res://scenes/playable/test1_geometry.tscn").instantiate()
	scene.playing = false
	scene.generation = 1001
	root.add_child(scene)
	var start := Time.get_ticks_msec()
	while (not scene.ready_for_ticks or scene._booting) and scene.last_error.is_empty() and Time.get_ticks_msec() - start < 90000: await process_frame
	check("formal_entry_ready", scene.ready_for_ticks and scene.last_error.is_empty())
	if not scene.ready_for_ticks: observations.error = String(scene.last_error); await _close(); return
	scene.hide_hud = true
	observations.configuration = scene.configuration.duplicate(true)
	observations.sources = scene.configuration.sources.duplicate(true)
	observations.snapshots = []
	observations.camera = var_to_str(root.get_camera_3d().global_transform)
	var material: ShaderMaterial = scene.get_node("GpuSandTerrain").material_override
	observations.material = {}
	for uniform in material.shader.get_shader_uniform_list():
		var value: Variant = material.get_shader_parameter(uniform.name)
		if not value is Object: observations.material[uniform.name] = value
	check("wetness_bound_to_published_view", material.get_shader_parameter("wetness_state").texture_rd_rid == scene.runtime.current.views.textures.wetness)
	RenderingServer.call_on_render_thread(_install)
	while not installed:await process_frame
	check("fused_install",install_error.is_empty() and wet_rid.is_valid())
	if not install_error.is_empty():observations.error=install_error;await _close();return
	wet_wrapper=Texture2DRD.new();wet_wrapper.texture_rd_rid=wet_rid
	base_shader=material.shader
	trial_shader=Shader.new()
	trial_shader.code=base_shader.code.replace("uniform bool use_wet_finish = true;","uniform bool use_wet_finish = true;\nuniform sampler2D surface_wetness_state : filter_linear, repeat_disable;").replace("(use_wet_finish ? wet : 0.0) * 0.65","use_wet_finish ? smoothstep(0.0,0.4,texture(surface_wetness_state,UV).r) : 0.0")
	material.shader=trial_shader;material.set_shader_parameter("surface_wetness_state",wet_wrapper)
	observations.trial_shader_sha=trial_shader.code.sha256_text()
	await _snapshot("t00")
	await _capture("t00")
	scene._on_trigger_wave_pressed()
	observations.wave_message = scene.action_message
	for target in [16]:
		scene.playing = true
		start = Time.get_ticks_msec()
		while scene.runtime.current.advanced_time_s < target and scene.last_error.is_empty() and Time.get_ticks_msec() - start < 90000: await process_frame
		scene.playing = false
		await _idle()
		check("advanced_" + str(target), scene.runtime.current.advanced_time_s >= target and scene.last_error.is_empty())
		var label := "t%02d" % target
		await _snapshot(label)
		await _capture(label)
		material.shader=base_shader
		await _capture(label+"_baseline")
		material.shader=trial_shader;material.set_shader_parameter("surface_wetness_state",wet_wrapper)
		print("WET_DIAG_STATE ", label, " ", scene.runtime.current.advanced_time_s)
	await _snapshot("paused_before")
	await create_timer(2.0).timeout
	await _snapshot("paused_after")
	check("pause_preserves_history",observations.snapshots[-1].fields.surface.sha256==observations.snapshots[-2].fields.surface.sha256)
	await _cost(material)
	material.shader=base_shader;material.set_shader_parameter("surface_wetness_state",null)
	wet_wrapper.texture_rd_rid=RID();wet_wrapper=null
	await _close()

func _swap(use_trial: bool) -> void:
	var state=scene.runtime.current.state
	state.kernels.publish=candidate_kernel if use_trial else baseline_kernel
	state.publish_set=candidate_set if use_trial else baseline_set
	call_deferred("_swap_received")

func _swap_received() -> void:swap_done=true

func _cost(material: ShaderMaterial) -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	root.grab_focus()
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	observations.cost={"device":RenderingServer.get_video_adapter_name(),"driver":RenderingServer.get_current_rendering_driver_name(),"size":str(DisplayServer.window_get_size()),"vsync":DisplayServer.window_get_vsync_mode(),"phases":[],"note":"Preliminary ABBA; frozen state for draw, evolving state for live; viewport GPU excludes standalone compute; wall frame includes actual workload. Not representative final cost acceptance."}
	for mode in ["frozen","live"]:
		for use_trial in [false,true,true,false]:
			scene.playing=false;await _idle()
			swap_done=false;RenderingServer.call_on_render_thread(_swap.bind(use_trial))
			while not swap_done:await process_frame
			material.shader=trial_shader if use_trial else base_shader
			if use_trial:material.set_shader_parameter("surface_wetness_state",wet_wrapper)
			scene.playing=mode=="live"
			await create_timer(2.0).timeout
			var begin:=Time.get_ticks_usec();var last:=begin
			var start_tick: int=scene.runtime.current.completed_tick
			var start_time: float=scene.runtime.current.advanced_time_s
			var rows:=[]
			while Time.get_ticks_usec()-begin<6000000:
				await process_frame
				var now:=Time.get_ticks_usec()
				rows.append([float(now-last)/1000.0,RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()),root.has_focus()]);last=now
			observations.cost.phases.append({"mode":mode,"trial":use_trial,"rows":rows,"wall_s":float(last-begin)/1000000.0,"ticks":scene.runtime.current.completed_tick-start_tick,"sim_s":scene.runtime.current.advanced_time_s-start_time})
			print("WET_COST ",mode," ",use_trial," ",rows.size())
	scene.playing=false;await _idle()

extends SceneTree

var beach
var checks: Array=[]
var output:="res://test_output/parameter_windows/runtime"
var mode:="smoke"

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
		if arg.begins_with("--mode="):mode=arg.trim_prefix("--mode=")
	DirAccess.make_dir_recursive_absolute(output)
	call_deferred("_run")

func check(label: String, passed: bool, detail: Variant=null) -> void:
	checks.append({"name":label,"pass":passed,"detail":detail});print("PARAMETER_CHECK ",label," ",passed," ",detail)

func _run() -> void:
	beach=load("res://scenes/main.tscn").instantiate();beach.playing=false;root.add_child(beach)
	current_scene=beach
	var deadline:=Time.get_ticks_msec()+60000
	while (not beach.ready_for_ticks or beach._booting) and beach.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	check("boot",beach.ready_for_ticks and beach.last_error.is_empty(),String(beach.last_error))
	if beach.ready_for_ticks:
		await process_frame
		var service=root.get_node("Parameters")
		check("bound",service.scene==beach)
		for id in service.editing:
			if service.available.get(id,false) and not service.Schema.valid(id,service.editing[id]):print("INVALID_DEFAULT ",id," ",service.editing[id])
		check("static_windows",service.GROUPS.size()==6 and service.get_node("water") is Window)
		for group in service.GROUPS:
			var window: Window=service.get_node(group)
			service.open_window(group);await process_frame
			check("native_"+group,not window.is_embedded())
			window.close_requested.emit();check("hide_"+group,not window.visible and is_instance_valid(window))
		if mode=="smoke":
			check("radius_change",service.set_value("radius_m",1.0).is_empty() and beach.tool_parameters().radius_m==1.0)
			check("wave_next",service.set_value("manual_wave_amplitude_m",.15).is_empty() and beach.manual_wave_amplitude_m==.15)
			var material: ShaderMaterial=beach.get_node("GpuWaterSurface").material_override
			check("live_material",service.set_value("visual_rdc_normal_gain",.5).is_empty() and material.get_shader_parameter("rdc_normal_gain")==.5)
			check("restart_pending",service.set_value("erosion_rate_per_s",.5).is_empty() and not beach.configuration.environment.get("coupling_parameters",{}).has("erosion_rate_per_s"))
			check("range_rejected",not service.set_value("radius_m",-1.0).is_empty())
			service.open_window("tools")
			for frame in 5:await process_frame
			check("parameter_window_has_focus",service.get_node("tools").has_focus() and not root.has_focus())
			var camera_before: Transform3D=beach.player_camera.transform
			var event:=InputEventKey.new();event.physical_keycode=KEY_W;event.keycode=KEY_W;event.pressed=true;event.window_id=service.get_node("tools").get_window_id()
			Input.parse_input_event(event)
			for frame in 5:await process_frame
			check("subwindow_w_does_not_move_camera",camera_before==beach.player_camera.transform)
			event.pressed=false;Input.parse_input_event(event)
			var space:=InputEventKey.new();space.keycode=KEY_SPACE;space.pressed=true;space.window_id=event.window_id
			beach._unhandled_input(space);check("subwindow_space_does_not_play",not beach.playing)
			service.get_node("tools").hide()
			check("strength_change",service.set_value("strength",.5).is_empty())
			await _edit(&"place_sand")
			await _edit(&"remove_sand")
			beach._on_tool_changed(&"smooth_v1");await _edit(&"smooth_v1")
			beach._on_tool_changed(&"compact_v1");await _edit(&"compact_v1")
			beach._on_tool_changed(&"remove_sand")
			beach._on_trigger_wave_pressed()
			check("wave_consumes_parameters",beach.runtime.current.boundary.requests.back().amplitude_m==.15)
			await _ticks(5)
			var checkpoint_error: StringName=await beach.save_gpu_checkpoint(output.path_join("state.sandue"))
			check("checkpoint_save",checkpoint_error.is_empty(),String(checkpoint_error))
			if checkpoint_error.is_empty():
				var restore_error: StringName=await beach.restore_gpu_checkpoint(output.path_join("state.sandue"))
				check("checkpoint_restore",restore_error.is_empty(),String(restore_error))
			for frame in 3:await process_frame
			service.save_parameters()
			check("saved",service.saved.get("main",{}).get("erosion_rate_per_s")==.5,service.message)
			check("not_applied_by_save",beach.runtime.current.state.coupling_parameters.get("erosion_rate_per_s",.7295628483661365)==.7295628483661365)
		elif mode=="restart":
			check("saved_tuning_consumed",beach.runtime.current.state.coupling_parameters.get("erosion_rate_per_s")==.5,beach.runtime.current.state.coupling_parameters)
			check("saved_live_consumed",beach.get_node("GpuWaterSurface").material_override.get_shader_parameter("rdc_normal_gain")==.5)
			await _ticks(3)
		elif mode=="matrix":
			check("scene_visual_edit",service.set_value("visual_rdc_normal_gain",.6).is_empty())
			check("scene_pending_edit",service.set_value("erosion_rate_per_s",.45).is_empty())
			var scenes=root.get_node("BeachScenes")
			for key in ["test1_capture","test1_backwash","test1_geometry","main"]:
				check(key+"_switch_admitted",scenes.request_switch(key))
				deadline=Time.get_ticks_msec()+120000
				while scenes.busy and Time.get_ticks_msec()<deadline:await process_frame
				beach=scenes.active_scene
				check(key+"_switched",not scenes.busy and scenes.last_error.is_empty() and beach.scene_key==key,scenes.last_error)
				check(key+"_parameter_binding",service.scene==beach)
				check(key+"_no_pending_tuning_applied",not beach.configuration.environment.get("coupling_parameters",{}).has("erosion_rate_per_s"))
				await _ticks(2)
				if key=="test1_geometry":
					for id in ["boundary_mean_level_m","boundary_amplitude_m","boundary_period_s"]:check("geometry_available_"+id,service.describe(id).available)
					for id in ["boundary_omega_rad_s","boundary_phase_rad"]:check("geometry_unused_"+id,not service.describe(id).available)
			check("main_visual_restored",beach.get_node("GpuWaterSurface").material_override.get_shader_parameter("rdc_normal_gain")==.6)
			check("main_pending_restored",service.editing.erosion_rate_per_s==.45)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join("game.png"))
		service.open_window("water");await process_frame;await RenderingServer.frame_post_draw
		service.get_node("water").get_texture().get_image().save_png(output.path_join("water.png"))
	await beach.shutdown();check("released",beach.gpu_release_done)
	beach.queue_free();await process_frame
	var passed:=checks.all(func(item):return item.pass)
	FileAccess.open(output.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"pass":passed,"checks":checks},"\t"))
	quit(0 if passed else 1)

func _edit(tool: StringName) -> void:
	beach._on_tool_changed(tool)
	var admitted: Dictionary=beach.input.begin(tool,Vector2(-2,0),beach.tool_parameters(),.1,beach.water_policy,beach.signed_speed_m_s)
	beach.input.finish()
	check(String(tool)+"_admitted",admitted.get("accepted",false),String(admitted.get("error",&"")))
	if not admitted.get("accepted",false):return
	var deadline:=Time.get_ticks_msec()+15000
	var result: Dictionary={}
	while result.is_empty() and Time.get_ticks_msec()<deadline:
		for terminal in beach.input.terminal:
			if terminal.command_id==admitted.command_id:result=terminal
		await process_frame
	check(String(tool)+"_gpu_result",not result.is_empty() and result.get("outcome",0) in [1,2],result.get("error_code",-1))
	if tool in [&"place_sand",&"remove_sand"]:
		check(String(tool)+"_strength_volume",absf(float(result.get("added_m3" if tool==&"place_sand" else "removed_m3",0.0))-.05)<.0001,result.get("added_m3" if tool==&"place_sand" else "removed_m3"))

func _ticks(count: int) -> void:
	var target: int=beach.runtime.current.completed_tick+count
	var deadline:=Time.get_ticks_msec()+45000
	beach.playing=true
	while beach.runtime.current.completed_tick<target and beach.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	beach.playing=false
	check(beach.scene_key+"_ticks_advance",beach.runtime.current.completed_tick>=target and beach.last_error.is_empty(),String(beach.last_error))
	while (beach.runtime.current.pending_count()>0 or beach.runtime.current.active_count()>0) and Time.get_ticks_msec()<deadline:await process_frame

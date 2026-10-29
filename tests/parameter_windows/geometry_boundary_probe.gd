extends "res://tests/integration/unified_edit_playable_probe.gd"

const Boundary=preload("res://scripts/simulation/unified_edit/boundary.gd")
const VALUES={"boundary_mean_level_m":1.0,"boundary_amplitude_m":0.25,"boundary_period_s":12.0}

func _wait_ready() -> bool:
	var deadline:=Time.get_ticks_msec()+90000
	while (scene._booting or not scene.ready_for_ticks) and scene.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	# Rows refresh on the parameter service's next busy-to-ready notification.
	for frame in 3:await process_frame
	check("ready_"+scene.scene_key,not scene._booting and scene.ready_for_ticks and scene.last_error.is_empty())
	return not scene._booting and scene.ready_for_ticks and scene.last_error.is_empty()

func _switch(key: String) -> bool:
	var hub=root.get_node("BeachScenes")
	check("switch_admitted_"+key,hub.request_switch(key))
	var deadline:=Time.get_ticks_msec()+180000
	while hub.busy and Time.get_ticks_msec()<deadline:await process_frame
	scene=hub.active_scene
	check("switch_settled_"+key,not hub.busy and hub.last_error.is_empty() and scene!=null and scene.scene_key==key)
	if not hub.last_error.is_empty():print("BOUNDARY_SWITCH_ERROR ",hub.last_error)
	return scene!=null and scene.scene_key==key and await _wait_ready()

func _run() -> void:
	orphan_baseline=int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	DisplayServer.window_set_size(Vector2i(1280,720))
	var restart: bool="--restart" in OS.get_cmdline_user_args()
	scene=load("res://scenes/playable/test1_geometry.tscn").instantiate();scene.playing=false;root.add_child(scene);current_scene=scene
	if not await _wait_ready():observations.error=String(scene.last_error);await _close();return
	var parameters=root.get_node("Parameters")
	for id in VALUES:
		var description: Dictionary=parameters.describe(id)
		var editor=parameters.get_node("water/Margin/Rows/Scroll/Fields/"+id+"/Line/Value")
		check("editable_"+id,description.available and editor.editable)
		check("restart_status_"+id,description.status.begins_with("需重建／重启"))
	for id in ["boundary_omega_rad_s","boundary_phase_rad"]:
		check("unused_"+id,not parameters.describe(id).available and parameters.describe(id).status=="当前水边界模式不使用此参数")
		check("unused_rejected_"+id,parameters.set_value(id,0.2)==&"parameter_unavailable")
	check("range_rejected",parameters.set_value("boundary_amplitude_m",0.61)==&"invalid_parameter")
	var frozen: Dictionary=scene.configuration.environment.boundary.duplicate(true)
	if not restart:
		check("default_boundary",frozen==Boundary.for_scene("test1_geometry"))
		for id in VALUES:
			var editor=parameters.get_node("water/Margin/Rows/Scroll/Fields/"+id+"/Line/Value")
			editor.value=VALUES[id]
			check("ui_staged_"+id,parameters.editing[id]==VALUES[id] and parameters.effective[id]==frozen[parameters.Schema.rows()[id].field])
		parameters.save_parameters()
		var saved: Dictionary=parameters.read_file(parameters._file_path)
		check("saved_file_valid",saved.error.is_empty())
		for id in VALUES:check("saved_"+id,saved.scenes.test1_geometry[id]==VALUES[id] and parameters.describe(id).status.contains("待重启生效（已保存）"))
		check("save_does_not_apply",scene.configuration.environment.boundary==frozen)
		parameters.reset_defaults("water")
		for id in VALUES:check("scene_default_"+id,parameters.editing[id]==frozen[parameters.Schema.rows()[id].field])
		parameters.load_parameters()
		for id in VALUES:check("loaded_pending_"+id,parameters.editing[id]==VALUES[id] and parameters.effective[id]!=VALUES[id])
	else:
		for id in VALUES:check("restart_consumed_"+id,frozen[parameters.Schema.rows()[id].field]==VALUES[id] and parameters.effective[id]==VALUES[id])
		var push: PackedByteArray=scene.runtime.current.visuals.water.boundary_push_constants()
		check("actual_gpu_push",is_equal_approx(push.decode_float(4),1.0) and is_equal_approx(push.decode_float(8),0.25) and is_equal_approx(push.decode_float(28),12.0))
		check("drainage_preserved",frozen.overflow==Boundary.for_scene("test1_geometry").overflow)
		for field in ["omega_rad_s","phase_rad","period_s","amplitude_m","domain_id","overflow"]:
			var bad:=frozen.duplicate(true);var domain:="test1_geometry"
			match field:
				"domain_id":domain="main_beach"
				"overflow":bad.overflow.drain_rate_m_s=0.15
				"period_s":bad.period_s=0.0
				"amplitude_m":bad.amplitude_m=0.61
				_:bad[field]=0.2
			check("invalid_config_"+field,not Boundary.configuration_error({"domain_id":domain,"environment":{"boundary":bad}}).is_empty())
		var boot: Dictionary={};var environment:={"boundary":frozen.duplicate(true)};var simulation: Dictionary={}
		var original_boot: Dictionary=scene.get_meta("parameter_boot_values",{}).duplicate(true)
		scene.set_meta("parameter_boot_values",{"boundary_phase_rad":1.0})
		check("unused_boot_rejected",parameters.prepare_boot(scene,boot,environment,simulation)==&"boundary_field_not_used_by_mode")
		scene.set_meta("parameter_boot_values",original_boot)
		scene.playing=true;var deadline:=Time.get_ticks_msec()+30000
		while scene.runtime.current.completed_tick<3 and scene.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
		scene.playing=false;await _idle()
		check("custom_boundary_runs",scene.runtime.current.completed_tick>=3 and scene.last_error.is_empty())
		var path:=output+"/custom.sandue"
		check("save_custom",(await scene.save_gpu_checkpoint(path)).is_empty())
		var snapshot:=Codec.load(path,scene.configuration)
		check("custom_boundary_gpu_level",snapshot.error.is_empty() and is_equal_approx(snapshot.checkpoint.native.control.decode_float(96),1.0))
		check("restore_custom",(await scene.restore_gpu_checkpoint(path)).is_empty())
		if not await _wait_ready():await _close();return
	observations.boundary=frozen;observations.sources=scene.configuration.sources.duplicate(true)
	var hub=root.get_node("BeachScenes");hub.session_directory=output+"/sessions";DirAccess.make_dir_recursive_absolute(hub.session_directory)
	if await _switch("main"):
		check("main_boundary_available",parameters.describe("boundary_mean_level_m").available and parameters.describe("boundary_omega_rad_s").available)
		check("main_period_unused",not parameters.describe("boundary_period_s").available)
		if await _switch("test1_geometry"):
			check("switch_preserves_effective_boundary",scene.configuration.environment.boundary==frozen)
			for id in VALUES:check("switch_keeps_editor_"+id,parameters.editing[id]==VALUES[id])
	parameters.open_window("water")
	for frame in 5:await process_frame;await RenderingServer.frame_post_draw
	check("water_window_capture",parameters.get_node("water").get_texture().get_image().save_png(output+"/water.png")==OK)
	parameters.get_node("water").hide()
	await _close()

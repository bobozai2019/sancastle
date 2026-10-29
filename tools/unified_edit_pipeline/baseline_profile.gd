extends "res://tools/gpu_optimization/profile.gd"

# Isolated G0 observer: no source substitutions or authority algorithm changes.

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):output=argument.trim_prefix("--output=")
		if argument.begins_with("--case="):case_id=argument.trim_prefix("--case=")
		if argument=="--sampling":sampling_enabled=true
		if argument=="--wet":wet_target=true
	call_deferred("_run")

func _configured(error: String) -> void:
	check("recorder_configured",error.is_empty())
	hardware.fixture_commands=[]
	hardware.fixture_results=[]
	hardware.initial_state={}
	hardware.camera_transform=str(preview.player_camera.global_transform)
	hardware.initial_tick=preview.completed_ticks
	hardware.initial_time=preview.async_controller.actual_time
	hardware.scope="paused sequential 20-command exploratory baseline; no first-visible/collision latency claim"
	check("visible_d3d12",DisplayServer.get_name()!="headless" and root.visible and RenderingServer.get_current_rendering_driver_name()=="d3d12")
	for field in ["rock","obstacle","sand","water","sediment","momentum_x","momentum_z","wetness","compaction","mold_support","clock"]:
		var bytes: PackedByteArray=await read(field)
		var path: String=output.get_basename()+"_initial_"+field+".bin"
		var file:=FileAccess.open(path,FileAccess.WRITE)
		check("initial_write_"+field,file!=null)
		if file!=null:file.store_buffer(bytes);file.close()
		hardware.initial_state[field]={"path":path,"sha256":digest(bytes),"bytes":bytes.size()}
	if error.is_empty() and case_id in ["wall","shovel"]:
		check("shape_begin",(await preview.begin_shape_stroke(7001)).is_empty())
	configure_done=true

func idle() -> bool:
	var settled: bool=await super.idle()
	if settled and not preview.input_scheduler.terminal.is_empty():
		var row: Dictionary=preview.input_scheduler.terminal.back()
		hardware.fixture_results.append(row.duplicate(true))
		if case_id in ["wall","shovel"]:
			check("shape_terminal_%d"%hardware.fixture_results.size(),row.result.get("gpu_complete",false) and row.result.get("status",0) in [1,2])
	return settled

func command(index: int, point: Vector3=Vector3(-2,0,0), fill: bool=true) -> Dictionary:
	if case_id not in ["wall","shovel"]:
		var ordinary_value: Dictionary=super.command(index,point,fill)
		hardware.fixture_commands.append(ordinary_value.duplicate(true))
		return ordinary_value
	var params: Dictionary={"height_m":0.2,"bottom_width_m":1.0,"top_width_m":0.5} if case_id=="wall" else {"trench_width_m":0.5,"depth_m":0.05,"shoulder_width_m":0.5}
	var a:=Vector2(point.x,point.z)+Vector2(0,float(index)*0.1)
	var b:=a+Vector2(0,0.25)
	var value:=Brush.make_command(StringName(case_id+"_v1"),params,a,b,preview.domain.domain_id,preview.generation,preview.command_queue.last_command_id+1,7001,index,preview.completed_ticks,preview.shape_baseline_token)
	value.material_profile_id=&"plain_sand_v1" if case_id=="shovel" else &"molded_v1"
	hardware.fixture_commands.append(value.duplicate(true))
	return value

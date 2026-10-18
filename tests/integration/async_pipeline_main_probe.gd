extends SceneTree

const Brush=preload("res://scripts/simulation/brushes/brush_protocol.gd")

var preview
var output:=""
var scene_path:="res://scenes/main.tscn"
var checks:=[]
var failed:=false
var read_data:=PackedByteArray()
var read_done:=false
var hardware:={}
var tools_enabled:=false
var ui_enabled:=false
var witnesses:={}

func digest(bytes: PackedByteArray) -> String:
	var hash:=HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	return hash.finish().hex_encode()

func loaded_code() -> Dictionary:
	var result:={}
	for object in [preview,preview.solver,preview.async_controller,preview.async_controller.water,preview.async_controller.coupled,preview.async_controller.visuals,preview.async_controller.collision,preview.solver.async_transport,preview.async_controller.slots]:
		var script: Script=object.get_script()
		while script!=null:
			if script is GDScript:result[script.resource_path]=script.source_code.sha256_text()
			script=script.get_base_script()
	return result

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
		if arg.begins_with("--scene="):scene_path=arg.trim_prefix("--scene=")
		if arg=="--tools":tools_enabled=true
		if arg=="--ui":ui_enabled=true
	call_deferred("_run")

func check(label: String, value: bool) -> void:
	checks.append({"name":label,"pass":value})
	failed=failed or not value
	print("ASYNC_MAIN ",label," ",value)

func command(index: int, point: Vector3=Vector3(-2,0,0), fill: bool=true) -> Dictionary:
	return {"domain_id":preview.domain.domain_id,"generation":preview.generation,"sim_tick":preview.completed_ticks,"command_id":preview.command_queue.last_command_id+1,"kind":&"place_sand" if fill else &"remove_sand","shape":&"circle","transform":{"position_m":point},"radius_m":0.3,"strength":1.0,"amount_m3":0.015,"seed":101+index}

func idle() -> bool:
	var deadline:=Time.get_ticks_msec()+30000
	while Time.get_ticks_msec()<deadline and preview.last_error.is_empty():
		if preview.command_queue.pending.is_empty() and preview.async_controller.idle(true) and not preview.input_scheduler.pumping and not preview.input_running:return true
		await process_frame
	return false

func read(field: String) -> PackedByteArray:
	read_done=false
	RenderingServer.call_on_render_thread(_read_render.bind(field))
	var deadline:=Time.get_ticks_msec()+15000
	while not read_done and Time.get_ticks_msec()<deadline:await process_frame
	check("read_"+field,read_done)
	return read_data.duplicate()

func _read_render(field: String) -> void:
	var rd: RenderingDevice=preview.solver.rd
	if field=="clock":rd.texture_get_data_async(preview.solver.async_transport.clock_texture,0,_read_arrived)
	elif field=="published_sand":rd.texture_get_data_async(preview.solver.published_sand,0,_read_arrived)
	else:rd.texture_get_data_async(preview.solver.current_texture(field),0,_read_arrived)

func _read_arrived(bytes: PackedByteArray) -> void:
	call_deferred("_read_store",bytes)

func _read_store(bytes: PackedByteArray) -> void:
	read_data=bytes
	read_done=true

func _inject_rejection() -> void:
	preview.solver.inject_water_loss_once=true

func total_sand() -> float:
	var total:=0.0
	for field in ["sand","sediment"]:
		var bytes: PackedByteArray=await read(field)
		for value in bytes.to_float32_array():total+=value*0.015625
	return total

func ui_and_capacity() -> void:
	var before: int=preview.input_events.size()
	var camera: Camera3D=preview.player_camera
	var panel: Control=preview.get_node("Interface/EditPanel")
	var button:=InputEventMouseButton.new()
	button.position=panel.get_global_rect().position+Vector2(10,10)
	button.button_index=MOUSE_BUTTON_LEFT
	button.pressed=true
	Input.parse_input_event(button.duplicate())
	await process_frame
	button.pressed=false
	Input.parse_input_event(button.duplicate())
	await process_frame
	check("gui_click_not_admitted",preview.input_events.size()==before)
	var screen:=Vector2.ZERO
	var hit: Dictionary={}
	for y in range(300,650,40):
		for x in range(200,900,40):
			var candidate: Dictionary=preview.pick(Vector2(x,y))
			if not candidate.is_empty() and preview._pick_current(candidate,true):screen=Vector2(x,y);hit=candidate;break
		if not hit.is_empty():break
	check("real_screen_collision_pick",not hit.is_empty())
	if not hit.is_empty():
		preview.brush_panel._on_tool_pressed(&"place_sand")
		button.position=screen
		button.pressed=true
		preview._unhandled_input(button)
		button.pressed=false
		preview._input(button)
		check("real_mouse_edit_drains",await idle())
		check("real_mouse_edit_admitted",preview.input_events.size()==before+1 and preview.gpu_brush.is_empty())
	var transform:=camera.transform
	root.gui_release_focus()
	var key:=InputEventKey.new()
	key.keycode=KEY_W
	key.physical_keycode=KEY_W
	key.pressed=true
	Input.parse_input_event(key.duplicate())
	await process_frame
	await process_frame
	key.pressed=false
	Input.parse_input_event(key.duplicate())
	check("camera_wasd_preserved",camera.position.distance_to(transform.origin)>0.001)
	var dig: SpinBox=preview.brush_panel.get_node("%DigAmount")
	check("numeric_focus_fixture_visible",dig.is_visible_in_tree())
	dig.get_line_edit().grab_focus()
	var position:=camera.position
	key.pressed=true
	Input.parse_input_event(key.duplicate())
	await process_frame
	await process_frame
	key.pressed=false
	Input.parse_input_event(key.duplicate())
	check("numeric_focus_blocks_camera",camera.position==position)
	root.gui_release_focus()
	before=preview.input_events.size()
	var right:=InputEventMouseButton.new()
	right.button_index=MOUSE_BUTTON_RIGHT
	right.pressed=true
	camera._unhandled_input(right)
	button.pressed=true
	preview._unhandled_input(button)
	right.pressed=false
	camera._input(right)
	check("camera_look_not_edit",preview.input_events.size()==before and not camera.look_active and preview.gpu_brush.is_empty())
	camera.transform=transform
	var invalid:=command(900)
	invalid.radius_m=NAN
	check("invalid_input_distinct",preview.input_scheduler.submit(invalid)==&"invalid_input")
	for index in 64:check("bounded_enqueue_%d"%index,preview.input_scheduler.submit(command(901+index)).is_empty())
	preview.gpu_brush=&"place_sand"
	check("queue_full_distinct",preview.input_scheduler.submit(command(1000))==&"queue_full")
	check("queue_full_mouse_rejected",not preview._submit_gpu_input(&"place_sand",Vector3.ZERO,Vector3(1,0,0),&"swept_segment",0.01) and preview.gpu_brush.is_empty())
	preview.gpu_brush=&"place_sand"
	button.pressed=false
	preview._input(button)
	check("release_survives_full_queue",preview.gpu_brush.is_empty() and preview.command_queue.pending.size()==64)
	check("capacity_recovers",await idle())

func tools() -> void:
	var clock: PackedByteArray=await read("clock")
	check("shape_boundary_begin",(await preview.begin_shape_stroke(701)).is_empty())
	var brush:=Brush.make_command(&"wall_v1",{"height_m":0.2,"bottom_width_m":1.0,"top_width_m":0.5},Vector2(-2,-0.25),Vector2(-2,0.25),preview.domain.domain_id,preview.generation,preview.command_queue.last_command_id+1,701,0,preview.completed_ticks,preview.shape_baseline_token)
	brush.material_profile_id=&"molded_v1"
	var shape_result: Dictionary=await preview.apply_gpu_command(brush)
	check("shape_result",shape_result.get("status")==1 and shape_result.get("gpu_complete",false))
	check("shape_boundary_end",(await preview.end_shape_stroke()).is_empty())
	check("shape_returns_to_pipeline",await idle() and not preview.async_controller.legacy and not preview.async_controller.transitioning and preview.solver.mold_field_ever_used)
	var stock: float=preview.domain.tool_inventory_m3
	var mass: float=await total_sand()
	check("shovel_boundary_begin",(await preview.begin_shape_stroke(702)).is_empty())
	var shovel:=Brush.make_command(&"shovel_v1",{"trench_width_m":0.5,"depth_m":0.05,"shoulder_width_m":0.5},Vector2(-1,-0.25),Vector2(-1,0.25),preview.domain.domain_id,preview.generation,preview.command_queue.last_command_id+1,702,0,preview.completed_ticks,preview.shape_baseline_token)
	var shovel_result: Dictionary=await preview.apply_gpu_command(shovel)
	check("shovel_result",shovel_result.get("status")==1 and shovel_result.get("gpu_complete",false))
	check("shovel_boundary_end",(await preview.end_shape_stroke()).is_empty())
	check("shovel_mass_and_stock",await idle() and absf((await total_sand())-mass)<0.00001 and preview.domain.tool_inventory_m3==stock)
	var cpu:=command(500,Vector3(-2,0,0))
	cpu.kind=&"compact"
	cpu.strength=0.25
	var compact: Dictionary=await preview.apply_legacy_command(cpu)
	check("legacy_compact",compact.get("results",[]).size()==1 and preview.last_error.is_empty())
	check("compact_returns_to_pipeline",await idle() and not preview.async_controller.legacy)
	var suspended:=command(501,Vector3(-8,0,0))
	suspended.sand_destination="suspended_v1"
	var accepted_before: int=preview.async_controller.accepted_commands
	check("suspended_admission",preview.input_scheduler.submit(suspended).is_empty())
	check("suspended_drain",await idle())
	check("suspended_pipeline_result",preview.input_scheduler.terminal[-1].result.get("gpu_complete",false) and preview.async_controller.accepted_commands==accepted_before+1)
	var drop: Dictionary=await preview.drop_gravel(Vector2(1,1),2)
	check("gravel_boundary_preserved",drop.get("ok",false) and drop.active_count==514)
	check("gravel_returns_to_pipeline",await idle() and not preview.async_controller.legacy)
	check("tool_bridge_clock_unchanged",clock==await read("clock"))
	var count: int=preview.async_controller.accepted_commands
	check("ordinary_after_tools",preview.input_scheduler.submit(command(502)).is_empty())
	check("ordinary_after_tools_drain",await idle() and preview.async_controller.accepted_commands==count+1)
	check("no_legacy_prefix_retained",preview.gpu_prefix.is_empty())

func _run() -> void:
	preview=load(scene_path).instantiate()
	preview.async_pipeline_enabled=true
	preview.playing=false
	root.add_child(preview)
	var deadline:=Time.get_ticks_msec()+60000
	while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	check("candidate_main_ready",preview.ready_for_ticks and preview.last_error.is_empty() and preview.async_backend_ready)
	hardware={"engine":Engine.get_version_info(),"adapter":RenderingServer.get_video_adapter_name(),"driver":RenderingServer.get_current_rendering_driver_name(),"window":DisplayServer.window_get_size(),"profile":preview._runtime_configuration_signature(),"water_shader":preview.water_material.shader.resource_path,"terrain_shader":preview.terrain_material.shader.resource_path,"loaded_gdscript_sha256":loaded_code()}
	if not failed:
		var before: PackedByteArray=await read("sand")
		preview.async_controller.hold_completions=true
		preview.async_controller.hold_collision=true
		for index in 8:check("enqueue_%d"%index,preview.input_scheduler.submit(command(index,Vector3(-2,0,float(index%2)*0.5),index%2==0)).is_empty())
		deadline=Time.get_ticks_msec()+30000
		while preview.async_controller.submitted_edits<3 and Time.get_ticks_msec()<deadline:await process_frame
		check("three_real_batches_before_cpu_consume",preview.async_controller.submitted_edits==3 and preview.async_controller.slots.active_count()==3 and preview.async_controller.events.filter(func(e):return e.event=="cpu_consume").is_empty())
		check("bounded_remaining_queue",preview.command_queue.pending.size()==2)
		var edited: PackedByteArray=await read("sand")
		check("gpu_sand_visible_without_cpu_ack",edited!=before and preview.async_controller.accepted_commands==0)
		check("published_sand_is_complete_without_cpu_ack",edited==await read("published_sand"))
		check("active_materials_bind_published_sand",preview.water_material.get_shader_parameter("sand_state")==preview.sand_texture and preview.terrain_material.get_shader_parameter("sand_state")==preview.sand_texture and preview.sand_texture.texture_rd_rid==preview.solver.published_sand)
		witnesses.overlap={"events":preview.async_controller.events.duplicate(true),"in_flight":preview.async_controller.slots.active_count(),"pending_count":preview.command_queue.pending.size(),"cpu_accepted":preview.async_controller.accepted_commands,"sand_before_sha256":digest(before),"sand_after_sha256":digest(edited)}
		preview.async_controller.hold_completions=false
		preview.async_controller.hold_collision=false
		check("paused_edits_drain",await idle())
		check("gpu_edit_counters",preview.async_controller.accepted_commands==8 and preview.async_controller.rejected_commands==0)
		check("ordinary_prefix_not_retained",preview.gpu_prefix.is_empty() and preview.command_queue.applied_log.is_empty())
		var frames:={}
		var at_most_one:=true
		for e in preview.async_controller.events:
			if e.event=="submit" and e.kind=="edit":
				if frames.has(e.frame_id):at_most_one=false
				frames[e.frame_id]=true
		check("at_most_one_edit_upload_each_frame",at_most_one)
		var clock: PackedByteArray=await read("clock")
		check("paused_actual_clock_zero",clock.decode_float(0)==0.0 and preview.completed_ticks==0)
		preview._start_tick()
		deadline=Time.get_ticks_msec()+30000
		while preview.completed_ticks==0 and Time.get_ticks_msec()<deadline:await process_frame
		check("explicit_paused_step_preserved",preview.completed_ticks==1 and await idle())
		for frame in 5:await process_frame
		check("pause_has_no_automatic_tick",preview.completed_ticks==1)
		var wet:=Vector3.ZERO
		var found:=false
		for index in 65536:
			if preview.shadow_domain.water[index]>0.05 and index%256>10 and index%256<245:
				wet=Vector3((index%256+0.5)*0.125-16,0,(index/256+0.5)*0.125-16)
				found=true
				break
		check("wet_rejection_fixture",found)
		var old_source: float=preview.domain.sand_source_m3
		var unchanged: PackedByteArray=await read("sand")
		RenderingServer.call_on_render_thread(_inject_rejection)
		check("rejected_input_admitted",preview.input_scheduler.submit(command(9,wet)).is_empty())
		check("rejected_input_drain",await idle())
		check("gpu_skip_distinguished",preview.async_controller.rejected_commands==1 and preview.async_controller.accepted_commands==8)
		check("skip_keeps_nominal_estimate",absf(preview.domain.sand_source_m3-old_source-0.015)<1e-8 and preview.ledger_precision=="approximate")
		check("skip_preserves_sand",unchanged==await read("sand"))
		preview.domain.sand_source_m3+=10.0
		preview.playing=true
		var admitted:=0
		deadline=Time.get_ticks_msec()+30000
		while preview.completed_ticks<5 and Time.get_ticks_msec()<deadline and preview.last_error.is_empty():
			if preview.command_queue.pending.size()<32:
				if preview.input_scheduler.submit(command(20+admitted,Vector3(-2,0,0),admitted%2==0)).is_empty():admitted+=1
			await process_frame
		preview.playing=false
		check("continuous_edit_water_progress",preview.completed_ticks>=5 and admitted>0 and preview.async_controller.submitted_water>=5)
		check("live_edits_stop_and_drain",await idle())
		witnesses.continuous={"events":preview.async_controller.events.duplicate(true),"sim_tick":preview.completed_ticks,"submitted_water":preview.async_controller.submitted_water,"submitted_edits":preview.async_controller.submitted_edits,"admitted":admitted,"state_seq":preview.async_controller.state_seq,"actual_time":preview.async_controller.actual_time}
		clock=await read("clock")
		check("gpu_actual_clock_matches_completion",clock.size()==4 and clock.decode_float(0)==preview.async_controller.actual_time and preview.visual_time_s==preview.async_controller.actual_time)
		check("material_uses_gpu_clock",preview.water_material.get_shader_parameter("use_async_clock")==true and preview.terrain_material.get_shader_parameter("use_async_clock")==true)
		check("active_shaders_declare_gpu_clock",preview.water_material.shader.get_shader_uniform_list().any(func(u):return u.name=="async_clock") and preview.terrain_material.shader.get_shader_uniform_list().any(func(u):return u.name=="async_clock"))
		check("bounded_histories",preview.gpu_prefix.is_empty() and preview.async_controller.events.size()<=128 and preview.input_scheduler.terminal.size()<=128)
		check("approximate_drift_does_not_stop",preview.last_error.is_empty() and preview.domain.sand_source_m3>=10.0)
		if tools_enabled and preview.last_error.is_empty():await tools()
		if ui_enabled and preview.last_error.is_empty():await ui_and_capacity()
	check("no_runtime_failure",preview.last_error.is_empty())
	var events: Array=preview.async_controller.events.duplicate(true) if preview.async_controller!=null else []
	await preview.shutdown()
	check("main_resources_released",preview.gpu_release_done and preview.solver.rd==null and preview.async_controller.water.rd==null and preview.async_controller.collision.rd==null)
	preview.queue_free()
	await process_frame
	var arguments:=OS.get_cmdline_args()
	var log_index:=arguments.find("--log-file")
	var runtime_log:=arguments[log_index+1] if log_index>=0 and log_index+1<arguments.size() else output.get_basename()+".log"
	if not output.is_empty():
		check("runtime_log_available",FileAccess.file_exists(runtime_log))
		var log_text:=FileAccess.get_file_as_string(runtime_log)
		check("no_engine_script_errors",not log_text.contains("SCRIPT ERROR:") and not log_text.contains("\nERROR:"))
	if not output.is_empty():
		var file:=FileAccess.open(output,FileAccess.WRITE)
		if file!=null:file.store_string(JSON.stringify({"pass":not failed,"checks":checks,"events":events,"witnesses":witnesses,"runtime":hardware},"\t"))
	quit(1 if failed else 0)

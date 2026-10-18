extends "res://tests/integration/unified_edit_playable_probe.gd"

const Presentation=preload("res://scripts/simulation/unified_edit/presentation.gd")
const Brush=preload("res://scripts/simulation/brushes/brush_protocol.gd")
const Observer=preload("res://tests/integration/unified_edit_cost_executor_proxy.gd")
var case_id:="fill"
var sampling:=false
var device: RenderingDevice
var observer
var configured:=false
var pending_read:=false
var read_bytes:=PackedByteArray()
var read_done:=false
var collecting:=false
var seen_capture:=-1
var gpu_samples: Array=[]
var frames: Array=[]
var terminals: Array=[]
var submitted: Array=[]
var outstanding: Dictionary={}
var start_point:=Vector2.ZERO
var target_witness: Dictionary={}
var hardware: Dictionary={}
var startup: Dictionary={}
var input_window: Dictionary={}
var previous_us:=0

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
		if arg.begins_with("--case="):case_id=arg.trim_prefix("--case=")
		if arg=="--sampling":sampling=true
	call_deferred("_run")

func _target(domain) -> bool:
	var best:=Vector2i(-1,-1);var best_score:=-INF
	for z in range(40,217,16):
		for x in range(32,225,16):
			var minimum:=INF;var maximum:=-INF;var min_sand:=INF;var obstruction:=false
			for dz in range(-20,21):
				for dx in range(-16,17):
					var i: int=(z+dz)*256+x+dx
					minimum=minf(minimum,domain.water[i]);maximum=maxf(maximum,domain.water[i]);min_sand=minf(min_sand,domain.sand[i]);obstruction=obstruction or domain.obstacle[i]!=0
			if maximum<=0.001 and not obstruction and min_sand>0.05 and min_sand>best_score:
				best=Vector2i(x,z);best_score=min_sand;target_witness={"cell":best,"water_min_m":minimum,"water_max_m":maximum,"sand_min_m":min_sand,"obstacle":obstruction,"checked_cell_rect":Rect2i(x-16,z-20,33,41)}
	if best.x<0:return false
	start_point=Vector2((best.x+.5)*.125-16,(best.y+.5)*.125-16);return true

func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1280,720));DisplayServer.window_set_title("Unified G8 current cost "+case_id)
	orphan_baseline=int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var boot:=Time.get_ticks_usec()
	scene=load("res://scenes/main.tscn").instantiate();scene.playing=false;root.add_child(scene)
	while not scene.ready_for_ticks and scene.last_error.is_empty() and Time.get_ticks_usec()-boot<180000000:await process_frame
	check("entry_ready",scene.ready_for_ticks and scene.last_error.is_empty())
	if not scene.ready_for_ticks:finish();return
	startup={"load_to_ready_us":Time.get_ticks_usec()-boot,"warmup_frames":30}
	observations.sources=scene.configuration.sources.duplicate(true)
	var data:=Presentation.read(scene.presentation_manifest);var initial:=Presentation.initial_domain(data.metadata,scene.generation)
	check("fixed_full_footprint_target",_target(initial.domain))
	check("known_cost_case",case_id in ["dig","fill","wall","shovel"])
	RenderingServer.call_on_render_thread(_configure_render)
	while not configured:await process_frame
	hardware={"engine":Engine.get_version_info(),"adapter":RenderingServer.get_video_adapter_name(),"driver":RenderingServer.get_current_rendering_driver_name(),"window":DisplayServer.window_get_size(),"viewport":root.get_visible_rect().size,"vsync":DisplayServer.window_get_vsync_mode(),"camera_transform":str(scene.player_camera.global_transform),"configuration":scene.configuration.duplicate(true),"diagnostic_override":sampling,"initial_state":{}}
	hardware.presentation_settings=data.metadata.settings.duplicate(true)
	hardware.presentation_effective_profile=data.metadata.effective_profile.duplicate(true)
	hardware.presentation_compilation=data.metadata.effective_compilation.duplicate(true)
	hardware.presentation_materials=data.metadata.materials.duplicate(true)
	check("visible_d3d12_full_window",DisplayServer.get_name()!="headless" and root.visible and hardware.driver=="d3d12" and DisplayServer.window_get_size()==Vector2i(1280,720))
	for field in ["rock","obstacle","sand","water","sediment","momentum_x","momentum_z","wetness","compaction","mold_support","clock"]:
		var bytes:=await _read(field);var path: String=output.get_basename()+"_initial_"+field+".bin";FileAccess.open(path,FileAccess.WRITE).store_buffer(bytes)
		hardware.initial_state[field]={"path":path,"sha256":FileAccess.get_sha256(path),"bytes":bytes.size()}
	var owner=scene.runtime.current
	if case_id in ["wall","shovel"]:check("common_begin",owner.submit_control("begin",_control(owner.command_highwater()+1)).accepted)
	await _settle()
	for i in 30:await process_frame
	process_frame.connect(_observe)
	var start_us:=Time.get_ticks_usec()
	for i in 24:
		var command:=_fixture(i)
		var before:=Time.get_ticks_usec();var result: Dictionary=owner.submit_legacy(command,scene.water_policy,scene.signed_speed_m_s)
		check("admission_"+str(i),result.accepted)
		outstanding[command.command_id]=before
		submitted.append({"command":command.duplicate(true),"admitted_at_us":before,"admission_return_us":Time.get_ticks_usec(),"index":i})
		await process_frame
	input_window={"start_at_us":start_us,"end_at_us":Time.get_ticks_usec(),"start_tick":0,"end_tick":owner.completed_tick,"start_time_s":0.0,"end_time_s":owner.advanced_time_s}
	if case_id in ["wall","shovel"]:check("common_end",owner.submit_control("end",_control(owner.command_highwater()+1)).accepted)
	var tail_start:=Time.get_ticks_usec();await _settle();_observe()
	observations.tail_us=Time.get_ticks_usec()-tail_start
	check("all_24_real_terminals",submitted.size()==24 and terminals.size()==24 and outstanding.is_empty())
	var final_fields: Dictionary={}
	process_frame.disconnect(_observe)
	while collecting:await process_frame
	for field in ["sand","water","sediment","momentum_x","momentum_z","wetness","compaction","mold_support","clock"]:
		var bytes:=await _read(field);var path: String=output.get_basename()+"_final_"+field+".bin";FileAccess.open(path,FileAccess.WRITE).store_buffer(bytes);final_fields[field]={"path":path,"sha256":FileAccess.get_sha256(path),"bytes":bytes.size()}
	observations.final_fields=final_fields;observations.completed_state_seq=owner.completed_state_seq
	observations.height_versions=owner.heights.applied_state_seq.duplicate(true)
	observations.cpu_records=observer.cpu_records.duplicate(true) if sampling else []
	await scene.shutdown();check("entry_released",scene.unified_release_complete())
	var service=root.get_node("BeachScenes")
	if service.active_scene==scene:service.active_scene=null
	root.remove_child(scene);scene.free();scene=null;await process_frame
	finish()

func _configure_render() -> void:
	var owner=scene.runtime.current;device=owner.state.rd
	if sampling:
		observer=Observer.new();observer.adopt(owner.executor);owner.executor=observer
	owner.state.profile_passes=sampling
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),sampling)
	call_deferred("_configured")
func _configured() -> void:configured=true

func _control(id: int) -> Dictionary:return {"domain_id":scene._domain_id(),"generation":scene.generation,"command_id":id,"sim_tick":0,"stroke_id":7001,"baseline_token":7001}
func _path(index: int) -> Vector2:return start_point+Vector2(0,-1.0+2.0*float(index)/23.0)
func _fixture(index: int) -> Dictionary:
	var owner=scene.runtime.current;var a:=_path(index)
	if case_id in ["dig","fill"]:return {"domain_id":scene._domain_id(),"generation":scene.generation,"sim_tick":0,"command_id":owner.command_highwater()+1,"kind":&"place_sand" if case_id=="fill" else &"remove_sand","shape":&"circle","transform":{"position_m":Vector3(a.x,0,a.y)},"radius_m":0.3,"strength":1.0,"amount_m3":0.015,"seed":101+index}
	var params: Dictionary={"height_m":0.2,"bottom_width_m":1.0,"top_width_m":0.5} if case_id=="wall" else {"trench_width_m":0.5,"depth_m":0.05,"shoulder_width_m":0.5}
	var value:=Brush.make_command(StringName(case_id+"_v1"),params,a,_path(mini(index+1,23)),scene._domain_id(),scene.generation,owner.command_highwater()+1,7001,index,0,7001)
	value.material_profile_id=&"plain_sand_v1" if case_id=="shovel" else &"molded_v1";return value

func _settle() -> void:
	var owner=scene.runtime.current;var start:=Time.get_ticks_msec()
	while (owner.pending_count()!=0 or owner.active_count()!=0 or owner.heights.active_count()!=0 or owner.heights.hinted) and Time.get_ticks_msec()-start<30000:await process_frame
	check("complete_and_collision_idle_"+str(checks.size()),owner.pending_count()==0 and owner.active_count()==0 and owner.heights.active_count()==0 and not owner.heights.hinted)

func _observe() -> void:
	var now:=Time.get_ticks_usec();var owner=scene.runtime.current
	frames.append({"at_us":now,"frame_id":Engine.get_process_frames(),"frame_us":0 if previous_us==0 else now-previous_us,"pending":owner.pending_count(),"active_slots":owner.active_count(),"tick":owner.completed_tick,"state_seq":owner.completed_state_seq,"time_s":owner.advanced_time_s,"collision_active":owner.heights.active_count(),"window_focused":DisplayServer.window_is_focused(),"max_fps":Engine.max_fps,"low_processor_usage":OS.low_processor_usage_mode,"low_processor_sleep_us":OS.low_processor_usage_mode_sleep_usec})
	previous_us=now
	frames.back().render_objects=Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	frames.back().render_primitives=Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	frames.back().render_draw_calls=Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	for id in outstanding.keys():
		var result: Dictionary=owner.take_result(id)
		if not result.is_empty():terminals.append({"id":id,"result":result,"admitted_at_us":outstanding[id],"observed_at_us":now});outstanding.erase(id)
	if sampling and not collecting:collecting=true;RenderingServer.call_on_render_thread(_timestamps_render)

func _timestamps_render() -> void:
	var frame:=device.get_captured_timestamps_frame()
	if frame!=seen_capture:
		seen_capture=frame;var starts: Dictionary={};var spans: Array=[]
		for i in device.get_captured_timestamps_count():
			var label:=device.get_captured_timestamp_name(i)
			if label.ends_with("_start"):starts[label.trim_suffix("_start")]={"gpu_ns":device.get_captured_timestamp_gpu_time(i),"cpu_us":device.get_captured_timestamp_cpu_time(i)}
			elif label.ends_with("_end"):
				var key:=label.trim_suffix("_end")
				if starts.has(key):spans.append({"label":key,"gpu_ns":device.get_captured_timestamp_gpu_time(i)-int(starts[key].gpu_ns),"cpu_marker_us":device.get_captured_timestamp_cpu_time(i)-int(starts[key].cpu_us)});starts.erase(key)
		if not spans.is_empty():gpu_samples.append({"frame":frame,"spans":spans})
	call_deferred("_collected")
func _collected() -> void:collecting=false

func _read(field: String) -> PackedByteArray:
	read_done=false;RenderingServer.call_on_render_thread(_read_render.bind(field))
	var start:=Time.get_ticks_msec()
	while not read_done and Time.get_ticks_msec()-start<15000:await process_frame
	check("read_"+field,read_done);return read_bytes.duplicate()
func _read_render(field: String) -> void:
	var owner=scene.runtime.current
	var texture: RID=owner.transport.clock_texture if field=="clock" else (owner.state.textures[field] if field in ["rock","obstacle"] else owner.state.textures[field][0])
	if device.texture_get_data_async(texture,0,_read_arrived)!=OK:call_deferred("_read_store",PackedByteArray())
func _read_arrived(bytes: PackedByteArray) -> void:call_deferred("_read_store",bytes)
func _read_store(bytes: PackedByteArray) -> void:read_bytes=bytes;read_done=true

func finish() -> void:
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"pass":not failed,"checks":checks,"case":case_id,"sampling":sampling,"runtime":hardware,"startup":startup,"target":target_witness,"input_open":input_window,"commands":submitted,"terminals":terminals,"frames":frames,"gpu_samples":gpu_samples,"observations":observations,"scope":"Current formal full rendering load; exact G0 dry footprint and 24 straight paused legacy API declarations. Optional observer delegates real executor unchanged and adds total-edit timestamps; no authority source substitution."},"\t"));quit(1 if failed else 0)

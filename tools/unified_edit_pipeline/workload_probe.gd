extends "res://tools/unified_edit_pipeline/baseline_profile.gd"

# The observer records frame-quantized completion bounds; it never changes the
# dispatcher, authority kernels, effect load or physical parameters.
var realtime:=false
var path_mode:="straight"
var input_count:=24
var warmup_frames:=30
var trace: Array=[]
var submitted: Array=[]
var terminals: Array=[]
var controller_events: Array=[]
var collision_events: Array=[]
var seen_controller:={}
var seen_collision:={}
var seen_terminal:={}
var outstanding:={}
var finalizing:=false
var input_open_end:={}
var startup:={}
var target_witness:={}
var tail_start_us:=0

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
		if arg.begins_with("--case="):case_id=arg.trim_prefix("--case=")
		if arg.begins_with("--pattern="):path_mode=arg.trim_prefix("--pattern=")
		if arg=="--sampling":sampling_enabled=true
		if arg=="--wet":wet_target=true
		if arg=="--realtime":realtime=true
	call_deferred("_run")

func _target() -> bool:
	var best:=Vector2i(-1,-1)
	var best_score:=-INF
	for z in range(40,217,16):
		for x in range(32,225,16):
			var minimum:=INF
			var maximum:=-INF
			var min_sand:=INF
			var obstruction:=false
			for dz in range(-20,21):
				for dx in range(-16,17):
					var i: int=(z+dz)*256+x+dx
					var h: float=preview.shadow_domain.water[i]
					minimum=minf(minimum,h);maximum=maxf(maximum,h)
					min_sand=minf(min_sand,preview.shadow_domain.sand[i])
					obstruction=obstruction or preview.shadow_domain.obstacle[i]!=0
			var valid: bool=minimum>0.05 if wet_target else maximum<=0.001
			var score: float=minimum if wet_target else min_sand
			if valid and not obstruction and min_sand>0.05 and score>best_score:
				best=Vector2i(x,z);best_score=score
				target_witness={"cell":best,"water_min_m":minimum,"water_max_m":maximum,"sand_min_m":min_sand,"obstacle":obstruction,"checked_cell_rect":Rect2i(x-16,z-20,33,41)}
	if best.x<0:return false
	input_target=Vector3((best.x+0.5)*0.125-16.0,0,(best.y+0.5)*0.125-16.0)
	return true

func _path(index: int) -> Vector2:
	var base:=Vector2(input_target.x,input_target.z)
	var u:=float(index)/float(input_count-1)
	if path_mode=="overlap":return base+Vector2(0,0.75*sin(u*TAU))
	if path_mode=="corner":
		return base+Vector2(-0.6+1.2*minf(u*2,1.0),-0.6+1.2*maxf(u*2-1.0,0.0))
	return base+Vector2(0,-1.0+2.0*u)

func _fixture(index: int) -> Dictionary:
	var a:=_path(index)
	if case_id in ["dig","fill"]:
		return super.command(index,Vector3(a.x,0,a.y),case_id=="fill")
	var params: Dictionary={"height_m":0.2,"bottom_width_m":1.0,"top_width_m":0.5} if case_id=="wall" else {"trench_width_m":0.5,"depth_m":0.05,"shoulder_width_m":0.5}
	var b:=_path(mini(index+1,input_count-1))
	var value:=Brush.make_command(StringName(case_id+"_v1"),params,a,b,preview.domain.domain_id,preview.generation,preview.command_queue.last_command_id+1,7001,index,preview.completed_ticks,preview.shape_baseline_token)
	value.material_profile_id=&"plain_sand_v1" if case_id=="shovel" else &"molded_v1"
	return value

func _observe_workload() -> void:
	if finalizing:return
	var now:=Time.get_ticks_usec()
	var age:=0
	for admitted_us in outstanding.values():age=maxi(age,now-int(admitted_us))
	trace.append({"at_us":now,"frame_id":Engine.get_process_frames(),"pending":preview.command_queue.pending.size(),"active_slots":preview.async_controller.slots.active_count(),"oldest_outstanding_age_us":age,"tick":preview.completed_ticks,"state_seq":preview.async_controller.state_seq,"time_s":preview.async_controller.actual_time,"collision_pending":preview.async_controller.collision.pending.size(),"collision_active":preview.async_controller.collision.active_count()})
	for row in preview.input_scheduler.terminal:
		var id: int=row.command.command_id
		if seen_terminal.has(id):continue
		seen_terminal[id]=true
		var result: Dictionary=row.duplicate(true)
		result.observed_at_us=now
		result.admitted_at_us=outstanding.get(id,-1)
		outstanding.erase(id)
		terminals.append(result)
	for row in preview.async_controller.events:
		var key: String=String(row.event)+":"+str(row.get("batch_seq",-1))+":"+str(row.frame_id)
		if seen_controller.has(key):continue
		seen_controller[key]=true
		var event: Dictionary=row.duplicate(true);event.observed_at_us=now
		controller_events.append(event)
	for row in preview.async_controller.collision.events:
		var key: String=String(row.event)+":"+str(row.snapshot_seq)+":"+str(row.frame_id)
		if seen_collision.has(key):continue
		seen_collision[key]=true
		var event: Dictionary=row.duplicate(true);event.observed_at_us=now
		collision_events.append(event)
	if sampling_enabled and not collect_pending:
		collect_pending=true
		RenderingServer.call_on_render_thread(_collect_render)

func _run() -> void:
	var boot_us:=Time.get_ticks_usec()
	preview=load(scene_path).instantiate();preview.playing=false;root.add_child(preview)
	var deadline:=Time.get_ticks_msec()+60000
	while not preview.ready_for_ticks and preview.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	startup={"load_to_ready_us":Time.get_ticks_usec()-boot_us,"ready_at_us":Time.get_ticks_usec()}
	check("ready",preview.ready_for_ticks and preview.async_backend_ready and preview.last_error.is_empty())
	if failed:await _finish();return
	check("fixed_full_footprint_target",_target())
	check("known_pattern",path_mode in ["straight","corner","overlap"])
	if failed:await _finish();return
	await preview.get_node("Interface/PerformancePanel").stop_sampling()
	hardware={"engine":Engine.get_version_info(),"adapter":RenderingServer.get_video_adapter_name(),"driver":RenderingServer.get_current_rendering_driver_name(),"window":DisplayServer.window_get_size(),"viewport":root.get_visible_rect().size,"vsync":DisplayServer.window_get_vsync_mode(),"profile":preview._runtime_configuration_signature(),"effective_profile":preview._effective_profile_request(),"loaded_gdscript_sha256":loaded_code()}
	RenderingServer.call_on_render_thread(_configure_render)
	while not configure_done:await process_frame
	hardware.scope="24 inputs, one offered per process frame; frame-bounded completion/collision observation; no framebuffer visibility claim"
	preview.async_controller.collision.observe=true
	for i in warmup_frames:await process_frame
	check("warmup_drained",await super.idle())
	startup.warmup_frames=warmup_frames
	process_frame.connect(_observe_workload)
	var start_tick: int=preview.completed_ticks
	var start_time: float=preview.async_controller.actual_time
	var start_us:=Time.get_ticks_usec()
	preview.playing=realtime
	for i in input_count:
		var value:=_fixture(i)
		var before:=Time.get_ticks_usec()
		var error: StringName=preview.input_scheduler.submit(value)
		check("admission_%d"%i,error.is_empty())
		if not error.is_empty():break
		outstanding[value.command_id]=before
		submitted.append({"command":value.duplicate(true),"admitted_at_us":before,"admission_return_us":Time.get_ticks_usec(),"index":i})
		await process_frame
	input_open_end={"start_at_us":start_us,"end_at_us":Time.get_ticks_usec(),"start_tick":start_tick,"end_tick":preview.completed_ticks,"start_time_s":start_time,"end_time_s":preview.async_controller.actual_time}
	preview.playing=false
	if case_id in ["wall","shovel"]:check("stroke_end",(await preview.end_shape_stroke()).is_empty())
	tail_start_us=Time.get_ticks_usec()
	check("drained",await super.idle())
	var drained_us:=Time.get_ticks_usec()
	_observe_workload()
	check("all_input_terminals",submitted.size()==input_count and submitted.all(func(row):return seen_terminal.has(row.command.command_id)))
	if realtime:check("water_advances_while_input_open",input_open_end.end_tick>start_tick and input_open_end.end_time_s>start_time)
	var hashes:={}
	for field in ["sand","water","sediment","momentum_x","momentum_z","wetness","compaction","mold_support","clock"]:hashes[field]=digest(await read(field))
	witnesses={"field_sha256":hashes,"drained_at_us":drained_us,"tail_us":drained_us-tail_start_us,"final_tick":preview.completed_ticks,"final_time_s":preview.async_controller.actual_time,"final_state_seq":preview.async_controller.state_seq,"accepted":preview.async_controller.accepted_commands,"rejected":preview.async_controller.rejected_commands,"collision_applied_seq":preview.async_controller.collision.applied_state_seq.duplicate(),"collision_applied_tick":preview.async_controller.collision.applied_sim_tick.duplicate()}
	await _finish()

func _finish() -> void:
	finalizing=true
	if process_frame.is_connected(_observe_workload):process_frame.disconnect(_observe_workload)
	while collect_pending:await process_frame
	check("no_runtime_failure",preview.last_error.is_empty())
	await preview.shutdown()
	check("released",preview.gpu_release_done and preview.solver.rd==null)
	preview.queue_free();await process_frame
	var log: String=FileAccess.get_file_as_string(output.get_basename()+".log")
	check("no_engine_errors",not log.contains("SCRIPT ERROR:") and not log.contains("\nERROR:"))
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"pass":not failed,"checks":checks,"case":case_id,"pattern":path_mode,"wet":wet_target,"realtime":realtime,"sampling":sampling_enabled,"runtime":hardware,"startup":startup,"target":target_witness,"input_open":input_open_end,"commands":submitted,"terminals":terminals,"frames":trace,"controller_events":controller_events,"collision_events":collision_events,"gpu_samples":gpu_samples,"witnesses":witnesses},"\t"))
	quit(1 if failed else 0)

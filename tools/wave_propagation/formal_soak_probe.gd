extends "res://tools/wave_propagation/experience_body_probe.gd"
const Codec=preload("res://scripts/simulation/unified_edit/checkpoint_codec.gd")
var seconds:=300.0
var container_records: Array=[]
var ownership_records: Array=[]
var orphan_baseline:=0

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seconds="):seconds=arg.trim_prefix("--seconds=").to_float()
	super._initialize()
func _process(_delta: float) -> bool:
	if scene!=null and not scene.is_processing():scene.input.poll();scene._update_reflection();scene._sync_gravel_count()
	if Time.get_ticks_msec()-started>7200000:push_error("formal soak timeout");quit(2)
	return false
func snapshot(label: String) -> void:
	await super.snapshot(label)
	current.snapshots[-1].visuals={"gravel_active_count":owner.visuals.active_count,"gravel_visible_count":scene.get_node("GravelLayer").multimesh.visible_instance_count,"foam_enabled":owner.visuals.foam_enabled,"gravel_enabled":owner.visuals.gravel_enabled}
func read_render() -> void:
	var result: Dictionary={}
	for name in ["rock","sand","water","momentum_x","momentum_z","sediment","obstacle","wetness","compaction","mold_support"]:
		var rid: RID=owner.state.textures[name] if name in ["rock","obstacle"] else owner.state.textures[name][0]
		result[name]=owner.state.rd.texture_get_data(rid,0)
	for name in ["sand","sediment","wetness","compaction","mold_support"]:result[name+"_spare"]=owner.state.rd.texture_get_data(owner.state.textures[name][1],0)
	result.control=owner.state.rd.buffer_get_data(owner.transport.control);result.decision=owner.state.rd.buffer_get_data(owner.water.decision)
	result.safety=owner.state.rd.buffer_get_data(owner.water.muscl.buffers.safety)
	var published:=true
	for name in ["sand","water","momentum_x","momentum_z","sediment","wetness","compaction","mold_support"]:published=published and result[name]==owner.state.rd.texture_get_data(owner.views.textures[name],0)
	result.published_matches=published;read_done.call_deferred(result)

func apply_standard(label: String) -> void:
	var params:={"trench_width_m":.5,"depth_m":.15,"shoulder_width_m":.5}
	check(label+":begin",scene.input.begin(&"shovel_v1",Vector2(0,-.5),params,.1,2,.25).accepted)
	check(label+":move",scene.input.move(Vector2(0,.5)).accepted);check(label+":end",scene.input.finish().accepted)
	await idle()
	current[label]={"terminals":scene.input.terminal.duplicate(true),"parameters":params,"policy":2,"speed":.25}

func capture_container(label: String) -> Dictionary:
	var path: String=output.path_join(label+".sandue")
	check(label+":save",(await scene.save_gpu_checkpoint(path)).is_empty())
	var loaded:=Codec.load(path,scene.configuration)
	check(label+":native_validate",loaded.error.is_empty())
	container_records.append({"label":label,"path":path,"sha256":FileAccess.get_sha256(path)})
	return loaded.get("checkpoint",{})

func run_main() -> void:
	scene=load("res://scenes/main.tscn").instantiate();scene.playing=false;scene.water_solver_id=solver_id
	root.add_child(scene)
	var deadline:=Time.get_ticks_msec()+120000
	while (not scene.ready_for_ticks or scene._booting) and scene.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	check("formal_full_boot",scene.ready_for_ticks and not scene._booting and scene.last_error.is_empty())
	if not scene.ready_for_ticks:return
	owner=scene.runtime.current;sources.merge(scene.configuration.sources);scene.floating_props.trace_enabled=true
	scene.set_process(false);scene.hide_hud=true
	while scene.floating_props.busy:await physics_frame
	check("props_active",(await scene.floating_props.set_paused(false,&"user")).error.is_empty())
	scene.floating_props.events.clear();scene.floating_props.events_evicted=0
	current={"id":"main_soak","snapshots":[],"configuration":scene.configuration,"camera":str(scene.player_camera.global_transform),"body_layout":"authored_default_no_position_overrides"}
	await snapshot("initial");await apply_standard("first_edit");await snapshot("edited")
	var restored:=false
	for second in range(1,int(seconds)+1):
		while owner.advanced_time_s<float(second)-.0001 and not failed:
			var remaining: float=float(second)-owner.advanced_time_s
			var batch:=mini(3,maxi(1,int(floor(remaining/(1.0/30.0)))))
			for i in batch:check("request",owner.request_tick(minf(1.0/30.0,remaining-float(i)/30.0)).is_empty())
			await idle()
		if failed:break
		await snapshot("second_%03d"%second)
		if second%30==0:ownership_records.append({"time_s":owner.advanced_time_s,"generation":str(scene.generation),"counts":owner.ownership_counts(),"props_error":String(scene.floating_props.last_error),"static_memory_bytes":int(Performance.get_monitor(Performance.MEMORY_STATIC)),"object_count":int(Performance.get_monitor(Performance.OBJECT_COUNT)),"node_count":int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),"orphan_count":int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))})
		if second==int(seconds/2) and not restored:
			var expected: Dictionary=await capture_container("before_restore")
			var old=owner;scene.set_process(true)
			check("live_restore",(await scene.restore_gpu_checkpoint(output.path_join("before_restore.sandue"))).is_empty())
			deadline=Time.get_ticks_msec()+60000
			while (not scene.ready_for_ticks or not scene.runtime.retired.is_empty()) and scene.last_error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
			check("old_owner_retired",old.released and scene.runtime.retired.is_empty())
			owner=scene.runtime.current;scene.set_process(false)
			while scene.floating_props.busy:await physics_frame
			check("props_resume",(await scene.floating_props.set_paused(false,&"user")).error.is_empty())
			var actual: Dictionary=await capture_container("after_restore")
			if not expected.is_empty() and not actual.is_empty():
				for group in ["fields","spare","material","foam","histories"]:check("restored_raw:"+group,expected.native[group]==actual.native[group])
				var control: PackedByteArray=expected.native.control.duplicate();control.encode_s64(8,actual.generation);check("restored_control_epoch_only",control==actual.native.control)
				for key in ["state_seq","sim_tick","revision","advanced_time_s","ledger"]:check("restored_meta:"+key,expected[key]==actual[key])
			await snapshot("restored");await apply_standard("second_edit");await snapshot("edited_again");restored=true
		if failed:break
	check("complete_five_minutes",not failed and owner.advanced_time_s>=seconds-.0001)
	await capture_container("final");current.ownership=ownership_records;current.containers=container_records;cases.append(current)
	scene.set_process(true);await scene.shutdown();check("formal_released",scene.unified_release_complete())
	var service=root.get_node("BeachScenes")
	if service.active_scene==scene:service.active_scene=null
	root.remove_child(scene);scene.free();scene=null;owner=null
	await process_frame
	check("no_orphan_growth",int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))==orphan_baseline)

func run() -> void:
	if output.is_empty() or solver_id!="muscl_mc_ssprk2_v1" or not is_finite(seconds) or seconds<2 or seconds>300:quit(2);return
	DirAccess.make_dir_recursive_absolute(output);DisplayServer.window_set_size(Vector2i(1280,720));DisplayServer.window_set_title("Formal main correctness soak")
	orphan_baseline=int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	await run_main()
	var drift: Array=[]
	for path in sources:
		if FileAccess.get_sha256(path)!=sources[path]:drift.append(path)
	check("source_integrity",drift.is_empty())
	FileAccess.open(output.path_join("diagnosis.json"),FileAccess.WRITE).store_string(JSON.stringify({"pass":not failed,"suite":"formal_soak","solver_id":solver_id,"requested_time_s":seconds,"checks":checks,"cases":cases,"source_hashes":sources,"source_drift":drift,"engine":Engine.get_version_info(),"adapter":RenderingServer.get_video_adapter_name(),"driver":RenderingServer.get_current_rendering_driver_name(),"window":DisplayServer.window_get_size(),"scope":"Full formal main, complete consumers/Jolt, actual edits and midpoint native restore. Diagnostic completed-time pacing/readbacks are not performance evidence."},"\t"));quit(1 if failed else 0)

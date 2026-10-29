extends "res://tests/integration/unified_edit_playable_probe.gd"
const Routes=preload("res://scripts/beach/unified_scene_routes.gd")
var files: Dictionary={}
func readmit() -> void:
	await process_frame;var began:=Time.get_ticks_msec()
	while not scene.ready_for_ticks and scene.last_error.is_empty() and Time.get_ticks_msec()-began<30000:await process_frame
	check("public_root_readmitted_"+str(checks.size()),scene.ready_for_ticks and not scene._booting and not scene._restoring and not scene._saving)
func boot(solver: String,epoch: int) -> void:
	scene=load(Routes.FORMAL.main).instantiate();scene.playing=false;scene.generation=epoch;scene.water_solver_id=solver;root.add_child(scene)
	var began:=Time.get_ticks_msec()
	while (not scene.ready_for_ticks or scene._booting) and scene.last_error.is_empty() and Time.get_ticks_msec()-began<120000:await process_frame
	check("boot:"+solver,scene.ready_for_ticks and not scene._booting and scene.last_error.is_empty())
	check("actual_dispatch:"+solver,scene.runtime.current.state.water_solver_id==solver and (scene.runtime.current.water.muscl!=null)==(solver=="muscl_mc_ssprk2_v1"))
	if not observations.has("sources"):observations.sources=scene.configuration.sources.duplicate(true)
	else:check("same_release_sources",observations.sources==scene.configuration.sources)
func dispose() -> void:
	var owner=scene.runtime.current;await scene.shutdown();check("owner_released_"+str(checks.size()),owner.released and owner.ownership_counts().values().all(func(value):return value==0))
	var service=root.get_node("BeachScenes")
	if service.active_scene==scene:service.active_scene=null
	root.remove_child(scene);scene.free();scene=null;await process_frame;await process_frame
func save_state(label: String) -> Dictionary:
	await readmit();var path:=output.path_join(label+".sandue");var error: StringName=await scene.save_gpu_checkpoint(path)
	check("save:"+label,error.is_empty());var loaded:=Codec.load(path,scene.configuration);check("validate:"+label,loaded.error.is_empty())
	files[label]={"path":path,"sha256":FileAccess.get_sha256(path)};return loaded.get("checkpoint",{})
func tick_once(label: String) -> void:
	var before: float=scene.runtime.current.advanced_time_s;check("tick_admitted:"+label,scene.runtime.request_tick(1.0/30.0).is_empty());await _idle()
	check("actual_time_advanced:"+label,scene.runtime.current.advanced_time_s>before and scene.runtime.current.fault_reason().is_empty())
func restore_and_compare(label: String,source_label: String) -> void:
	var source: Dictionary=Codec.read_container(files[source_label].path).checkpoint;var owner=scene.runtime.current;var epoch: int=scene.generation
	check("restore:"+label,(await scene.restore_gpu_checkpoint(files[source_label].path)).is_empty());await readmit()
	var began:=Time.get_ticks_msec()
	while not scene.runtime.retired.is_empty() and Time.get_ticks_msec()-began<30000:await process_frame
	check("new_generation_and_retired:"+label,scene.generation>epoch and owner.released and owner.ownership_counts().values().all(func(value):return value==0))
	var actual:=await save_state(label)
	for group in ["fields","spare","material","foam","histories"]:check(label+"/raw/"+group,actual.native[group]==source.native[group])
	var control: PackedByteArray=source.native.control.duplicate();control.encode_s64(8,actual.generation);check(label+"/control",actual.native.control==control)
	for key in ["state_seq","sim_tick","revision","advanced_time_s","ledger","initial_sand_total_m3"]:check(label+"/"+key,actual[key]==source[key])
	check(label+"/explicit_source_provenance",actual.source_provenance.configuration==source.configuration and actual.source_provenance.policies.from_solver==source.configuration.environment.water_numerics.solver_id and actual.source_provenance.policies.to_solver==actual.configuration.environment.water_numerics.solver_id)
func _run() -> void:
	orphan_baseline=int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT));DisplayServer.window_set_size(Vector2i(1280,720))
	await boot("rusanov_first_order_v1",1001);await tick_once("real_fo_source");await save_state("fo_source");await dispose()
	await boot("muscl_mc_ssprk2_v1",2001);await restore_and_compare("fo_to_mc","fo_source");await tick_once("real_mc_source");await save_state("mc_source");await dispose()
	await boot("rusanov_first_order_v1",3001);await restore_and_compare("mc_to_fo","mc_source");await tick_once("fo_after_rollback");await save_state("fo_continued");await dispose()
	check("no_orphan_nodes",int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))<=orphan_baseline);finish()
func finish() -> void:
	FileAccess.open(output.path_join("probe.json"),FileAccess.WRITE).store_string(JSON.stringify({"pass":not failed,"checks":checks,"files":files,"observations":observations,"scope":"Genuine same-release FO source tick/save to MC, then genuine MC source tick/save back to FO; new generation, complete raw bytes and actual future execution"},"\t"));quit(1 if failed else 0)

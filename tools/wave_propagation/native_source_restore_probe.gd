extends "res://tests/integration/unified_edit_playable_probe.gd"
const Routes=preload("res://scripts/beach/unified_scene_routes.gd")
const Router=preload("res://scripts/simulation/unified_edit/checkpoint_router.gd")
var fixture_file:=""
var matched_domain:=false
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--fixtures="):fixture_file=arg.trim_prefix("--fixtures=")
		if arg=="--matched-domain":matched_domain=true
	super._initialize()
func write_native(path: String,value: Dictionary) -> void:
	var payload:=var_to_bytes(value);var file:=FileAccess.open(path,FileAccess.WRITE)
	file.store_buffer(Codec.MAGIC.to_ascii_buffer());file.store_32(1);file.store_32(payload.size());file.store_buffer(Codec.Old.digest(payload));file.store_buffer(payload);file.flush();file.close()
func owned(owner) -> int:
	var count:=0
	for value in owner.ownership_counts().values():count+=value
	return count
func _run() -> void:
	if fixture_file.is_empty() or output.is_empty():quit(2);return
	orphan_baseline=int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT));DisplayServer.window_set_size(Vector2i(1280,720))
	scene=load(Routes.FORMAL[scene_key]).instantiate();scene.playing=false;scene.generation=1001;scene.water_solver_id="muscl_mc_ssprk2_v1";root.add_child(scene)
	var began:=Time.get_ticks_msec()
	while (not scene.ready_for_ticks or scene._booting) and scene.last_error.is_empty() and Time.get_ticks_msec()-began<120000:await process_frame
	check("formal_main_full_boot",scene.ready_for_ticks and not scene._booting and scene.last_error.is_empty())
	if not scene.ready_for_ticks or scene._booting:await _close();return
	observations.sources=scene.configuration.sources.duplicate(true);observations.migrations=[];observations.capture_attempts=[];observations.foreign_rejections=[]
	var fixtures: Array=JSON.parse_string(FileAccess.get_file_as_string(fixture_file))
	for i in fixtures.size():
		var fixture: Dictionary=fixtures[i];var path: String=fixture.path
		check("source_file_pin:"+str(i),FileAccess.get_sha256(path)==fixture.sha256)
		var projected:=Router.load_file(path,scene.configuration)
		if scene_key!="main" and not matched_domain:
			var current_owner=scene.runtime.current;var current_epoch: int=scene.generation;var current_seq: int=current_owner.completed_state_seq
			check("foreign_projection_rejected:"+str(i),not projected.error.is_empty())
			var foreign_error: StringName=await scene.restore_gpu_checkpoint(path)
			check("foreign_keeps_current_domain:"+str(i),not foreign_error.is_empty() and scene.runtime.current==current_owner and scene.runtime.candidate==null and scene.generation==current_epoch and current_owner.completed_state_seq==current_seq and scene.runtime.ready_for_input())
			observations.foreign_rejections.append({"source":fixture,"error":String(foreign_error)});continue
		check("full_source_projection:"+str(i),projected.error.is_empty())
		if not projected.error.is_empty():observations.projection_error=String(projected.error);continue
		var old=scene.runtime.current;var old_epoch: int=scene.generation;var error: StringName=await scene.restore_gpu_checkpoint(path)
		check("actual_native_candidate:"+str(i),error.is_empty())
		if not error.is_empty():observations.restore_error=String(error);continue
		began=Time.get_ticks_msec()
		while not scene.runtime.retired.is_empty() and Time.get_ticks_msec()-began<30000:await process_frame
		# The public root updates ready_for_ticks in its next process phase after
		# restore clears _restoring; wait for that public admission boundary too.
		await process_frame
		while not scene.ready_for_ticks and scene.last_error.is_empty() and Time.get_ticks_msec()-began<30000:await process_frame
		check("root_readmission_after_restore:"+str(i),scene.ready_for_ticks and not scene._restoring and not scene._saving)
		check("old_owner_retired:"+str(i),old.released and owned(old)==0 and scene.generation>old_epoch)
		check("actual_muscl_candidate:"+str(i),scene.runtime.current.water.muscl!=null and scene.runtime.current.state.water_solver_id=="muscl_mc_ssprk2_v1")
		var saved_path:=output.path_join("migrated_%02d.sandue"%i);var save_error: StringName=await scene.save_gpu_checkpoint(saved_path)
		observations.capture_attempts.append({"index":i,"error":String(save_error),"ready":scene.ready_for_ticks,"restoring":scene._restoring,"saving":scene._saving,"capture":scene.runtime.current.last_checkpoint_info.duplicate(true)})
		check("resave_actual_capture:"+str(i),save_error.is_empty())
		var loaded:=Codec.load(saved_path,scene.configuration);check("validate_resaved:"+str(i),loaded.error.is_empty())
		if not loaded.error.is_empty():continue
		var expected: Dictionary=projected.checkpoint;var actual: Dictionary=loaded.checkpoint
		for group in ["fields","spare","material","foam","histories"]:check("raw_%d/%s"%[i,group],actual.native[group]==expected.native[group])
		var control: PackedByteArray=expected.native.control.duplicate();control.encode_s64(8,actual.generation)
		check("raw_control_only_epoch:"+str(i),control==actual.native.control)
		for key in ["state_seq","sim_tick","revision","advanced_time_s","ledger","initial_sand_total_m3","nominal_upper_supply","source_provenance"]:check("metadata_%d/%s"%[i,key],actual[key]==expected[key])
		var gravel: Dictionary=expected.visual_extensions.gravel_v1.duplicate(true)
		if gravel.enabled:gravel.source_generation=actual.generation
		check("gravel_raw_and_population:"+str(i),actual.visual_extensions.gravel_v1==gravel)
		var time_before: float=scene.runtime.current.advanced_time_s;check("continue_tick_admitted:"+str(i),scene.runtime.request_tick(.001).is_empty());await _idle()
		check("continue_with_actual_time:"+str(i),scene.runtime.current.advanced_time_s>time_before and scene.last_error.is_empty())
		observations.migrations.append({"source":fixture,"saved":{"path":saved_path,"sha256":FileAccess.get_sha256(saved_path)},"from_generation":str(old_epoch),"generation":str(scene.generation),"time_s":actual.advanced_time_s,"provenance":actual.source_provenance.duplicate(true)})
	var current=scene.runtime.current;var epoch: int=scene.generation;var seq: int=current.completed_state_seq
	var path:=output.path_join("current.sandue");check("negative_fixture_capture",(await scene.save_gpu_checkpoint(path)).is_empty())
	var captured:=Codec.load(path,scene.configuration)
	for fault in ["unknown_source","unknown_algorithm","nan","identity"]:
		var bad: Dictionary=captured.checkpoint.duplicate(true)
		if fault=="unknown_source":bad.configuration.sources.erase(Router.ConsumerSources.SELF);bad.configuration.configuration_hash=Codec.Config.stable_hash(bad.configuration)
		elif fault=="unknown_algorithm":bad.configuration.environment.water_numerics.solver_id="unknown";bad.configuration.configuration_hash=Codec.Config.stable_hash(bad.configuration)
		elif fault=="nan":bad.native.fields.water.encode_float(0,NAN)
		else:bad.native.control.encode_s64(8,bad.generation+1)
		var bad_path:=output.path_join("rejected_"+fault+".sandue");write_native(bad_path,bad)
		var error: StringName=await scene.restore_gpu_checkpoint(bad_path)
		check("reject_before_candidate:"+fault,not error.is_empty() and scene.runtime.current==current and scene.runtime.candidate==null and scene.generation==epoch and current.completed_state_seq==seq and scene.runtime.ready_for_input())
	check("all_fixture_routes_executed",(observations.migrations.size() if scene_key=="main" or matched_domain else observations.foreign_rejections.size())==fixtures.size())
	observations.events=scene.runtime.events.duplicate(true);await _close()
func finish() -> void:
	FileAccess.open(output.path_join("probe.json"),FileAccess.WRITE).store_string(JSON.stringify({"pass":not failed,"checks":checks,"observations":observations,"scope":"Actual formal main candidate restore of pinned old native and reconstructed legacy fixtures, complete raw resave, continued MC tick and rejection preserving current domain"},"\t"));quit(1 if failed else 0)

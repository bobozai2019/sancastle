extends SceneTree
const N=preload("res://scripts/simulation/unified_edit/numerics_checkpoint_sources.gd")
const Router=preload("res://scripts/simulation/unified_edit/checkpoint_router.gd")
const Config=N.Config
const Codec=N.Codec
var output:=""
var target_file:=""
var rows: Array=[]
var failed:=false
func check(label: String,okay: bool,detail: Dictionary={}) -> void:
	rows.append({"label":label,"pass":okay,"detail":detail});failed=failed or not okay;print("MIGRATION ",label," ",okay)
func refresh(configuration: Dictionary) -> Dictionary:
	var value:=configuration.duplicate(true)
	for path in value.sources:value.sources[path]=FileAccess.get_sha256(path)
	value.configuration_hash=Config.stable_hash(value);return value
func raw_equal(first: Dictionary,second: Dictionary) -> bool:
	return first.native==second.native and first.ledger==second.ledger and first.advanced_time_s==second.advanced_time_s and first.sim_tick==second.sim_tick and first.revision==second.revision and first.state_seq==second.state_seq
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
		if arg.begins_with("--targets="):target_file=arg.trim_prefix("--targets=")
	if output.is_empty() or FileAccess.file_exists(output):quit(2);return
	var loaded:=N._load_catalog();check("baked_catalog_identity",loaded.error.is_empty())
	if not loaded.error.is_empty():finish();return
	var targets: Array=bytes_to_var(FileAccess.get_file_as_bytes(target_file));var all_targets: Array=[]
	for row in targets:
		var target:=refresh(row.configuration);check("current_target:"+row.scene,Config.validate(target,true).is_empty());all_targets.append(target)
	var source_cases: Array=[]
	for known in loaded.catalog.native_sources:
		var path: String=known.fixture.path
		var available: bool=FileAccess.file_exists(path) and FileAccess.get_sha256(path)==known.fixture.sha256
		var item:={"fixture":known.fixture,"available":available,"target_matches":[],"mapping_change_counts":[]}
		for i in all_targets.size():
			for mapping in known.mappings:
				if N.parameters(known.configuration)==mapping.source_parameters and N.parameters(all_targets[i])==mapping.target_parameters:item.target_matches.append(i);item.mapping_change_counts.append(mapping.changes.size())
		if available:
			var source:=Codec.read_container(path);check("known_container:"+path,source.error.is_empty())
			if source.error.is_empty():
				for index in item.target_matches:
					var projected:=Router.load_file(path,all_targets[index])
					check("known_native_projection:"+path+":"+str(index),projected.error.is_empty() and raw_equal(projected.get("checkpoint",{}),source.checkpoint),{"error":String(projected.error)})
					if projected.error.is_empty():
						check("source_configuration_and_parameter_changes_preserved:"+path,projected.checkpoint.source_provenance.configuration==source.checkpoint.configuration and projected.checkpoint.source_provenance.policies.has("parameter_changes"))
				if item.target_matches.is_empty():
					var rejected:=Router.load_file(path,all_targets[0]);item.current_projection_error=String(rejected.error)
					check("unmatched_parameters_not_silently_rebound:"+path,not rejected.error.is_empty(),{"error":String(rejected.error),"note":"Compatibility still pending for this source; this rejection is not a successful migration."})
		else:item.note="Original fixture missing; exact configuration retained in baked catalog; no fabricated original success."
		source_cases.append(item)
	# Current same-release source: save a known source checkpoint with its own
	# valid configuration, then project to the other algorithm and back.
	var current_source: Dictionary={}
	for item in source_cases:
		if item.available and not item.target_matches.is_empty():current_source=Codec.read_container(item.fixture.path).checkpoint;break
	if current_source.is_empty():check("available_native_source_for_same_release_fixture",false);finish(source_cases);return
	var target: Dictionary=all_targets[source_cases.filter(func(item):return item.available and not item.target_matches.is_empty())[0].target_matches[0]]
	var first:=Router.load_file(source_cases.filter(func(item):return item.available and not item.target_matches.is_empty())[0].fixture.path,target)
	if not first.error.is_empty():check("same_release_fixture_projection",false);finish(source_cases);return
	var mc: Dictionary=first.checkpoint;var fo_config:=target.duplicate(true);fo_config.environment.water_numerics.solver_id=Config.Numerics.FIRST_ORDER;fo_config.configuration_hash=Config.stable_hash(fo_config)
	var fo:=N.project(mc,fo_config,"");check("same_release_mc_to_fo",fo.error.is_empty() and raw_equal(mc,fo.get("checkpoint",{})))
	if fo.error.is_empty():
		var back:=N.project(fo.checkpoint,target,"");check("same_release_fo_to_mc",back.error.is_empty() and raw_equal(mc,back.get("checkpoint",{})))
		check("provenance_original_and_parent",back.error.is_empty() and back.checkpoint.source_provenance.configuration==fo_config and back.checkpoint.source_provenance.policies.parent_provenance==fo.checkpoint.source_provenance)
	var unknown:=mc.duplicate(true);unknown.configuration.environment.water_numerics.solver_id="unknown";unknown.configuration.configuration_hash=Config.stable_hash(unknown.configuration)
	check("unknown_source_algorithm_rejected",N.project(unknown,target,"").error==&"unknown_water_solver_id")
	var corrupt:=mc.duplicate(true);corrupt.native.fields.water.encode_float(0,-1.0);check("corrupt_physical_source_rejected",not N.project(corrupt,fo_config,"").error.is_empty())
	corrupt=mc.duplicate(true);corrupt.native.control.encode_s64(8,corrupt.generation+1);check("corrupt_identity_rejected",not N.project(corrupt,fo_config,"").error.is_empty())
	var changed:=fo_config.duplicate(true);changed.environment.ordinary_cohesion_yield_height_m+=0.001;changed.configuration_hash=Config.stable_hash(changed)
	check("same_release_non_numeric_parameter_rejected",N.project(mc,changed,"").error==&"numerics_parameter_mismatch")
	var old_source:=current_source.duplicate(true);old_source.configuration.environment.unreviewed=true;old_source.configuration.configuration_hash=Config.stable_hash(old_source.configuration)
	check("unlisted_complete_configuration_rejected",N.project(old_source,target,"").error==&"unknown_numerics_source_configuration")
	changed=target.duplicate(true);changed.sources.erase(Router.ConsumerSources.SELF);changed.configuration_hash=Config.stable_hash(changed)
	check("unreviewed_target_source_set_rejected",N.project(current_source,changed,"").error==&"unreviewed_numerics_target_configuration")
	finish(source_cases)
func finish(source_cases: Array=[]) -> void:
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"outcome":"fail" if failed else "pass","checks":rows,"source_cases":source_cases,"catalog_sha256":FileAccess.get_sha256(N.CATALOG),"scope":"Offline source projection and rejection; runtime candidate verification and physical switching separate"},"\t"));quit(1 if failed else 0)

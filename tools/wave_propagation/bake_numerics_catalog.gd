extends SceneTree
# Explicit offline bake. Inputs are fixed by SHA, not supplied by an opened save.
const Sources=preload("res://scripts/simulation/unified_edit/numerics_checkpoint_sources.gd")
const Config=Sources.Config
const PINNED_PATH="res://test_output/wave_propagation/g1_recovery_inspect_01/source_configurations.variant"
const PINNED_SHA="72e3a733ba7abdd743803c1c03d4dacc178605d37e425427b1125a21b4e13751"
var output:=""
var targets_path:=""
var targets_sha:=""
const OLD_SHOVEL="346826e4f0e5203b8425ef854be79be5a49e8a50c796ea6eac772f50a9756f38"
const NEW_SHOVEL="62ff4641dbbe8b866da6954579cda64d608cb1cd0c308aa0c7a807d22bd09ff9"
func differences(first: Variant,second: Variant,path: String="") -> Array:
	var result: Array=[]
	if first is Dictionary and second is Dictionary:
		var keys: Array=first.keys()
		for key in second:
			if key not in keys:keys.append(key)
		for key in keys:
			var next: String=path+"/"+key if not path.is_empty() else key
			if not first.has(key) or not second.has(key):result.append({"path":next,"from":first.get(key),"to":second.get(key),"missing":true})
			else:result.append_array(differences(first[key],second[key],next))
	elif first!=second:result.append({"path":path,"from":first,"to":second})
	return result
func allowed(change: Dictionary) -> bool:
	if change.has("missing"):return false
	var path: String=change.path;var before: Variant=change.from;var after: Variant=change.to;var parts:=path.split("/")
	if parts.size()==3 and parts[0]=="profiles" and parts[2]=="profile_hash":return Sources.Codec.WireHash(before) and Sources.Codec.WireHash(after)
	if parts.size()==4 and parts[0]=="profiles" and parts[2] in ["resource_identity","template"] and parts[3]=="model_sha256":return Sources.Codec.WireHash(before) and Sources.Codec.WireHash(after)
	if parts.size()==4 and parts[0]=="profiles" and parts[2]=="allowed_features":
		if parts[3]=="water_policy" and parts[1] in ["castle_v1","wall_v1","fill_v1","dig_v1","fill_sweep_v1","dig_sweep_v1","shovel_v1"]:return before==[3] and after==[0,1,2,3]
		if parts[3]=="material_policy" and parts[1] in ["castle_v1","wall_v1"]:return before==[1] and after==[0,1]
	if path=="profiles/shovel_v1/version":return before==1 and after==2
	if path=="profiles/shovel_v1/transfer_policy":return before==1 and after==2
	if path=="profiles/shovel_v1/resource_identity/sha256":return before==OLD_SHOVEL and after==NEW_SHOVEL
	if path=="ledger_policy/transfer":return before=="conservative_source_sink_unchanged_v1" and after=="balanced_conservative_or_capped_exact_sink_v2"
	return false
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
		if arg.begins_with("--targets="):targets_path=arg.trim_prefix("--targets=")
		if arg.begins_with("--targets-sha256="):targets_sha=arg.trim_prefix("--targets-sha256=")
	if output.is_empty() or FileAccess.file_exists(output) or FileAccess.get_sha256(PINNED_PATH)!=PINNED_SHA or not Sources.Codec.WireHash(targets_sha) or FileAccess.get_sha256(targets_path)!=targets_sha:push_error("bake_input_identity");quit(1);return
	var original: Dictionary=bytes_to_var(FileAccess.get_file_as_bytes(PINNED_PATH))
	var target_rows: Variant=bytes_to_var(FileAccess.get_file_as_bytes(targets_path))
	if not target_rows is Array or target_rows.size()!=4:push_error("four_formal_targets_required");quit(1);return
	var sources: Array=[];var digests:={}
	for row in original.native_sources:
		var digest:=Config.digest_data(row.configuration)
		if not digests.has(digest):sources.append({"configuration":row.configuration,"fixture":row.fixture,"mappings":[]});digests[digest]=true
	var consumer: Dictionary=original.inherited_consumer_catalog
	for row in [{"configuration":consumer.source_configuration,"fixture":consumer.fixture}]+consumer.additional_sources:
		var digest:=Config.digest_data(row.configuration)
		if not digests.has(digest):sources.append({"configuration":row.configuration,"fixture":row.fixture,"mappings":[]});digests[digest]=true
	var targets: Array=[]
	for row in target_rows:
		var target: Dictionary=row.configuration
		var error:=Config.validate(target,true)
		if not error.is_empty():push_error(error);quit(1);return
		targets.append({"sources":Sources.target_sources(target),"parameters":Sources.parameters(target),"consumer_parameters":Sources.parameters(target,true)})
	for source in sources:
		var validation: Dictionary=source.configuration.duplicate(true);validation.configuration_hash=Config.stable_hash(validation)
		var error:=Config._validate_snapshot(validation,false,source.configuration.ledger_policy)
		if not error.is_empty():push_error("pinned_source_invalid:"+error);quit(1);return
		for target in targets:
			var changes:=differences(Config.canonical(Sources.parameters(source.configuration)),Config.canonical(target.parameters));var reviewed:=true
			for change in changes:reviewed=reviewed and allowed(change)
			if reviewed:source.mappings.append({"source_parameters":Sources.parameters(source.configuration),"target_parameters":target.parameters.duplicate(true),"changes":changes})
		if source.mappings.is_empty():push_error("no_reviewed_target_for_pinned_source:"+str(source.fixture.path));quit(1);return
	var value:={"schema":2,"id":"water_numerics_release_v1","native_sources":sources,"targets":targets,"review":{"scope":"Exact original configurations plus explicit per-source/per-target parameter maps. Only listed derived identities, expanded declared tool admission and the already-current shovel/transfer v2 may differ. Past fields and ledger remain untouched; future operations use the reviewed target.","pinned_archive":{"path":PINNED_PATH,"sha256":PINNED_SHA},"targets":{"path":targets_path,"sha256":targets_sha},"same_release_policy":"identical complete sources and non-numeric parameters","legacy":"existing exact legacy source catalog and validator remain required","authority":"G2/G3 kernels; G4 native-source adapters separately verified; refresh target pins after G6 final sources"}}
	var file:=FileAccess.open(output,FileAccess.WRITE);file.store_buffer(var_to_bytes(value));file.flush();file.close()
	print("NUMERICS_CATALOG ",FileAccess.get_sha256(output)," sources=",sources.size()," targets=",targets.size());quit()

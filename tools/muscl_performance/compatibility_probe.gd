extends SceneTree

const Pipeline=preload("res://scripts/simulation/unified_edit/pipeline.gd")
const Codec=preload("res://scripts/simulation/unified_edit/checkpoint_codec.gd")
const Config=preload("res://scripts/simulation/unified_edit/configuration.gd")
const Router=preload("res://scripts/simulation/unified_edit/checkpoint_router.gd")

func _initialize() -> void:
	var args:=OS.get_cmdline_user_args();var output:=args[0]
	var corpus: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(args[1]))
	var seed:=Codec.read_container(args[2])
	if not seed.error.is_empty():quit(1);return
	var catalog: Dictionary=load("res://assets/unified_edit/default_catalog.tres").instantiate_registry()
	var old: Dictionary=seed.checkpoint.configuration
	var extra:=PackedStringArray(Pipeline.SOURCE_PATHS+Pipeline.ADAPTER_SOURCES)
	extra.append_array(["res://tools/muscl_performance/restart_probe.gd","res://tools/wave_propagation/gpu_probe.gd","res://tools/wave_propagation/native_restart_probe.gd","res://scripts/simulation/unified_edit/momentum_bytes.gd","res://tools/muscl_performance/fixture_upload.gd"])
	var frozen:=Config.freeze(catalog.registry,old.domain_id,old.simulation,old.effects,old.diagnostics,old.environment,extra)
	if not frozen.error.is_empty():quit(1);return
	var results: Array=[];var valid:=true
	for fixture in corpus.fixtures:
		var record:={"original_path":fixture.path,"expected_sha256":fixture.expected_sha256,"available":fixture.has("retained_path")}
		if fixture.has("retained_path"):
			var path: String=fixture.retained_path
			record.retained_path=path;record.hash_matches=FileAccess.get_sha256(path)==fixture.expected_sha256
			valid=valid and record.hash_matches
			var loaded:=Router.load_file(path,frozen.value)
			record.error=String(loaded.error)
			if loaded.error.is_empty():
				var source:=Codec.read_container(path)
				record.projected_native_exact=source.error.is_empty() and loaded.checkpoint.native==source.checkpoint.native
				valid=valid and record.projected_native_exact
		results.append(record)
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"pass":valid,"results":results,"target_sources":frozen.value.sources,"scope":"Actual Router outcomes against available offline-pinned files for the same current native fixture declaration, scalar/packed projects. Missing fixtures are explicit; CPU projection alone does not prove GPU cold migration."},"\t"))
	quit(0 if valid else 1)

extends RefCounted

# Explicit release conversion only. This catalog is baked offline from pinned
# original configurations and reviewed target sources, never from an opened save.
const Codec=preload("res://scripts/simulation/unified_edit/checkpoint_codec.gd")
const Config=preload("res://scripts/simulation/unified_edit/configuration.gd")
const Consumer=preload("res://scripts/simulation/unified_edit/consumer_checkpoint_sources.gd")
const SELF="res://scripts/simulation/unified_edit/numerics_checkpoint_sources.gd"
const CATALOG="res://assets/unified_edit/numerics_source_catalog.variant"
const CATALOG_SHA256="0d20058631d7f8fdaa0083f989a97b092b77e6d71f3585ac92945ddd9ad10350"
const SOURCES=[SELF,CATALOG]

static func parameters(configuration: Dictionary, consumer_rebind: bool=false) -> Dictionary:
	var result: Dictionary=Consumer.parameters(configuration) if consumer_rebind else configuration.duplicate(true)
	for key in ["sources","configuration_hash","diagnostics"]:result.erase(key)
	result.environment.erase("water_numerics")
	return result

static func target_sources(configuration: Dictionary) -> Dictionary:
	var result: Dictionary=configuration.sources.duplicate()
	for path in SOURCES:result.erase(path)
	return result

static func _load_catalog() -> Dictionary:
	if not FileAccess.file_exists(CATALOG) or FileAccess.get_sha256(CATALOG)!=CATALOG_SHA256:return {"error":&"numerics_source_catalog_identity_mismatch"}
	var raw:=FileAccess.get_file_as_bytes(CATALOG)
	if raw.is_empty() or raw.size()>4*1024*1024:return {"error":&"invalid_numerics_source_catalog"}
	var value: Variant=bytes_to_var(raw)
	if not Config.exact(value,["schema","id","native_sources","targets","review"]) or typeof(value.schema)!=TYPE_INT or value.schema!=2 or value.id!="water_numerics_release_v1" or not value.native_sources is Array or value.native_sources.is_empty() or value.native_sources.size()>64 or not value.targets is Array or value.targets.is_empty() or value.targets.size()>32 or not value.review is Dictionary:return {"error":&"invalid_numerics_source_catalog"}
	for row in value.native_sources:
		if not Config.exact(row,["configuration","fixture","mappings"]) or not row.configuration is Dictionary or not Config.exact(row.fixture,["path","sha256"]) or typeof(row.fixture.path)!=TYPE_STRING or not Codec.WireHash(row.fixture.sha256) or not row.mappings is Array or row.mappings.is_empty() or row.mappings.size()>4:return {"error":&"invalid_numerics_source_catalog"}
		for mapping in row.mappings:
			if not Config.exact(mapping,["source_parameters","target_parameters","changes"]) or not mapping.source_parameters is Dictionary or not mapping.target_parameters is Dictionary or not mapping.changes is Array:return {"error":&"invalid_numerics_source_catalog"}
	for row in value.targets:
		if not Config.exact(row,["sources","parameters","consumer_parameters"]) or not row.sources is Dictionary or not row.parameters is Dictionary or not row.consumer_parameters is Dictionary:return {"error":&"invalid_numerics_source_catalog"}
	return {"error":&"","catalog":value}

static func project(value: Dictionary, target: Dictionary, path: String) -> Dictionary:
	var error:=Config.validate(target,true)
	if not error.is_empty():return {"error":error}
	if not value.get("configuration") is Dictionary:return {"error":&"invalid_configuration"}
	var source: Dictionary=value.configuration
	if not source.get("environment") is Dictionary:return {"error":&"invalid_configuration"}
	error=Config.Numerics.configuration_error(source.environment)
	if not error.is_empty():return {"error":error}
	# Existing solver/retention migration does not authorize changing the new
	# timestep policy or attempt budget while restoring a saved simulation.
	if Config.Numerics.cfl(source.environment)!=Config.Numerics.cfl(target.environment) or Config.Numerics.max_attempts(source.environment)!=Config.Numerics.max_attempts(target.environment):return {"error":&"numerics_tuning_mismatch"}
	# Same-release algorithm changes need no historical allowlist: every source
	# hash and every non-numeric parameter must be identical to the validated disk.
	var same_release: bool=source.get("sources")==target.sources
	var trusted: Dictionary={};var mappings: Array=[];var parameter_changes: Array=[]
	if same_release:
		error=Codec.validate(value,source,false)
		if not error.is_empty():return {"error":error}
		if parameters(source)!=parameters(target):return {"error":&"numerics_parameter_mismatch"}
	else:
		var loaded:=_load_catalog()
		if not loaded.error.is_empty():return loaded
		for row in loaded.catalog.native_sources:
			if source==row.configuration:
				trusted=row.fixture.duplicate(true);mappings=row.mappings;break
		if trusted.is_empty():return {"error":&"unknown_numerics_source_configuration"}
		# Only an exact complete historical configuration pin permits normalizing
		# the mixed String/StringName derived hash in this private validation copy.
		error=Codec.validate_pinned_source(value,source)
		if not error.is_empty():return {"error":error}
		var reviewed:=false
		for row in loaded.catalog.targets:
			if target_sources(target)==row.sources and parameters(target)==row.parameters:
				for mapping in mappings:
					if parameters(source)==mapping.source_parameters and parameters(target)==mapping.target_parameters:
						parameter_changes=mapping.changes.duplicate(true);reviewed=true;break
				if not reviewed:return {"error":&"numerics_parameter_mismatch"}
				break
		if not reviewed:return {"error":&"unreviewed_numerics_target_configuration"}
	var result:=value.duplicate(true)
	result.configuration=target.duplicate(true)
	result.source_provenance={"format":"native_v6","path":path,"sha256":FileAccess.get_sha256(path),"configuration":source.duplicate(true),"trusted_fixture":trusted,"original_prefix":[],"policies":{"migration":"water_numerics_release_v1","from_solver":Config.Numerics.solver_id(source.environment),"to_solver":Config.Numerics.solver_id(target.environment),"native":"preserve_v3_raw_bytes","clock":"preserve_actual_complete_f32","parameter_changes":parameter_changes,"future_operations":"reviewed_target_declarations_only_past_ledger_unchanged","parent_provenance":value.source_provenance.duplicate(true)}}
	error=Codec.validate(result,target)
	return {"error":&"","checkpoint":result,"requires_candidate_build":true} if error.is_empty() else {"error":error}

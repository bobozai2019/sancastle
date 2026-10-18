extends RefCounted

# One offline-reviewed native-v6 source configuration. Never trust a signature
# learned from the checkpoint being opened. Exact target source hashes make this
# permission expire whenever a release source changes, pending another review.
const Codec=preload("res://scripts/simulation/unified_edit/checkpoint_codec.gd")
const Config=preload("res://scripts/simulation/unified_edit/configuration.gd")
const SELF="res://scripts/simulation/unified_edit/consumer_checkpoint_sources.gd"
const CATALOG="res://assets/unified_edit/floating_props_source_catalog.variant"
const CATALOG_SHA256="ee2c2b862101110c323e0280bb2b97a2a2e345dddbfb3b08a4d7ee61b84c9991"
const SOURCES=[SELF,CATALOG]

static func parameters(configuration: Dictionary) -> Dictionary:
	var result:=configuration.duplicate(true)
	for key in ["sources","configuration_hash","diagnostics"]:result.erase(key)
	# Model source identity and its derived profile hash are rebound only after
	# every declarative value matches and this release's whole source map passes.
	for profile in result.profiles.values():
		profile.erase("profile_hash");profile.resource_identity.erase("model_sha256")
	return result

static func project(value: Dictionary, target: Dictionary, path: String) -> Dictionary:
	if not FileAccess.file_exists(CATALOG) or FileAccess.get_sha256(CATALOG)!=CATALOG_SHA256:return {"error":&"consumer_source_catalog_identity_mismatch"}
	var bytes:=FileAccess.get_file_as_bytes(CATALOG)
	if bytes.is_empty() or bytes.size()>1048576:return {"error":&"invalid_consumer_source_catalog"}
	var catalog: Variant=bytes_to_var(bytes)
	if not Config.exact(catalog,["schema","id","source_configuration","fixture","target_sources","target_parameters","review"]) or catalog.schema!=2 or catalog.id!="floating_props_consumer_v2" or not catalog.source_configuration is Dictionary or not catalog.target_sources is Dictionary:return {"error":&"invalid_consumer_source_catalog"}
	if value.get("configuration",{}).get("configuration_hash")!=catalog.source_configuration.get("configuration_hash"):return {"error":&"unknown_native_source_configuration"}
	if value.configuration!=catalog.source_configuration:return {"error":&"unknown_native_source_configuration"}
	# The source disk is archival, so validate its known configuration and ALL
	# native fields/counters/ledger/provenance without comparing to today's disk.
	# Historical schema1 hashed mixed String/StringName keys using Variant sort,
	# whose interning order differs between headless and visible processes. The
	# offline-pinned COMPLETE original configuration above is the trust identity.
	# Normalize only its derived hash in a validation copy; native bytes, original
	# configuration/provenance and the source file are preserved unchanged.
	var validation_copy:=value.duplicate(true)
	validation_copy.configuration.configuration_hash=Config.stable_hash(validation_copy.configuration)
	var error:=Codec.validate(validation_copy,validation_copy.configuration,false)
	if not error.is_empty():return {"error":error}
	error=Config.validate(target,true)
	if not error.is_empty():return {"error":error}
	var target_sources: Dictionary=target.sources.duplicate()
	for entry in SOURCES:target_sources.erase(entry)
	if target_sources!=catalog.target_sources or parameters(target)!=catalog.target_parameters or parameters(value.configuration)!=catalog.target_parameters:return {"error":&"unreviewed_consumer_target_configuration"}
	var result:=value.duplicate(true)
	result.configuration=target.duplicate(true)
	result.source_provenance={"format":"native_v6","path":path,"sha256":FileAccess.get_sha256(path),"configuration":value.configuration.duplicate(true),"trusted_fixture":catalog.fixture.duplicate(true),"original_prefix":[],"policies":{"migration":catalog.id,"native":"preserve_v3_raw_bytes","clock":"preserve_actual_complete_f32","profiles":"rebind_only_identical_declarative_data_after_exact_source_review","props":"reset_authored_layout_not_serialized","parent_provenance":value.source_provenance.duplicate(true)}}
	error=Codec.validate(result,target)
	return {"error":&"","checkpoint":result,"requires_candidate_build":true} if error.is_empty() else {"error":error}

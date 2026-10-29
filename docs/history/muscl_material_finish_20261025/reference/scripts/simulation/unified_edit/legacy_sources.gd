extends RefCounted

# Read/validate only. No legacy editor, controller, scene, RD or replay is built.
const Old=preload("res://scripts/simulation/edit_validation/frame_pipeline/async_checkpoint_codec.gd")
const Store=preload("res://scripts/simulation/checkpoint_store.gd")
const Recovery=preload("res://scripts/beach/beach_recovery_entry.gd")
const Gravel=preload("res://scripts/visual/gravel_checkpoint_codec.gd")
const Config=preload("res://scripts/simulation/unified_edit/configuration.gd")
const Wire=preload("res://scripts/simulation/unified_edit/protocol.gd")
var _trusted: Dictionary={}
var _ready:=false

func initialize_catalog(path: String, sha256: String) -> StringName:
	if _ready:return &"legacy_sources_already_initialized"
	if not Wire.hash_valid(sha256,true) or not FileAccess.file_exists(path) or FileAccess.get_sha256(path)!=sha256:return &"legacy_catalog_identity_mismatch"
	var file:=FileAccess.open(path,FileAccess.READ)
	if file==null or file.get_length()>1048576:return &"invalid_legacy_source_catalog"
	var catalog: Variant=bytes_to_var(file.get_buffer(file.get_length()))
	if not Config.exact(catalog,["schema","sources"]) or typeof(catalog.schema)!=TYPE_INT or catalog.schema!=1 or not catalog.sources is Array or catalog.sources.is_empty() or catalog.sources.size()>64:return &"invalid_legacy_source_catalog"
	var pending:={}
	for row in catalog.sources:
		if not Config.exact(row,["format","configuration","fixture"]) or not row.format in ["edit5_native3","edit4_native2"] or not row.configuration is Dictionary or row.configuration.is_empty() or not Config.exact(row.fixture,["path","sha256"]) or typeof(row.fixture.path)!=TYPE_STRING or row.fixture.path.is_empty() or not Wire.hash_valid(row.fixture.sha256,true):return &"invalid_legacy_source_catalog"
		var key: String=row.format+":"+Config.digest_data(row.configuration)
		if pending.has(key):return &"duplicate_legacy_source_configuration"
		pending[key]={"configuration":row.configuration.duplicate(true),"fixture":row.fixture.duplicate(true),"format":row.format}
	_trusted=pending;_ready=true
	return &""

func initialize(pinned_fixtures: Array) -> StringName:
	if _ready:return &"legacy_sources_already_initialized"
	if pinned_fixtures.is_empty() or pinned_fixtures.size()>64:return &"invalid_legacy_source_catalog"
	var pending:={}
	for fixture in pinned_fixtures:
		if not Config.exact(fixture,["path","sha256"]) or typeof(fixture.path)!=TYPE_STRING or not Wire.hash_valid(fixture.sha256,true) or not FileAccess.file_exists(fixture.path) or FileAccess.get_sha256(fixture.path)!=fixture.sha256:return &"legacy_fixture_identity_mismatch"
		var loaded:=_read_file(fixture.path)
		if not loaded.error.is_empty():return loaded.error
		var signature: Dictionary=loaded.signature
		var key: String=loaded.format+":"+Config.digest_data(signature)
		pending[key]={"configuration":signature.duplicate(true),"fixture":fixture.duplicate(true),"format":loaded.format}
	_trusted=pending;_ready=true
	return &""

func inspect_file(path: String) -> Dictionary:
	if not _ready:return {"error":&"legacy_sources_not_initialized"}
	var loaded:=_read_file(path)
	if not loaded.error.is_empty():return loaded
	var key: String=loaded.format+":"+Config.digest_data(loaded.signature)
	if not _trusted.has(key):return {"error":&"unknown_legacy_source_configuration"}
	var known: Dictionary=_trusted[key]
	if loaded.signature!=known.configuration:return {"error":&"legacy_source_configuration_mismatch"}
	return inspect_data(loaded.checkpoint,loaded.format,known.configuration,path,FileAccess.get_sha256(path),loaded.get("enable_erosion",true))

func inspect_data(value: Dictionary, format: String, signature: Dictionary, path: String="", file_sha256: String="", enable_erosion: bool=true) -> Dictionary:
	var key:=format+":"+Config.digest_data(signature)
	if not _ready or not _trusted.has(key) or _trusted[key].configuration!=signature:return {"error":&"unknown_legacy_source_configuration"}
	var error:=validate_data(value,format,signature,enable_erosion)
	if not error.is_empty():return {"error":error}
	return {"error":&"","format":format,"checkpoint":value.duplicate(true),"enable_erosion":enable_erosion,"requires_candidate_build":true,"provenance":{"format":format,"path":path,"sha256":file_sha256,"configuration":signature.duplicate(true),"trusted_fixture":_trusted[key].fixture.duplicate(true)}}

static func _read_file(path: String) -> Dictionary:
	var file:=FileAccess.open(path,FileAccess.READ)
	if file==null:return {"error":&"open_failed"}
	if file.get_length()<48 or file.get_length()>48+Old.MAX_BYTES:return {"error":&"invalid_legacy_file_size"}
	var magic:=file.get_buffer(8).get_string_from_ascii();file.close()
	if magic==Old.MAGIC:
		var loaded:=Old.load(path)
		if not loaded.error.is_empty():return loaded
		return {"error":&"","format":"edit5_native3","checkpoint":loaded.checkpoint,"signature":loaded.checkpoint.configuration,"enable_erosion":loaded.checkpoint.simulation.enable_erosion}
	if magic==Store.MAGIC:
		var loaded:=Store.load(path)
		if not loaded.error.is_empty():return loaded
		var value: Dictionary=loaded.checkpoint
		if value.get("gpu_beach_edit",{}).get("version")!=4 or value.get("gpu_beach_native",{}).get("version")!=2:return {"error":&"unsupported_legacy_pipeline_version"}
		var signature: Variant=value.gpu_beach_edit.get("configuration")
		if not signature is Dictionary:return {"error":&"invalid_legacy_configuration"}
		var error:=validate_data(value,"edit4_native2",signature,loaded.enable_erosion)
		if not error.is_empty():return {"error":error}
		return {"error":&"","format":"edit4_native2","checkpoint":value,"signature":signature,"enable_erosion":loaded.enable_erosion}
	return {"error":&"unsupported_checkpoint_family"}

static func validate_data(value: Dictionary, format: String, signature: Dictionary, enable_erosion: bool=true) -> StringName:
	if signature.is_empty():return &"missing_legacy_configuration"
	if format=="edit5_native3":return Old.validate(value,signature)
	if format!="edit4_native2" or value.get("gpu_beach_edit",{}).get("version")!=4 or value.get("gpu_beach_native",{}).get("version")!=2:return &"unsupported_legacy_pipeline_version"
	var error:=Store._validate({"format_version":Store.FORMAT_VERSION,"enable_erosion":enable_erosion,"checkpoint":value,"prefix_commands":[]})
	if not error.is_empty():return error
	error=Recovery.validate_gpu_checkpoint(value,signature)
	if not error.is_empty():return error
	if value.get("enable_structures",false) or not value.get("structures",{}).is_empty() or not value.get("support_loss_events",[]).is_empty():return &"unsupported_legacy_pipeline_history"
	var projection:={"visual_extensions":value.get("visual_extensions",{}),"shadow":value.shadow,"tick":value.tick,"revision":value.revision}
	return Gravel.validate(projection,{},String(value.shadow.domain_id))

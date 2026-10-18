extends RefCounted

# The bundled catalog is an offline validated signature allowlist, never populated
# from the file being opened. Its hash is part of the release source configuration.
const Codec=preload("res://scripts/simulation/unified_edit/checkpoint_codec.gd")
const Legacy=preload("res://scripts/simulation/unified_edit/legacy_sources.gd")
const CATALOG="res://assets/unified_edit/legacy_source_catalog.variant"
const CATALOG_SHA256="cbac0b2c091c09f3506d0a15723d0ff7cd962104918b8eb3827a44a7b57942ff"
const SOURCES=["res://scripts/simulation/unified_edit/checkpoint_router.gd",CATALOG]

static func load_file(path: String, configuration: Dictionary) -> Dictionary:
	var file:=FileAccess.open(path,FileAccess.READ)
	if file==null:return {"error":&"open_failed"}
	if file.get_length()<48:return {"error":&"invalid_file_size"}
	var magic:=file.get_buffer(8).get_string_from_ascii();file.close()
	if magic==Codec.MAGIC:return Codec.load(path,configuration)
	if magic!=Legacy.Old.MAGIC and magic!=Legacy.Store.MAGIC:return {"error":&"unsupported_checkpoint_family"}
	var source:=Legacy.new()
	var error:=source.initialize_catalog(CATALOG,CATALOG_SHA256)
	if not error.is_empty():return {"error":error}
	var inspected:=source.inspect_file(path)
	if not inspected.error.is_empty():return inspected
	return Codec.project_validated_legacy(inspected,configuration)

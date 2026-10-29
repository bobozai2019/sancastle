extends RefCounted

const PATHS := {&"castle_v1": "res://assets/brushes/castle_v1.tres", &"wall_v1": "res://assets/brushes/wall_v1.tres", &"shovel_v1": "res://assets/brushes/shovel_v1.tres"}
const Definition = preload("res://scripts/sand/brushes/brush_definition.gd")
var definitions: Dictionary = {}
var _definition_hashes: Dictionary = {}

func definition(id: StringName):
	if not PATHS.has(id): return null
	if not definitions.has(id):
		var loaded = load(PATHS[id])
		if not loaded is Definition or not loaded.validate_definition().is_empty(): return null
		definitions[id] = loaded
		_definition_hashes[id] = loaded.definition_hash()
	var resource = definitions[id]
	if resource.resource_path != PATHS[id] or resource.definition_hash() != _definition_hashes[id] or not resource.validate_definition().is_empty(): return null
	return resource

func validate_identity(id: StringName, hash: String, template_hash: String = "") -> StringName:
	var resource = definition(id)
	if resource == null: return &"unknown_brush"
	if hash != resource.definition_hash(): return &"template_mismatch"
	if id == &"castle_v1":
		if template_hash.is_empty() or template_hash != resource.template_hash(): return &"template_mismatch"
	elif not template_hash.is_empty(): return &"template_mismatch"
	return &""

class_name SandcastleBrushDefinition
extends Resource

const Spec = preload("res://scripts/sand/brushes/brush_spec.gd")
@export var schema_version := 2
@export var brush_id: StringName
@export var operation: StringName
@export var default_params: Dictionary = {}
@export var param_ranges: Dictionary = {}
@export var max_add_m3 := 0.0
@export var max_transfer_m3 := 0.0
@export var template_id: StringName
@export_file("*.rgba32f") var template_path := ""
@export var material_profile_id: StringName = &"plain_sand_v1"

func validate_definition() -> StringName:
	var all: Dictionary = Spec.specification().get("brushes", {})
	if schema_version != 2: return &"unsupported_brush_version"
	if not all.has(String(brush_id)): return &"unknown_brush"
	var expected: Dictionary = all[String(brush_id)]
	if String(operation) != expected.operation or default_params != expected.default or param_ranges != expected.ranges: return &"invalid_command"
	if max_add_m3 != expected.max_add_m3 or max_transfer_m3 != expected.max_transfer_m3: return &"budget_exceeded"
	if material_profile_id != &"plain_sand_v1": return &"material_candidate_invalid"
	if brush_id == &"castle_v1" and String(template_id) != expected.template_id: return &"template_mismatch"
	return &""

func definition_hash() -> String:
	return FileAccess.get_sha256(resource_path) if not resource_path.is_empty() else ""

func template_hash() -> String:
	return FileAccess.get_sha256(template_path) if not template_path.is_empty() and FileAccess.file_exists(template_path) else ""

@tool
extends EditorExportPlugin

func _get_name() -> String:
	return "SandcastleRuntimeSources"

func _export_file(path: String, _type: String, _features: PackedStringArray) -> void:
	# ResourceLoader still needs the imported GPU resource. FileAccess separately
	# needs the exact original bytes for profile hashes, images and GLSL compilation.
	# include_filter alone does not preserve originals of imported resources.
	if not path.begins_with("res://assets/") and not path.begins_with("res://scripts/") and not path.begins_with("res://shaders/") and not path.begins_with("res://tests/visual_water_alignment/prototypes/"):
		return
	if path.get_extension() in ["png", "jpg", "webp", "glsl"] and FileAccess.file_exists(path + ".import"):
		add_file(path, FileAccess.get_file_as_bytes(path), false)

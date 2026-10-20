@tool
extends EditorExportPlugin

# ResourceLoader consumes the normal exported resources. FileAccess also needs
# original bytes for presentation validation, configuration hashes and compute.
const SOURCE_ROOTS = [
	"res://assets", "res://scripts", "res://shaders", "res://scenes",
	"res://tests/visual_water_alignment/prototypes",
]
const SOURCE_EXTENSIONS = [
	"gd", "tscn", "tres", "res", "gdshader", "gdshaderinc", "glsl", "glslinc",
	"json", "bin", "variant", "rgba32f", "f32", "png", "jpg", "webp",
	"ttf", "otf",
]

func _get_name() -> String:
	return "SandcastleRuntimeSources"

func _export_begin(_features: PackedStringArray, _is_debug: bool, _path: String, _flags: int) -> void:
	add_file("res://project.godot", FileAccess.get_file_as_bytes("res://project.godot"), false)
	for path in SOURCE_ROOTS:
		_add_sources(path)

func _add_sources(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		push_error("Cannot export runtime sources: " + path)
		return
	for file in directory.get_files():
		if file.get_extension() in SOURCE_EXTENSIONS:
			var source := path.path_join(file)
			add_file(source, FileAccess.get_file_as_bytes(source), false)
	for child in directory.get_directories():
		_add_sources(path.path_join(child))

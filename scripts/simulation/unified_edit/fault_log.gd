extends Node

# Main-thread diagnostic sink. Each record is flushed before returning.
const Layout = preload("res://scripts/simulation/unified_edit/layout.gd")
static var log_path := ""
static var write_failed := false

func _ready() -> void:
	var engine_log := ProjectSettings.globalize_path(str(ProjectSettings.get_setting("debug/file_logging/log_path", "user://logs/godot.log")))
	var arguments := OS.get_cmdline_args()
	for index in arguments.size():
		if arguments[index] == "--log-file" and index + 1 < arguments.size(): engine_log = arguments[index + 1]
	write_event("startup", {"engine": Engine.get_version_info(), "os": OS.get_name(),
		"renderer": RenderingServer.get_current_rendering_method(),
		"driver": RenderingServer.get_current_rendering_driver_name(),
		"gpu": RenderingServer.get_video_adapter_name(),
		"vendor": RenderingServer.get_video_adapter_vendor(),
		"api_version": RenderingServer.get_video_adapter_api_version(),
		"executable": OS.get_executable_path(), "main_scene": ProjectSettings.get_setting("application/run/main_scene"),
		"engine_log": engine_log})

static func write_event(event: String, data: Dictionary = {}) -> void:
	if log_path.is_empty():
		var root := ProjectSettings.globalize_path("res://") if OS.has_feature("editor") else OS.get_executable_path().get_base_dir()
		var directory := root.path_join("logs")
		log_path = directory.path_join("startup_%s_%s.jsonl" % [str(Time.get_unix_time_from_system()).replace(".", "_"), OS.get_process_id()])
		if DirAccess.make_dir_recursive_absolute(directory) != OK:
			write_failed = true
		print("[sandcastle diagnostic log] ", log_path)
	var row := {"event": event, "utc": Time.get_datetime_string_from_system(true), "ticks_usec": Time.get_ticks_usec(), "data": data}
	var line := JSON.stringify(row)
	if not write_failed:
		var file := FileAccess.open(log_path, FileAccess.READ_WRITE if FileAccess.file_exists(log_path) else FileAccess.WRITE)
		if file != null:
			file.seek_end(); file.store_line(line); file.flush()
			return
		write_failed = true
	printerr("[sandcastle diagnostic log unavailable] ", log_path, " ", line)

static func receipt(bytes: PackedByteArray) -> Dictionary:
	var result := {"byte_count": bytes.size(), "raw_hex": bytes.hex_encode()}
	# Decode independently of protocol acceptance, including rejected FATAL seq=0.
	if bytes.size() >= Layout.COMPLETION_BYTES:
		for key in Layout.COMPLETION_U32: result[key] = bytes.decode_u32(Layout.COMPLETION_U32[key])
		for key in Layout.COMPLETION_I64: result[key] = str(bytes.decode_s64(Layout.COMPLETION_I64[key]))
		for key in Layout.COMPLETION_F32: result[key] = str(bytes.decode_float(Layout.COMPLETION_F32[key]))
	return result

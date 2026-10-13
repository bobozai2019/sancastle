@tool
extends EditorPlugin

class FileLogger extends Logger:
	var log_path: String = "res://logs/editor.log"
	var _is_ready: bool = false
	var _mutex := Mutex.new()

	func _init() -> void:
		_setup()

	func _setup() -> void:
		var dir := DirAccess.open("res://")

		if dir == null:
			push_error("FileLogger init failed: cannot open res://")
			return

		if not dir.dir_exists("logs"):
			var make_dir_result := dir.make_dir("logs")
			if make_dir_result != OK and make_dir_result != ERR_ALREADY_EXISTS:
				push_error("FileLogger init failed: cannot create logs dir: " + str(make_dir_result))
				return

		# WRITE 模式会截断已有文件，确保每次启动编辑器都从空日志开始
		var file := FileAccess.open(log_path, FileAccess.WRITE)
		if file == null:
			push_error("FileLogger init failed: cannot open log file: " + str(FileAccess.get_open_error()))
			return

		file.close()
		_is_ready = true
		_write_raw("=== EditorLogger session start: %s ===" % Time.get_datetime_string_from_system())

	func _write_raw(message: String) -> void:
		if not _is_ready:
			return

		_mutex.lock()
		var file := FileAccess.open(log_path, FileAccess.READ_WRITE)
		if file != null:
			file.seek_end()
			file.store_line(message)
			file.flush()
			file.close()
		_mutex.unlock()

	func _log_message(message: String, error: bool) -> void:
		var level := "STDERR" if error else "STDOUT"
		var timestamp := Time.get_datetime_string_from_system()
		_write_raw("[%s] [%s] %s" % [timestamp, level, message])

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, editor_notify: bool, error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
		var timestamp := Time.get_datetime_string_from_system()
		var parts: Array[String] = []
		parts.append("[%s] [ERROR] type=%s editor_notify=%s" % [timestamp, str(error_type), str(editor_notify)])
		parts.append("origin=%s (%s:%d)" % [function, file, line])

		if not code.is_empty():
			parts.append("code=%s" % code)
		if not rationale.is_empty():
			parts.append("rationale=%s" % rationale)
		if not script_backtraces.is_empty():
			parts.append("backtraces=%s" % str(script_backtraces))

		_write_raw(" | ".join(parts))

var _logger: FileLogger

func _enter_tree() -> void:
	_logger = FileLogger.new()
	OS.add_logger(_logger)
	print("Editor Logger enabled")

func _exit_tree() -> void:
	if _logger:
		OS.remove_logger(_logger)
	_logger = null

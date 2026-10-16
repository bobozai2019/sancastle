extends "res://tests/water_material_natural/rdc_main_smoke.gd"

func _run() -> void:
	var path:String=OS.get_executable_path()
	_check("actual_process_executable_exists",FileAccess.file_exists(path),path)
	_check("actual_process_executable_hash",FileAccess.get_sha256(path).length()==64)
	_finish()
	quit(0 if FileAccess.file_exists(path) else 1)

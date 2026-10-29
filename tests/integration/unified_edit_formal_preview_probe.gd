extends "res://tests/integration/unified_edit_live_preview_probe.gd"
func _entry_path(key: String) -> String:return preload("res://scripts/beach/unified_scene_routes.gd").FORMAL[key]
func _ready_timeout_ms() -> int:return 180000

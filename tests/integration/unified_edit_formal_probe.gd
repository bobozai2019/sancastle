extends "res://tests/integration/unified_edit_playable_probe.gd"

const Routes=preload("res://scripts/beach/unified_scene_routes.gd")
func _entry_path(key: String) -> String:return Routes.FORMAL[key]

func finish() -> void:
	FileAccess.open(output+"/probe.json",FileAccess.WRITE).store_string(JSON.stringify({"pass":not failed,"checks":checks,"observations":observations,"scope":"Formal scene path uses unified root, common tools/water/native save/restore/close and real render; full G6 in-flight matrix and G7 audit remain"},"\t"))
	quit(1 if failed else 0)

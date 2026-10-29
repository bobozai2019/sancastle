extends "res://tests/integration/unified_edit_formal_service_probe.gd"

# Keep existing production-service checks and retain the native session files
# under the runner's copied data tree. No legacy solver snapshot API is used.
func _initialize() -> void:
	super._initialize()
	output=output.path_join("data")
	DirAccess.make_dir_recursive_absolute(output)

func finish() -> void:
	var report:={"pass":not failed,"checks":checks,"observations":observations,"scope":"Production main↔test1_geometry switching, failed target rollback, saved native progress, controls/camera, same-family source consistency and released roots"}
	FileAccess.open(output.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	FileAccess.open(output.get_base_dir().path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	quit(1 if failed else 0)

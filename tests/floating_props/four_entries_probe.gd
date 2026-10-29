extends "res://tests/integration/unified_edit_formal_probe.gd"

var result_path:=""
var inspected_props:=false

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):result_path=arg.trim_prefix("--output=");output=result_path.get_base_dir()
		if arg.begins_with("--case="):scene_key=arg.trim_prefix("--case=")
	call_deferred("_run")

func _idle() -> void:
	if not inspected_props:
		inspected_props=true
		check("only_formal_main_has_default_three",scene.floating_props!=null and scene.floating_props.registry.size()==3 if scene_key=="main" else scene.floating_props==null)
	await super._idle()

func finish() -> void:
	FileAccess.open(result_path,FileAccess.WRITE).store_string(JSON.stringify({"pass":not failed,"checks":checks,"observations":observations,"scope":"G6 four formal entries; same existing common tool/UI/native restore/material binding/queued close regression plus main-only static props."},"\t"));quit(1 if failed else 0)

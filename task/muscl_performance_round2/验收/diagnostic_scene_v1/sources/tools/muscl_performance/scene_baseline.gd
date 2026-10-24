extends "res://tools/parameter_windows/scene_profile.gd"

func _initialize() -> void:
	# Production parameter service supports an explicit isolated config path.
	# Verify it before a scene can boot, and export the actual consumed paths.
	timing_off=true
	super._initialize()

func run() -> void:
	var service=root.get_node("Parameters")
	var expected:=""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--parameter-config="):expected=arg.trim_prefix("--parameter-config=")
	if expected.is_empty() or service._file_path!=expected or service._layout_path.get_base_dir()!=expected.get_base_dir():
		push_error("ROUND2_PARAMETER_ISOLATION_FAILED");quit(1)
		return
	DirAccess.make_dir_recursive_absolute(output)
	FileAccess.open(output.path_join("isolation.json"),FileAccess.WRITE).store_string(JSON.stringify({"parameter_path":service._file_path,"layout_path":service._layout_path,"user_data_dir":OS.get_user_data_dir(),"startup_sha256":FileAccess.get_sha256(service._file_path)},"\t"))
	await super.run()

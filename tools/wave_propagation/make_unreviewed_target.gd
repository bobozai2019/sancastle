extends SceneTree
const N=preload("res://scripts/simulation/unified_edit/numerics_checkpoint_sources.gd")
func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()!=2 or FileAccess.file_exists(args[1]):quit(2);return
	var targets: Array=bytes_to_var(FileAccess.get_file_as_bytes(args[0]))
	for row in targets:
		for path in row.configuration.sources:
			var actual:=FileAccess.get_sha256(path)
			if path not in N.SOURCES and row.configuration.sources[path]!=actual:push_error("unexpected_disk_drift");quit(1);return
			row.configuration.sources[path]=actual
		row.configuration.environment.ordinary_cohesion_yield_height_m+=.001
		row.configuration.configuration_hash=N.Config.stable_hash(row.configuration)
		if not N.Config.validate(row.configuration,true).is_empty():push_error("negative_fixture_not_structurally_valid");quit(1);return
	var file:=FileAccess.open(args[1],FileAccess.WRITE);file.store_buffer(var_to_bytes(targets));file.flush();file.close();quit()

extends SceneTree
const N=preload("res://scripts/simulation/unified_edit/numerics_checkpoint_sources.gd")
const ALLOWED=["res://scripts/beach/beach_scene_service.gd","res://scripts/simulation/unified_edit/configuration.gd","res://scripts/simulation/unified_edit/checkpoint_codec.gd"]
func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()!=3 or FileAccess.file_exists(args[2]) or FileAccess.get_sha256(args[0])!=args[1]:push_error("refresh_input_identity");quit(1);return
	var rows: Array=bytes_to_var(FileAccess.get_file_as_bytes(args[0]));var changes: Array=[]
	for row in rows:
		for path in row.configuration.sources:
			var actual:=FileAccess.get_sha256(path)
			if actual!=row.configuration.sources[path]:
				if path not in ALLOWED and path not in N.SOURCES:push_error("unreviewed_target_source_change:"+path);quit(1);return
				changes.append({"scene":row.scene,"path":path,"from":row.configuration.sources[path],"to":actual})
			row.configuration.sources[path]=actual
		row.configuration.configuration_hash=N.Config.stable_hash(row.configuration)
		if not N.Config.validate(row.configuration,true).is_empty():push_error("refreshed_configuration_invalid");quit(1);return
	var file:=FileAccess.open(args[2],FileAccess.WRITE);file.store_buffer(var_to_bytes(rows));file.flush();file.close()
	FileAccess.open(args[2]+".json",FileAccess.WRITE).store_string(JSON.stringify({"sha256":FileAccess.get_sha256(args[2]),"changes":changes,"scope":"Carry explicit water algorithm through scene construction, plus self-excluded catalog/checker refresh. Declarative parameters unchanged; actual switching tested separately."},"\t"));quit()

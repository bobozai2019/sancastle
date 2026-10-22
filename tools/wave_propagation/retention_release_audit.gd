extends SceneTree
func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()!=2 or FileAccess.file_exists(args[1]):quit(2);return
	var rows: Array=bytes_to_var(FileAccess.get_file_as_bytes(args[0]))
	var checks: Array=[];var sources: Dictionary={};var passed:=rows.size()==4
	for row in rows:
		var okay:=true
		for path in row.configuration.sources:
			okay=okay and FileAccess.get_sha256(path)==row.configuration.sources[path]
			if sources.has(path):okay=okay and sources[path]==row.configuration.sources[path]
			sources[path]=row.configuration.sources[path]
		checks.append({"scene":row.scene,"sources_match_disk":okay});passed=passed and okay
	FileAccess.open(args[1],FileAccess.WRITE).store_string(JSON.stringify({"outcome":"pass" if passed else "fail","checks":checks,"sources":sources},"\t"));quit(0 if passed else 1)

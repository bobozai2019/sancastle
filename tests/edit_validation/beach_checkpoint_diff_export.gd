extends SceneTree
const Store=preload("res://scripts/simulation/checkpoint_store.gd")
var output := ""

func _init() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output=argument.trim_prefix("--output=")
	call_deferred("_run")

func _run() -> void:
	var reports:= {}
	for name in ["before","replayed"]:
		var path:=output.path_join(name+".scp")
		var loaded:=Store.load(path)
		if not loaded.error.is_empty(): push_error(String(loaded.error));quit(1);return
		var checkpoint: Dictionary=loaded.checkpoint
		var exports:= {}
		for group in ["fields","spare"]:
			for field in checkpoint.gpu_beach_native[group]: exports[group+"_"+field]=checkpoint.gpu_beach_native[group][field]
		for field in ["foam_0","foam_1","bed_0","bed_1"]: exports[field]=checkpoint.gpu_beach_native.foam[field]
		exports.front=checkpoint.local_front_history.to_byte_array()
		var files:= {}
		for field in exports:
			var filename: String=name+"_native_"+String(field)+".bin"
			var file:=FileAccess.open(output.path_join(filename),FileAccess.WRITE);file.store_buffer(exports[field]);file.close()
			files[field]={"path":filename,"size":exports[field].size(),"sha256":FileAccess.get_sha256(output.path_join(filename))}
		reports[name]={"source":path,"source_sha256":FileAccess.get_sha256(path),"tick":checkpoint.tick,"generation":checkpoint.shadow.generation,"revision":checkpoint.revision,"index":checkpoint.gpu_beach_native.current_index,"foam_index":checkpoint.gpu_beach_native.foam.current_index,"ledger":checkpoint.gpu_beach_edit.ledger,"prefix":checkpoint.gpu_beach_edit.prefix,"files":files}
	var file:=FileAccess.open(output.path_join("checkpoint_diff_exports.json"),FileAccess.WRITE);file.store_string(JSON.stringify(reports,"\t"));file.close()
	quit(0)

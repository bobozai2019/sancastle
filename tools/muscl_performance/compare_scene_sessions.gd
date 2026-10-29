extends SceneTree

const Codec=preload("res://scripts/simulation/unified_edit/checkpoint_codec.gd")

func _initialize() -> void:
	var args:=OS.get_cmdline_user_args();var left:=args[0];var right:=args[1];var output:=args[2]
	var names:=DirAccess.get_files_at(left);var other:=DirAccess.get_files_at(right)
	names.sort();other.sort()
	var passed:=not names.is_empty() and names==other;var results: Array=[]
	for name in names:
		if not name.ends_with(".sandue"):continue
		var a:=Codec.read_container(left.path_join(name));var b:=Codec.read_container(right.path_join(name))
		var record:={"name":name,"a_sha256":FileAccess.get_sha256(left.path_join(name)),"b_sha256":FileAccess.get_sha256(right.path_join(name)),"containers_valid":a.error.is_empty() and b.error.is_empty(),"differences":[]}
		if record.containers_valid:
			var x: Dictionary=a.checkpoint;var y: Dictionary=b.checkpoint
			if x.keys().size()!=y.keys().size():record.differences.append("checkpoint_keys")
			for field in x:
				if field=="configuration":continue
				if not y.has(field) or x[field]!=y[field]:record.differences.append(field)
			var cx: Dictionary=x.configuration.duplicate(true);var cy: Dictionary=y.configuration.duplicate(true)
			for field in ["sources","configuration_hash"]:cx.erase(field);cy.erase(field)
			if cx!=cy:record.differences.append("configuration_declarations")
		passed=passed and record.containers_valid and record.differences.is_empty();results.append(record)
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"pass":passed and not results.is_empty(),"sessions":results,"scope":"CRC-checked saved session containers: all logical native fields/spare/material/foam/histories, control, counters, ledger, selection and provenance exact. Configuration differs only by declared source identity; each production service restore separately enforces its own full source validation."},"\t"))
	quit(0 if passed and not results.is_empty() else 1)
